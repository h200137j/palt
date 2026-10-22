/// device_screen.dart — one peer, full screen (Beacon).
///
/// Opened by tapping a PeerCard. Paired devices get two tabs: Control (what
/// it's playing, then the actions as tiles) and Activity (the shared history
/// as a chat: sent right in dark amber, received left, pictures as
/// thumbnails). Unpaired devices get the chat only. A composer for text and
/// files sits under both. If the peer drops off the network
/// the thread stays readable but sending is disabled until it returns.
/// Auto-copy (incoming texts → clipboard) is opt-in per device and only
/// offered for trusted devices; "Send clipboard" is always a manual tap.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_filex/open_filex.dart';

import '../../models/history_entry.dart';
import '../../models/peer.dart';
import '../../providers/alias_provider.dart';
import '../../providers/auto_copy_provider.dart';
import '../../providers/device_features_provider.dart';
import '../../features/apps.dart';
import '../../features/device_actions.dart';
import '../../features/media.dart';
import '../../features/phone_features.dart';
import '../../features/remote_input.dart';
import '../../providers/link_provider.dart';
import '../widgets/device_status.dart';
import '../widgets/bluetooth_card.dart';
import '../widgets/commands_card.dart';
import '../widgets/computer_vitals.dart';
import '../widgets/media_player.dart';
import '../widgets/restricted_hint.dart';
import '../../providers/history_provider.dart';
import '../../providers/peer_provider.dart';
import '../../services/transfer_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/media.dart';
import '../widgets/peer_card.dart';
import '../widgets/route_badge.dart';
import 'dock_screen.dart';
import 'touchpad_screen.dart';

/// Broadcast name of the device whose screen is open, so the home screen can
/// skip toasting messages that are already visible in the thread.
final openDeviceNameProvider = StateProvider<String?>((ref) => null);

class DeviceScreen extends ConsumerStatefulWidget {
  /// The device as last seen; kept so the screen survives it going offline.
  final Peer peer;

  const DeviceScreen({super.key, required this.peer});

  @override
  ConsumerState<DeviceScreen> createState() => _DeviceScreenState();
}

class _DeviceScreenState extends ConsumerState<DeviceScreen> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  bool _sending = false;
  int _tab = 0; // 0 Control, 1 Activity
  // Activity counts as read up to here (opening it, or leaving it).
  DateTime _seenActivity = DateTime.now();
  final _pages = PageController();
  String? _sendError;
  late final StateController<String?> _openDevice;

  @override
  void initState() {
    super.initState();
    _openDevice = ref.read(openDeviceNameProvider.notifier);
    WidgetsBinding.instance.addPostFrameCallback((_) => _openDevice.state = widget.peer.deviceName);
    _controller.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    // Riverpod forbids provider writes during unmount; defer by a microtask.
    final openDevice = _openDevice;
    final name = widget.peer.deviceName;
    Future.microtask(() {
      if (openDevice.state == name) openDevice.state = null;
    });
    _controller.dispose();
    _focus.dispose();
    _pages.dispose();
    super.dispose();
  }

  Peer? _livePeer(List<Peer> peers) {
    for (final p in peers) {
      if (p.deviceName == widget.peer.deviceName) return p;
    }
    return null;
  }

  Future<void> _submit(Peer peer) async {
    final text = _controller.text;
    if (text.trim().isEmpty || _sending) return;
    await _send(peer, text, clearDraft: true);
  }

  Future<void> _sendClipboard(Peer peer) async {
    if (_sending) return;
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text ?? '';
    if (text.trim().isEmpty) {
      setState(() => _sendError = 'Clipboard is empty.');
      return;
    }
    if (utf8.encode(text).length > kMaxTextBytes) {
      setState(() => _sendError = 'Clipboard is over ${kMaxTextBytes ~/ 1024} KB. Send it as a file instead.');
      return;
    }
    await _send(peer, text, clearDraft: false);
  }

  /// What this phone shares with one device.
  void _deviceSettings(String name, bool paired) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => Consumer(builder: (ctx, ref, _) {
        final autoCopy = ref.watch(autoCopyProvider).contains(name);
        ref.watch(deviceFeaturesProvider);
        final features = ref.read(deviceFeaturesProvider.notifier);
        Widget toggle(String feature, String title, String subtitle) => SwitchListTile(
              title: Text(title, style: const TextStyle(color: kText)),
              subtitle: Text(subtitle, style: const TextStyle(color: kTextSecondary, fontSize: 12.5)),
              value: features.isOn(feature, name),
              onChanged: paired ? (on) => features.set(feature, name, on) : null,
            );
        return SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(name, style: display(fontSize: 17)),
            if (!paired)
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 8, 20, 0),
                child: Text('Pair with this device to share clipboard and notifications.',
                    style: TextStyle(color: kTextSecondary, fontSize: 12.5)),
              ),
            const SizedBox(height: 6),
            toggle(DeviceFeature.clipboardSend, 'Send my clipboard', 'What you copy here goes to $name'),
            toggle(DeviceFeature.clipboardReceive, 'Take its clipboard', 'What you copy on $name lands here'),
            toggle(DeviceFeature.notifications, 'Show my notifications', 'This phone\'s notifications appear on $name'),
            toggle(DeviceFeature.mediaControls, 'Its media in my controls',
                'What $name plays shows in your quick panel and lock screen'),
            SwitchListTile(
              title: const Text('Copy its messages', style: TextStyle(color: kText)),
              subtitle: const Text('Texts it sends you go to the clipboard',
                  style: TextStyle(color: kTextSecondary, fontSize: 12.5)),
              value: autoCopy,
              onChanged: (_) => _toggleAutoCopy(name, paired, autoCopy),
            ),
            const SizedBox(height: 8),
          ]),
        );
      }),
    );
  }

  Future<void> _toggleAutoCopy(String name, bool paired, bool enabled) async {
    if (!enabled && !paired) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Auto-copy works for paired devices only. Pair from the link icon on the home screen.'),
      ));
      return;
    }
    ref.read(autoCopyProvider.notifier).set(name, !enabled);
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(!enabled ? 'Messages from this device will be copied to the clipboard' : 'Auto-copy off'),
    ));
  }

  Future<void> _send(Peer peer, String text, {required bool clearDraft}) async {
    setState(() {
      _sending = true;
      _sendError = null;
    });
    try {
      await ref.read(transferServiceProvider).sendText(peer, text);
      if (clearDraft) _controller.clear();
    } catch (e) {
      setState(() => _sendError = e.toString());
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final peers = ref.watch(peerListProvider).valueOrNull ?? const [];
    final live = _livePeer(peers);
    final online = live != null;
    final peer = live ?? widget.peer;

    final alias = ref.watch(aliasProvider)[peer.deviceName];
    final displayName = (alias != null && alias.isNotEmpty) ? alias : peer.deviceName;
    final paired = peer.paired;
    final status = ref.watch(peerStatusProvider)[peer.deviceName];
    // Unpaired devices only exchange files and text: no Control tab.

    // History is newest-first, which is exactly what a reversed list wants.
    final thread = _groupTransfers(ref.watch(historyProvider).where((e) => e.partnerName == peer.deviceName).toList());

    final progress = ref.watch(transferProgressProvider);

    final draftBytes = utf8.encode(_controller.text).length;
    final tooLong = draftBytes > kMaxTextBytes;
    final canSend = online && !_sending && _controller.text.trim().isNotEmpty && !tooLong;

    final notice = !online
        ? '$displayName is offline. Sending resumes when it reappears.'
        : tooLong
            ? 'Too long for a message (${(draftBytes / 1024).toStringAsFixed(1)} of ${kMaxTextBytes ~/ 1024} KB). Send it as a file instead.'
            : _sendError;

    final Widget threadView = thread.isEmpty && progress == null
        ? _EmptyThread(online: online)
        : ListView.builder(
            reverse: true,
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
            itemCount: thread.length + (progress != null ? 1 : 0),
            itemBuilder: (context, i) {
              if (progress != null) {
                if (i == 0) return _ProgressBubble(progress: progress);
                i--;
              }
              final entry = thread[i];
              // Reversed list: the day header sits above the oldest entry of
              // each day, i.e. when the next (older) item is from a
              // different day.
              final older = i + 1 < thread.length ? thread[i + 1] : null;
              final showDay = older == null || _dayLabel(older.timestamp) != _dayLabel(entry.timestamp);
              return Column(
                // Stretch so each bubble can align left/right.
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (showDay) _DayDivider(label: _dayLabel(entry.timestamp)),
                  _Bubble(entry: entry),
                ],
              );
            },
          );

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        toolbarHeight: 64,
        actions: [
          IconButton(
            tooltip: 'Device settings',
            icon: const Icon(Icons.tune_rounded, color: kTextSecondary),
            onPressed: () => _deviceSettings(peer.deviceName, paired),
          ),
          const SizedBox(width: 4),
        ],
        title: GestureDetector(
          onLongPress: () => showRenameDialog(context, ref, peer),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(displayName,
                  style: display(fontSize: 20, fontWeight: FontWeight.w800),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
              const SizedBox(height: 3),
              Row(
                children: [
                  if (online) ...[
                    RouteBadge(route: peer.via, ip: peer.ipAddress),
                    const SizedBox(width: 10),
                  ],
                  Flexible(
                    child: Text(
                      !online
                          ? 'offline'
                          : [
                              if (status != null && status.battery >= 0) '${status.battery}%',
                              if (status != null && networkLabel(status).isNotEmpty) networkLabel(status),
                              if (status == null && !peer.viaRelay) peer.ipAddress,
                            ].join('   '),
                      style: mono(fontSize: 11),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      body: DecoratedBox(
        decoration: const BoxDecoration(gradient: kPageGlow),
        child: SafeArea(
          top: false,
          child: Column(
            children: [
              if (paired)
                _Tabs(
                  selected: _tab,
                  unread: _tab == 1
                      ? 0
                      : thread.where((e) => e.direction == 'incoming' && e.timestamp.isAfter(_seenActivity)).length,
                  onSelect: (i) =>
                      _pages.animateToPage(i, duration: const Duration(milliseconds: 260), curve: Curves.easeOutCubic),
                ),
              Expanded(
                // Paired: swipe between Control and Activity.
                child: paired
                    ? PageView(
                        controller: _pages,
                        onPageChanged: (i) => setState(() {
                          _tab = i;
                          _seenActivity = DateTime.now();
                        }),
                        children: [_ControlTab(peer: peer, online: online), threadView],
                      )
                    : threadView,
              ),
              if (notice != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 2),
                  child: Text(
                    notice,
                    style: TextStyle(
                      fontSize: 12,
                      color: online ? kDanger : kTextSecondary,
                    ),
                  ),
                ),
              _Composer(
                controller: _controller,
                focus: _focus,
                enabled: online,
                canSend: canSend,
                sending: _sending,
                hint: online ? 'Send text to $displayName…' : 'Device offline',
                onAttach: () => pickAndSendFiles(ref, peer),
                onPasteSend: () => _sendClipboard(peer),
                onSend: () => _submit(peer),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Control | Activity
class _Tabs extends StatelessWidget {
  final int selected;
  final int unread; // new on Activity since it was last seen
  final ValueChanged<int> onSelect;
  const _Tabs({required this.selected, required this.unread, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    Widget tab(int i, String label, [int count = 0]) {
      final on = i == selected;
      return Expanded(
        child: Material(
          color: on ? kSurfaceRaised : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => onSelect(i),
            child: SizedBox(
              height: 40,
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Text(label,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: on ? FontWeight.w600 : FontWeight.w500,
                      color: on ? kText : kTextSecondary,
                    )),
                if (count > 0) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(gradient: kAccentGradient, borderRadius: BorderRadius.circular(999)),
                    child: Text(count > 99 ? '99+' : '$count',
                        style: const TextStyle(color: kOnAccent, fontSize: 11, fontWeight: FontWeight.w700)),
                  ),
                ],
              ]),
            ),
          ),
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: kSurface, borderRadius: BorderRadius.circular(16)),
      child: Row(children: [tab(0, 'Control'), const SizedBox(width: 4), tab(1, 'Activity', unread)]),
    );
  }
}

/// The remote: what's playing, then the actions as tiles.
class _ControlTab extends ConsumerWidget {
  final Peer peer;
  final bool online;
  const _ControlTab({required this.peer, required this.online});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    VoidCallback? when(VoidCallback f) => online ? f : null;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      children: [
        _NowPlaying(device: peer.deviceName),
        LayoutBuilder(builder: (context, box) {
          const gap = 8.0, h = 78.0;
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _Tile(
                  height: h * 2 + gap,
                  big: true,
                  icon: Icons.attach_file_rounded,
                  label: 'Send files',
                  sub: 'Photos, docs, anything',
                  onTap: when(() => pickAndSendFiles(ref, peer)),
                ),
              ),
              const SizedBox(width: gap),
              Expanded(
                child: Column(children: [
                  Row(children: [
                    Expanded(
                        child: _Tile(
                            height: h,
                            icon: Icons.content_paste_go_rounded,
                            label: 'Clipboard',
                            onTap: when(() => sendClipboardTo(context, ref, peer)))),
                    const SizedBox(width: gap),
                    Expanded(
                        child: _Tile(
                            height: h,
                            icon: Icons.notifications_active_rounded,
                            label: 'Ring',
                            onTap: when(() => sendDevicePacket(context, ref, peer, 'ring')))),
                  ]),
                  const SizedBox(height: gap),
                  Row(children: [
                    Expanded(
                        child: _Tile(
                            height: h,
                            icon: Icons.waving_hand_rounded,
                            label: 'Ping',
                            onTap: when(() => sendDevicePacket(context, ref, peer, 'user_ping')))),
                    const SizedBox(width: gap),
                    Expanded(
                        child: _Tile(
                            height: h,
                            icon: Icons.wifi_rounded,
                            label: 'Share Wi-Fi',
                            onTap: when(() => shareWifiTo(context, peer)))),
                  ]),
                ]),
              ),
            ],
          );
        }),
        if (online) CommandsCard(key: ValueKey(peer.deviceName), peer: peer),
        if (online && DockApps.supported(ref.watch(linkManagerProvider).byName(peer.deviceName))) ...[
          const SizedBox(height: 8),
          SizedBox(
            height: 52,
            child: OutlinedButton.icon(
              onPressed: () =>
                  Navigator.push(context, MaterialPageRoute(builder: (_) => DockScreen(peer: peer))),
              icon: const Icon(Icons.apps_rounded, size: 18),
              label: const Text('App dock'),
              style: OutlinedButton.styleFrom(
                foregroundColor: kText.withValues(alpha: 0.85),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
              ),
            ),
          ),
        ],
        if (online && RemoteInput.supported(ref.watch(linkManagerProvider).byName(peer.deviceName))) ...[
          const SizedBox(height: 8),
          SizedBox(
            height: 52,
            child: OutlinedButton.icon(
              onPressed: () =>
                  Navigator.push(context, MaterialPageRoute(builder: (_) => TouchpadScreen(peer: peer))),
              icon: const Icon(Icons.mouse_rounded, size: 18),
              label: const Text('Touchpad & keyboard'),
              style: OutlinedButton.styleFrom(
                foregroundColor: kText.withValues(alpha: 0.85),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
              ),
            ),
          ),
        ],
        const SizedBox(height: 8),
        SizedBox(
          height: 52,
          child: OutlinedButton.icon(
            onPressed: when(() =>
                shareInternetWith(context, ref, peer, phoneOnline: ref.read(localStatusProvider)?.internet ?? true)),
            icon: const Icon(Icons.public_rounded, size: 18),
            label: Text('Share internet with ${peer.deviceName}', maxLines: 1, overflow: TextOverflow.ellipsis),
            style: OutlinedButton.styleFrom(
              foregroundColor: kText.withValues(alpha: 0.85),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
              textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
            ),
          ),
        ),
        if (ref.watch(peerStatusProvider)[peer.deviceName] case final st? when st.isComputer)
          ComputerVitals(status: st),
        if (online) BluetoothCard(peer: peer),
        if (peer.os != 'android') RestrictedHint(computer: peer.deviceName),
      ],
    );
  }
}

class _Tile extends StatelessWidget {
  final double height;
  final IconData icon;
  final String label;
  final String? sub;
  final bool big;
  final VoidCallback? onTap;
  const _Tile({required this.height, required this.icon, required this.label, this.sub, this.big = false, this.onTap});

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final fg = big ? kOnAccent : (enabled ? kText.withValues(alpha: 0.88) : kTextFaint);
    // Ink paints on the nearest Material, so give it one inside the fade.
    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: Material(
        type: MaterialType.transparency,
        child: Ink(
          decoration: BoxDecoration(
            gradient: big ? kAccentGradient : kTileGradient,
            borderRadius: BorderRadius.circular(big ? 22 : 20),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(big ? 22 : 20),
            onTap: onTap,
            child: SizedBox(
              height: height,
              child: big
                  ? Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Icon(icon, size: 28, color: fg),
                          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(label, style: display(fontSize: 21, fontWeight: FontWeight.w800, color: fg)),
                            if (sub != null)
                              Text(sub!, style: TextStyle(fontSize: 12, color: fg.withValues(alpha: 0.75))),
                          ]),
                        ],
                      ),
                    )
                  : Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(icon, size: 21, color: fg),
                        const SizedBox(height: 6),
                        Text(label,
                            style: TextStyle(fontSize: 12, color: fg), maxLines: 1, overflow: TextOverflow.ellipsis),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

/// What the device is playing (NowPlayingCard) with its volume. Nothing at
/// all when the device reports no media.
class _NowPlaying extends ConsumerStatefulWidget {
  final String device;
  const _NowPlaying({required this.device});

  @override
  ConsumerState<_NowPlaying> createState() => _NowPlayingState();
}

class _NowPlayingState extends ConsumerState<_NowPlaying> {
  double? _volumeDrag;

  void _act(String player, String action, [double value = 0]) =>
      sendMediaAction(ref.read(linkManagerProvider), widget.device, player, action, value);

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(peerMediaProvider)[widget.device];
    if (state == null) return const SizedBox.shrink();
    final p = state.main;
    if (p == null && state.volume < 0) return const SizedBox.shrink();
    final v = _volumeDrag ?? state.volume.toDouble();

    final volume = state.volume < 0
        ? null
        : Row(children: [
            GestureDetector(
              onTap: () => _act('', 'mute'),
              child: Icon(state.muted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                  size: 20, color: state.muted ? kDanger : kText.withValues(alpha: 0.75)),
            ),
            Expanded(
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 3,
                  activeTrackColor: kText.withValues(alpha: 0.85),
                  inactiveTrackColor: Colors.white.withValues(alpha: 0.15),
                  thumbColor: kText,
                  overlayColor: kText.withValues(alpha: 0.1),
                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                ),
                child: Slider(
                  value: v.clamp(0, 100),
                  max: 100,
                  onChanged: (x) => setState(() => _volumeDrag = x),
                  onChangeEnd: (x) {
                    _act('', 'volume', x.roundToDouble());
                    Future.delayed(const Duration(seconds: 1), () {
                      if (mounted) setState(() => _volumeDrag = null);
                    });
                  },
                ),
              ),
            ),
            SizedBox(
                width: 28, child: Text('${v.round()}', style: mono(fontSize: 11, color: kText.withValues(alpha: 0.7)))),
          ]);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: p == null
          ? Container(
              padding: const EdgeInsets.fromLTRB(16, 6, 12, 6),
              decoration: BoxDecoration(color: kTile, borderRadius: BorderRadius.circular(20)),
              child: volume,
            )
          : NowPlayingCard(device: widget.device, player: p, state: state, act: _act, footer: volume),
    );
  }
}

/// History stores one entry per file (id "<transferId>_<name>"); merge
/// adjacent entries from the same transfer back into one bubble.
List<HistoryEntry> _groupTransfers(List<HistoryEntry> entries) {
  String? key(HistoryEntry e) {
    if (e.isText) return null;
    final i = e.id.indexOf('_');
    return i > 0 ? '${e.direction}:${e.id.substring(0, i)}' : null;
  }

  final out = <HistoryEntry>[];
  var i = 0;
  while (i < entries.length) {
    final k = key(entries[i]);
    var j = i + 1;
    while (k != null && j < entries.length && key(entries[j]) == k) {
      j++;
    }
    if (j - i == 1) {
      out.add(entries[i]);
    } else {
      // Newest-first storage reverses file order within a batch; undo that.
      final group = entries.sublist(i, j).reversed.toList();
      final failed = group.where((e) => e.status != 'completed').toList();
      out.add(HistoryEntry(
        id: k!,
        partnerName: group.first.partnerName,
        files: [for (final e in group) ...e.files],
        totalSize: group.fold(0, (sum, e) => sum + e.totalSize),
        direction: group.first.direction,
        timestamp: entries[i].timestamp,
        status: failed.isEmpty ? 'completed' : 'error',
        errorMessage: failed.isEmpty ? null : failed.first.errorMessage,
        durationMillis: group.first.durationMillis,
        route: group.first.route,
      ));
    }
    i = j;
  }
  return out;
}

/// Where a thread file can be opened from, if anywhere. Received files fall
/// back to Downloads/PALT by name (older entries didn't record a path); sent
/// files fall back to the preview kept for pictures.
List<String> _fileCandidates(HistoryFile f, bool outgoing) => [
      if (f.path != null) f.path!,
      if (!outgoing && f.path == null) '$kPaltDownloadDir/${safeFileName(f.name)}',
      if (outgoing && f.preview != null) f.preview!,
    ];

bool _canOpen(HistoryFile f, bool outgoing) => _fileCandidates(f, outgoing).isNotEmpty;

Future<void> _openFile(BuildContext context, HistoryFile f, bool outgoing) async {
  final messenger = ScaffoldMessenger.of(context);
  OpenResult? last;
  for (final path in _fileCandidates(f, outgoing)) {
    last = await OpenFilex.open(path);
    if (last.type == ResultType.done) return;
    if (last.type != ResultType.fileNotFound) break;
  }
  messenger.showSnackBar(SnackBar(
    content: Text(last == null || last.type == ResultType.fileNotFound
        ? '${f.name} is no longer on this phone'
        : 'Could not open ${f.name}: ${last.message}'),
  ));
}

/// "Today" / "Yesterday" / "Mon, 14 Jul"
String _dayLabel(DateTime t) {
  final d = t.toLocal();
  final now = DateTime.now();
  final diff = DateTime(now.year, now.month, now.day).difference(DateTime(d.year, d.month, d.day)).inDays;
  if (diff == 0) return 'Today';
  if (diff == 1) return 'Yesterday';
  const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return '${weekdays[d.weekday - 1]}, ${d.day} ${months[d.month - 1]}';
}

String _formatTime(DateTime t) {
  final l = t.toLocal();
  return '${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}';
}

String _formatSize(int bytes) {
  if (bytes <= 0) return '0 B';
  const suffixes = ['B', 'KB', 'MB', 'GB', 'TB'];
  var i = 0;
  double size = bytes.toDouble();
  while (size >= 1024 && i < suffixes.length - 1) {
    size /= 1024;
    i++;
  }
  return '${size.toStringAsFixed(1)} ${suffixes[i]}';
}

class _DayDivider extends StatelessWidget {
  final String label;
  const _DayDivider({required this.label});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 14, bottom: 8),
        child: Center(
          child: Text(label.toUpperCase(), style: mono(fontSize: 10, color: kTextFaint).copyWith(letterSpacing: 1.2)),
        ),
      );
}

/// A picture or video frame shown inline as a thumbnail of a fixed size.
/// Falls back to the plain file card when it can't be loaded.
class _ImageTile extends StatelessWidget {
  final HistoryFile file;
  final bool outgoing;
  final Widget fallback;
  final VoidCallback onTap;
  final double width, height;
  final BorderRadius radius;
  const _ImageTile({
    required this.file,
    required this.outgoing,
    required this.fallback,
    required this.onTap,
    required this.width,
    required this.height,
    required this.radius,
  });

  Widget _frame(BuildContext context, String src, {Widget? overlay}) {
    final dpr = MediaQuery.of(context).devicePixelRatio;
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: radius,
        child: SizedBox(
          width: width,
          height: height,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.file(
                File(src),
                cacheWidth: (width * dpr).round(),
                fit: BoxFit.cover,
                gaplessPlayback: true,
                errorBuilder: (_, __, ___) => fallback,
              ),
              if (overlay != null) overlay,
            ],
          ),
        ),
      ),
    );
  }

  Widget _videoOverlay(Duration? duration) => Stack(
        children: [
          Center(
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: kBg.withValues(alpha: 0.65),
                shape: BoxShape.circle,
                border: Border.all(color: kText.withValues(alpha: 0.25)),
              ),
              child: const Icon(Icons.play_arrow_rounded, color: kText, size: 24),
            ),
          ),
          if (duration != null && duration > Duration.zero)
            Positioned(
              left: 6,
              bottom: 6,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: kBg.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(formatDuration(duration), style: mono(fontSize: 10, color: kText)),
              ),
            ),
        ],
      );

  @override
  Widget build(BuildContext context) {
    if (isVideoName(file.name)) {
      final video = outgoing ? file.path : (file.path ?? '$kPaltDownloadDir/${safeFileName(file.name)}');
      return FutureBuilder<VideoThumb?>(
        future: video == null ? Future.value(null) : videoThumb(video),
        builder: (context, snap) {
          final thumb = snap.data;
          if (thumb != null) {
            return _frame(context, thumb.path, overlay: _videoOverlay(thumb.duration));
          }
          // Sent video whose temporary copy is gone: the frame kept at send time.
          if (snap.connectionState == ConnectionState.done && outgoing && file.preview != null) {
            return _frame(context, file.preview!, overlay: _videoOverlay(null));
          }
          if (snap.connectionState == ConnectionState.done) return fallback;
          return Container(
            width: width,
            height: height,
            decoration: BoxDecoration(color: kSurfaceRaised, borderRadius: radius),
          );
        },
      );
    }

    // Sent pictures: the kept preview outlives the picker's temporary copy.
    final src = outgoing ? (file.preview ?? file.path) : (file.path ?? '$kPaltDownloadDir/${safeFileName(file.name)}');
    if (src == null) return fallback;
    return _frame(context, src);
  }
}

class _Bubble extends ConsumerWidget {
  final HistoryEntry entry;
  const _Bubble({required this.entry});

  bool _isPicture(HistoryFile f) => isMediaName(f.name) && entry.status == 'completed';

  /// A file as a card: type tile, name, size and an Open button.
  Widget _fileCard(BuildContext context, HistoryFile f, bool outgoing, bool failed) {
    final canOpen = !failed && _canOpen(f, outgoing);
    final tint = failed ? kDanger : (outgoing ? kAccent : kRelay);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: tint.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(Icons.insert_drive_file_outlined, size: 19, color: tint),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  f.name,
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: outgoing ? kOnSent : kText),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(_formatSize(f.size), style: mono(fontSize: 10, color: outgoing ? kSentMeta : kTextFaint)),
              ],
            ),
          ),
          if (canOpen) ...[
            const SizedBox(width: 10),
            SizedBox(
              height: 32,
              child: TextButton(
                onPressed: () => _openFile(context, f, outgoing),
                style: TextButton.styleFrom(
                  backgroundColor: outgoing ? Colors.black.withValues(alpha: 0.22) : kSurfaceRaised,
                  foregroundColor: outgoing ? kOnSent : kText,
                  padding: const EdgeInsets.symmetric(horizontal: 11),
                  minimumSize: Size.zero,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                ),
                child: const Text('Open'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Pictures: one as a 150-wide thumbnail, several as a 3-across grid.
  Widget _pictures(BuildContext context, bool outgoing, bool failed) {
    final files = entry.files;
    Widget tile(HistoryFile f, double w, double h, BorderRadius r) => _ImageTile(
          file: f,
          outgoing: outgoing,
          width: w,
          height: h,
          radius: r,
          onTap: () => _openFile(context, f, outgoing),
          fallback: Container(
              width: w,
              height: h,
              color: kSurfaceRaised,
              child: const Icon(Icons.image_not_supported_outlined, color: kTextFaint, size: 20)),
        );
    if (files.length == 1) {
      return tile(files.first, 150, 190, BorderRadius.circular(14));
    }
    const cell = 72.0, gap = 3.0;
    return SizedBox(
      width: cell * 3 + gap * 2,
      child: Wrap(
        spacing: gap,
        runSpacing: gap,
        children: [for (final f in files) tile(f, cell, cell, BorderRadius.circular(6))],
      ),
    );
  }

  void _showActions(BuildContext context, WidgetRef ref) {
    final outgoing = entry.direction == 'outgoing';
    showModalBottomSheet(
      context: context,
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (entry.isText)
              ListTile(
                leading: const Icon(Icons.copy_rounded),
                title: const Text('Copy'),
                onTap: () {
                  Navigator.pop(sheet);
                  Clipboard.setData(ClipboardData(text: entry.text ?? ''));
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Copied')));
                },
              ),
            if (!entry.isText && entry.files.length == 1 && _canOpen(entry.files.first, outgoing))
              ListTile(
                leading: const Icon(Icons.open_in_new_rounded),
                title: const Text('Open'),
                onTap: () {
                  Navigator.pop(sheet);
                  _openFile(context, entry.files.first, outgoing);
                },
              ),
            ListTile(
              leading: const Icon(Icons.delete_outline_rounded, color: kDanger),
              title: const Text('Delete', style: TextStyle(color: kDanger)),
              subtitle: entry.isText
                  ? null
                  : const Text('Removes it from this chat. Files stay on the phone.',
                      style: TextStyle(fontSize: 12, color: kTextFaint)),
              onTap: () {
                Navigator.pop(sheet);
                ref.read(historyProvider.notifier).removeEntry(entry);
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final outgoing = entry.direction == 'outgoing';
    final failed = entry.status != 'completed';
    final maxWidth = MediaQuery.of(context).size.width * 0.76;
    final picturesOnly = !entry.isText && entry.files.isNotEmpty && entry.files.every(_isPicture);
    final metaColor = outgoing ? kSentMeta : kTextFaint;
    final total = entry.files.fold<int>(0, (n, f) => n + f.size);

    final body = entry.isText
        ? SelectableText(
            entry.text ?? '',
            style: TextStyle(fontSize: 14.5, color: outgoing ? kOnSent : kText, height: 1.35),
          )
        : picturesOnly
            ? _pictures(context, outgoing, failed)
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [for (final f in entry.files) _fileCard(context, f, outgoing, failed)],
              );

    final meta = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (entry.copied) ...[
          Icon(Icons.content_paste_rounded, size: 11, color: metaColor),
          const SizedBox(width: 4),
          Text('copied · ', style: mono(fontSize: 10, color: metaColor)),
        ],
        if (picturesOnly)
          Text('${entry.files.length > 1 ? '${entry.files.length} photos · ' : ''}${_formatSize(total)} · ',
              style: mono(fontSize: 10, color: metaColor)),
        Text(_formatTime(entry.timestamp), style: mono(fontSize: 10, color: metaColor)),
        if (entry.route != null)
          Text(' · ${routeLabel(entry.route)}',
              style: mono(fontSize: 10, color: entry.route == 'relay' ? kRelay : metaColor)),
        if (outgoing && !failed) ...[
          const SizedBox(width: 4),
          Icon(Icons.done_rounded, size: 13, color: metaColor),
        ],
      ],
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: outgoing ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onLongPress: () => _showActions(context, ref),
            child: Container(
              constraints: BoxConstraints(maxWidth: maxWidth),
              padding: picturesOnly ? const EdgeInsets.all(4) : const EdgeInsets.fromLTRB(12, 9, 12, 7),
              decoration: BoxDecoration(
                color: outgoing ? kSent : kTile,
                border: failed ? Border.all(color: kDanger.withValues(alpha: 0.6)) : null,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(18),
                  topRight: const Radius.circular(18),
                  bottomLeft: Radius.circular(outgoing ? 18 : 6),
                  bottomRight: Radius.circular(outgoing ? 6 : 18),
                ),
              ),
              child: Material(
                type: MaterialType.transparency,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    body,
                    Padding(
                      padding: picturesOnly ? const EdgeInsets.fromLTRB(6, 5, 6, 2) : const EdgeInsets.only(top: 4),
                      child: meta,
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (failed)
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 4, 6, 0),
              child: GestureDetector(
                onTap: entry.errorMessage == null
                    ? null
                    : () => ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(entry.errorMessage!)),
                        ),
                child: const Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.error_outline_rounded, size: 13, color: kDanger),
                  SizedBox(width: 4),
                  Text('Not delivered', style: TextStyle(fontSize: 11, color: kDanger)),
                ]),
              ),
            ),
        ],
      ),
    );
  }
}

class _EmptyThread extends StatelessWidget {
  final bool online;
  const _EmptyThread({required this.online});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.forum_outlined, size: 48, color: kTextFaint),
            const SizedBox(height: 14),
            Text('Nothing shared yet', style: display(fontSize: 18)),
            const SizedBox(height: 6),
            const Text(
              'Type a message below, or tap + to send files.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: kTextSecondary, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }
}

/// The transfer in progress, as the newest bubble in the chat.
class _ProgressBubble extends StatelessWidget {
  final TransferProgress progress;
  const _ProgressBubble({required this.progress});

  @override
  Widget build(BuildContext context) {
    final isError = progress.status == TransferStatus.error;
    final isDone = progress.status == TransferStatus.completed;
    final isWaiting = progress.status == TransferStatus.waiting;
    final color = isError ? kDanger : (isDone ? kOk : kAccent);
    final value = progress.total > 0 ? progress.written / progress.total : 0.0;

    final title = isError
        ? 'Transfer failed'
        : isDone
            ? 'Transfer complete'
            : isWaiting
                ? 'Waiting for the other device…'
                : (progress.currentFileName ?? 'Transferring…');
    final detail = isError
        ? (progress.error ?? '')
        : [
            if ((progress.totalItems ?? 1) > 1) 'file ${progress.sentItems ?? 1} of ${progress.totalItems}',
            '${_formatSize(isDone ? progress.total : progress.written)} / ${_formatSize(progress.total)}',
            if (!isDone && !isWaiting && progress.speed != null) '${_formatSize(progress.speed!.round())}/s',
            if (progress.route != null) routeLabel(progress.route),
          ].join(' · ');

    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        width: 250,
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: const BoxDecoration(
          color: kSent,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(18),
            topRight: Radius.circular(18),
            bottomLeft: Radius.circular(18),
            bottomRight: Radius.circular(6),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  isError
                      ? Icons.error_outline_rounded
                      : isDone
                          ? Icons.check_rounded
                          : Icons.swap_vert_rounded,
                  size: 19,
                  color: color,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title,
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: kOnSent),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 2),
                  Text(detail,
                      style: mono(fontSize: 10, color: isError ? kDanger : kSentMeta),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis),
                ]),
              ),
            ]),
            if (!isError) ...[
              const SizedBox(height: 9),
              ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(
                  value: isWaiting ? null : (isDone ? 1.0 : value),
                  minHeight: 4,
                  backgroundColor: Colors.black.withValues(alpha: 0.3),
                  valueColor: AlwaysStoppedAnimation<Color>(color),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focus;
  final bool enabled;
  final bool canSend;
  final bool sending;
  final String hint;
  final VoidCallback onAttach;
  final VoidCallback onPasteSend;
  final VoidCallback onSend;

  const _Composer({
    required this.controller,
    required this.focus,
    required this.enabled,
    required this.canSend,
    required this.sending,
    required this.hint,
    required this.onAttach,
    required this.onPasteSend,
    required this.onSend,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 12),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: kHairline)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          SizedBox(
            width: 44,
            height: 44,
            child: Material(
              color: kTile,
              shape: const CircleBorder(),
              child: IconButton(
                icon: const Icon(Icons.add_rounded, size: 24),
                color: kAccent,
                tooltip: 'Send files',
                onPressed: enabled ? onAttach : null,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Container(
              constraints: const BoxConstraints(minHeight: 44),
              decoration: BoxDecoration(
                color: kTile,
                borderRadius: BorderRadius.circular(22),
              ),
              padding: const EdgeInsets.only(left: 16, right: 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: controller,
                      focusNode: focus,
                      enabled: enabled,
                      minLines: 1,
                      maxLines: 6,
                      keyboardType: TextInputType.multiline,
                      textCapitalization: TextCapitalization.sentences,
                      style: const TextStyle(fontSize: 15, color: kText),
                      decoration: InputDecoration(
                        hintText: hint,
                        hintStyle: const TextStyle(color: kTextFaint),
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        disabledBorder: InputBorder.none,
                        filled: false,
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.content_paste_go_rounded, size: 19),
                    color: kTextSecondary,
                    tooltip: 'Send clipboard',
                    onPressed: enabled && !sending ? onPasteSend : null,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 44,
            height: 44,
            child: Material(
              color: canSend ? kAccent : kTile,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: canSend ? onSend : null,
                child: Center(
                  child: sending
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: kTextFaint),
                        )
                      : Icon(Icons.arrow_upward_rounded, size: 21, color: canSend ? kOnAccent : kTextFaint),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
