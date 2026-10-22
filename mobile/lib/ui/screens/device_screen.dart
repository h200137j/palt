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
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
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
import '../../features/screen_capture.dart';
import '../../providers/link_provider.dart';
import '../widgets/dock_view.dart';
import '../widgets/device_status.dart';
import '../widgets/bluetooth_card.dart';
import '../widgets/commands_card.dart';
import '../widgets/computer_vitals.dart';
import '../widgets/media_player.dart';
import '../widgets/restricted_hint.dart';
import '../widgets/screen_capture_tiles.dart';
import '../../providers/history_provider.dart';
import '../../providers/peer_provider.dart';
import '../../services/transfer_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/media.dart';
import '../widgets/peer_card.dart';
import '../widgets/palt_page.dart';
import '../../utils/os_icons.dart';
import '../widgets/route_badge.dart';
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
  int _tab = 0; // Control, Dock (computers), Activity
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
              title: Text(title, style: TextStyle(color: kText)),
              subtitle: Text(subtitle, style: TextStyle(color: kTextSecondary, fontSize: 12.5)),
              value: features.isOn(feature, name),
              onChanged: paired ? (on) => features.set(feature, name, on) : null,
            );
        return SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(name, style: display(fontSize: 17)),
            if (!paired)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
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
              title: Text('Copy its messages', style: TextStyle(color: kText)),
              subtitle: Text('Texts it sends you go to the clipboard',
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
    final peers = ref.watch(peerListProvider).valueOrNull ?? [];
    final live = _livePeer(peers);
    final online = live != null;
    final peer = live ?? widget.peer;

    final alias = ref.watch(aliasProvider)[peer.deviceName];
    final displayName = (alias != null && alias.isNotEmpty) ? alias : peer.deviceName;
    final paired = peer.paired;
    // The app dock is for computers that run apps PALT can open.
    final dock = paired &&
        (peer.os == 'linux' || DockApps.supported(ref.watch(linkManagerProvider).byName(peer.deviceName)));
    final activityTab = dock ? 2 : 1;
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
            padding: EdgeInsets.fromLTRB(isPaper ? 22 : 14, 12, isPaper ? 22 : (isPop ? 18 : 14), 8),
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

    final labels = ['Control', if (dock) 'Dock', 'Activity'];
    final unread = _tab == activityTab
        ? 0
        : thread.where((e) => e.direction == 'incoming' && e.timestamp.isAfter(_seenActivity)).length;
    void select(int i) => _pages.animateToPage(i, duration: const Duration(milliseconds: 260), curve: Curves.easeOutCubic);
    // Material and Aurora keep the composer to the Activity tab; the others
    // keep it under everything.
    final composerHere = !paired || !(isMaterial || isAurora) || _tab == activityTab;

    final subtitle = !online
        ? 'offline'
        : [
            if (status != null && status.battery >= 0) '${status.battery}%',
            if (status != null && networkLabel(status).isNotEmpty) networkLabel(status),
            if (status == null && !peer.viaRelay) peer.ipAddress,
          ].join('   ');
    final settingsButton = IconButton(
      tooltip: 'Device settings',
      icon: Icon(isMaterial ? Icons.settings_outlined : Icons.tune_rounded, color: isMaterial ? null : kTextSecondary),
      onPressed: () => _deviceSettings(peer.deviceName, paired),
    );

    PreferredSizeWidget? appBar;
    Widget? header;
    switch (palt.style) {
      case PaltStyle.paper:
        header = GestureDetector(
          onLongPress: () => showRenameDialog(context, ref, peer),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 0, 12, 0),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                TextButton.icon(
                  onPressed: () => Navigator.pop(context),
                  style: TextButton.styleFrom(padding: EdgeInsets.zero, foregroundColor: kText),
                  icon: const Icon(Icons.west_rounded, size: 18),
                  label: const Text('Front page'),
                ),
                const Spacer(),
                settingsButton,
              ]),
              Text(displayName, style: display(fontSize: 40), maxLines: 1, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 4),
              Row(children: [
                if (online) ...[RouteBadge(route: peer.via, ip: peer.ipAddress), const SizedBox(width: 10)],
                Flexible(
                  child: Text(subtitle.toUpperCase(),
                      style: mono(fontSize: 10.5).copyWith(letterSpacing: 1.2), maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
              ]),
              const SizedBox(height: 10),
              Container(height: 3, color: kText),
              const SizedBox(height: 2),
              Container(height: 1, color: kText),
            ]),
          ),
        );
      case PaltStyle.pop:
        header = Padding(
          padding: const EdgeInsets.fromLTRB(18, 10, 18, 4),
          child: Row(children: [
            PopIconButton(icon: Icons.arrow_back_rounded, tooltip: 'Back', onTap: () => Navigator.pop(context)),
            const SizedBox(width: 14),
            Expanded(
              child: GestureDetector(
                onLongPress: () => showRenameDialog(context, ref, peer),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(displayName.toUpperCase(), style: display(fontSize: 22), maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 4),
                  Row(children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                          color: online ? kOk : kTextFaint, shape: BoxShape.circle, border: Border.all(color: kText, width: 1.5)),
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(subtitle,
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: kTextSecondary),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                    ),
                  ]),
                ]),
              ),
            ),
            PopIconButton(
              icon: Icons.tune_rounded,
              tooltip: 'Device settings',
              color: popColor(1, kSurface),
              onTap: () => _deviceSettings(peer.deviceName, paired),
            ),
          ]),
        );
      case PaltStyle.material:
        appBar = AppBar(
          titleSpacing: 0,
          toolbarHeight: 72,
          actions: [settingsButton, const SizedBox(width: 4)],
          title: GestureDetector(
            onLongPress: () => showRenameDialog(context, ref, peer),
            child: Row(children: [
              DeviceBadge(icon: getOsInfo(peer.os).icon, size: 42, lit: online),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(displayName, style: Theme.of(context).textTheme.titleLarge, maxLines: 1, overflow: TextOverflow.ellipsis),
                  Text(online ? '${routeLabel(peer.via, peer.ipAddress)} · $subtitle' : 'Offline',
                      style: TextStyle(fontSize: 13, color: kTextSecondary), maxLines: 1, overflow: TextOverflow.ellipsis),
                ]),
              ),
            ]),
          ),
        );
      case PaltStyle.aurora:
        appBar = AppBar(
          centerTitle: true,
          toolbarHeight: 64,
          actions: [settingsButton, const SizedBox(width: 4)],
          title: GestureDetector(
            onLongPress: () => showRenameDialog(context, ref, peer),
            child: Column(children: [
              Text(displayName,
                  style: display(fontSize: 18, fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 2),
              Row(mainAxisSize: MainAxisSize.min, children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(color: online ? kOk : kTextFaint, shape: BoxShape.circle),
                ),
                const SizedBox(width: 6),
                Text(subtitle, style: TextStyle(fontSize: 11.5, color: kTextSecondary)),
              ]),
            ]),
          ),
        );
      case PaltStyle.beacon:
        appBar = AppBar(
          titleSpacing: 0,
          toolbarHeight: 64,
          actions: [settingsButton, const SizedBox(width: 4)],
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
                      child: Text(subtitle, style: mono(fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
    }

    return Scaffold(
      appBar: appBar,
      bottomNavigationBar: paired && isMaterial
          ? NavigationBar(
              selectedIndex: _tab,
              onDestinationSelected: select,
              destinations: [
                for (var i = 0; i < labels.length; i++)
                  NavigationDestination(
                    icon: Badge(
                      isLabelVisible: i == labels.length - 1 && unread > 0,
                      label: Text('$unread'),
                      child: Icon(_tabIcon(labels[i], false)),
                    ),
                    selectedIcon: Icon(_tabIcon(labels[i], true)),
                    label: labels[i],
                  ),
              ],
            )
          : null,
      body: PaltBackdrop(
        child: SafeArea(
          top: appBar == null,
          bottom: !(paired && isMaterial),
          child: Column(
            children: [
              if (header != null) header,
              if (paired && !isMaterial && !isAurora)
                _Tabs(labels: labels, selected: _tab, unread: unread, onSelect: select),
              Expanded(
                // Paired: swipe between Control and Activity.
                child: paired
                    ? PageView(
                        controller: _pages,
                        onPageChanged: (i) => setState(() {
                          _tab = i;
                          _seenActivity = DateTime.now();
                        }),
                        children: [
                          _ControlTab(peer: peer, online: online),
                          if (dock) DockView(peer: peer, active: _tab == 1),
                          threadView,
                        ],
                      )
                    : threadView,
              ),
              if (notice != null && composerHere)
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
              if (composerHere)
                _Composer(
                  controller: _controller,
                  focus: _focus,
                  enabled: online,
                  canSend: canSend,
                  sending: _sending,
                  hint: online
                      ? (isPaper ? 'Write to $displayName…' : (isPop ? 'Say something…' : 'Send text to $displayName…'))
                      : 'Device offline',
                  onAttach: () => pickAndSendFiles(ref, peer),
                  onPasteSend: () => _sendClipboard(peer),
                  onSend: () => _submit(peer),
                ),
              if (paired && isAurora) _GlassNav(labels: labels, selected: _tab, unread: unread, onSelect: select),
            ],
          ),
        ),
      ),
    );
  }
}

IconData _tabIcon(String label, bool on) => switch (label) {
      'Control' => on ? Icons.tune_rounded : Icons.tune_outlined,
      'Dock' => on ? Icons.apps_rounded : Icons.apps_outlined,
      _ => on ? Icons.forum_rounded : Icons.forum_outlined,
    };

/// Aurora: a floating frosted capsule with a glowing pill under the tab.
class _GlassNav extends StatelessWidget {
  final List<String> labels;
  final int selected;
  final int unread;
  final ValueChanged<int> onSelect;
  const _GlassNav({required this.labels, required this.selected, required this.unread, required this.onSelect});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(28, 6, 28, 12),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: Container(
              height: 62,
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
              ),
              child: LayoutBuilder(builder: (context, box) {
                final w = box.maxWidth / labels.length;
                return Stack(children: [
                  AnimatedPositioned(
                    duration: const Duration(milliseconds: 320),
                    curve: Curves.easeOutBack,
                    left: w * selected,
                    top: 0,
                    bottom: 0,
                    width: w,
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: kAccentGradient,
                        borderRadius: BorderRadius.circular(999),
                        boxShadow: [BoxShadow(color: kAccent.withValues(alpha: 0.5), blurRadius: 18, spreadRadius: -4)],
                      ),
                    ),
                  ),
                  Row(children: [
                    for (var i = 0; i < labels.length; i++)
                      Expanded(
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => onSelect(i),
                          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                            Badge(
                              isLabelVisible: i == labels.length - 1 && unread > 0,
                              backgroundColor: kDanger,
                              smallSize: 8,
                              child: Icon(_tabIcon(labels[i], i == selected),
                                  size: 20, color: i == selected ? kOnAccent : kTextSecondary),
                            ),
                            if (i == selected) ...[
                              const SizedBox(width: 6),
                              Text(labels[i],
                                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: kOnAccent)),
                            ],
                          ]),
                        ),
                      ),
                  ]),
                ]);
              }),
            ),
          ),
        ),
      );
}

/// Control | Dock | Activity
class _Tabs extends StatelessWidget {
  final List<String> labels; // Activity is last
  final int selected;
  final int unread; // new on Activity since it was last seen
  final ValueChanged<int> onSelect;
  const _Tabs({required this.labels, required this.selected, required this.unread, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    if (isPaper) return _paper();
    if (isPop) return _pop();
    return _beacon();
  }

  Widget _count(int count, {Color? bg, Color? fg}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        decoration: BoxDecoration(
          color: bg,
          gradient: bg == null ? kAccentGradient : null,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(count > 99 ? '99+' : '$count',
            style: TextStyle(color: fg ?? kOnAccent, fontSize: 11, fontWeight: FontWeight.w700)),
      );

  /// Paper: numbered sections, the open one underlined in red.
  Widget _paper() {
    const numerals = ['I', 'II', 'III'];
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 4, 22, 0),
      child: Row(children: [
        for (var i = 0; i < labels.length; i++)
          Padding(
            padding: const EdgeInsets.only(right: 22),
            child: InkWell(
              onTap: () => onSelect(i),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: i == selected ? kAccent : Colors.transparent, width: 2.5)),
                ),
                child: Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
                  Text('${numerals[i]}. ', style: mono(fontSize: 11, color: i == selected ? kAccent : kTextFaint)),
                  Text(labels[i],
                      style: display(fontSize: 21, color: i == selected ? kText : kTextSecondary)
                          .copyWith(fontStyle: i == selected ? FontStyle.normal : FontStyle.italic)),
                  if (i == labels.length - 1 && unread > 0) ...[
                    const SizedBox(width: 6),
                    Text('($unread new)', style: TextStyle(fontSize: 12, color: kAccent, fontStyle: FontStyle.italic)),
                  ],
                ]),
              ),
            ),
          ),
      ]),
    );
  }

  /// Pop: fat blocks, the open one loud and raised.
  Widget _pop() => Padding(
        padding: const EdgeInsets.fromLTRB(18, 10, 22, 6),
        child: Row(children: [
          for (var i = 0; i < labels.length; i++) ...[
            if (i > 0) const SizedBox(width: 10),
            Expanded(
              child: PressDown(
                onTap: () => onSelect(i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  height: 46,
                  decoration: paltDeco(radius: 10, color: i == selected ? popColor(i, kAccent) : kSurface, flat: i != selected),
                  child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Text(labels[i].toUpperCase(),
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: kText, letterSpacing: 0.6)),
                    if (i == labels.length - 1 && unread > 0) ...[
                      const SizedBox(width: 6),
                      _count(unread, bg: kDanger, fg: kSurface),
                    ],
                  ]),
                ),
              ),
            ),
          ],
        ]),
      );

  Widget _beacon() {
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
                        style: TextStyle(color: kOnAccent, fontSize: 11, fontWeight: FontWeight.w700)),
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
      child: Row(children: [
        for (var i = 0; i < labels.length; i++) ...[
          if (i > 0) const SizedBox(width: 4),
          tab(i, labels[i], i == labels.length - 1 ? unread : 0),
        ],
      ]),
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
    final link = ref.watch(linkManagerProvider).byName(peer.deviceName);
    final _Action send = (icon: Icons.attach_file_rounded, label: 'Send files', sub: 'Photos, docs, anything', onTap: when(() => pickAndSendFiles(ref, peer)));
    final quick = <_Action>[
      (icon: Icons.content_paste_go_rounded, label: 'Clipboard', sub: 'Send what you copied', onTap: when(() => sendClipboardTo(context, ref, peer))),
      (icon: Icons.notifications_active_rounded, label: 'Ring', sub: 'Make it ring out loud', onTap: when(() => sendDevicePacket(context, ref, peer, 'ring'))),
      (icon: Icons.waving_hand_rounded, label: 'Ping', sub: 'A friendly nudge', onTap: when(() => sendDevicePacket(context, ref, peer, 'user_ping'))),
      (icon: Icons.wifi_rounded, label: 'Share Wi-Fi', sub: 'Hand over this network', onTap: when(() => shareWifiTo(context, peer))),
    ];
    final more = <_Action>[
      if (online && RemoteInput.supported(link))
        (
          icon: Icons.mouse_rounded,
          label: 'Touchpad & keyboard',
          sub: 'Drive the pointer from here',
          onTap: () {
            Navigator.push(context, MaterialPageRoute(builder: (_) => TouchpadScreen(peer: peer)));
          },
        ),
      (
        icon: Icons.public_rounded,
        label: 'Share internet',
        sub: 'Give ${peer.deviceName} this phone\'s connection',
        onTap: when(() => shareInternetWith(context, ref, peer, phoneOnline: ref.read(localStatusProvider)?.internet ?? true)),
      ),
    ];
    const gap = 8.0, h = 78.0;

    final List<Widget> actions = switch (palt.style) {
      // An index, like the contents column of a paper.
      PaltStyle.paper => [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 6, 4, 0),
            child: Text(caps('IN THIS SECTION'), style: overline()),
          ),
          for (final (i, a) in [send, ...quick, ...more].indexed) _PaperRow(n: i + 1, a: a),
          Container(height: 1, color: kText),
        ],
      // A big tonal hero, a button group of round actions, a list for the rest.
      PaltStyle.material => [
          _MaterialHero(a: send),
          const SizedBox(height: 18),
          Row(children: [
            for (final a in quick)
              Expanded(
                child: Column(children: [
                  IconButton.filledTonal(
                    onPressed: a.onTap,
                    iconSize: 26,
                    style: IconButton.styleFrom(minimumSize: const Size(64, 64)),
                    icon: Icon(a.icon),
                  ),
                  const SizedBox(height: 6),
                  Text(a.label, style: TextStyle(fontSize: 12.5, color: kTextSecondary)),
                ]),
              ),
          ]),
          const SizedBox(height: 8),
        ],
      // Send across the top, then a block of loud colours.
      PaltStyle.pop => [
          _Tile(height: 92, big: true, icon: send.icon, label: send.label, sub: send.sub, onTap: send.onTap),
          const SizedBox(height: 12),
          for (var r = 0; r < 2; r++) ...[
            Row(children: [
              for (var c = 0; c < 2; c++) ...[
                if (c > 0) const SizedBox(width: 12),
                Expanded(
                  child: _Tile(
                    height: h,
                    index: r * 2 + c,
                    icon: quick[r * 2 + c].icon,
                    label: quick[r * 2 + c].label,
                    onTap: quick[r * 2 + c].onTap,
                  ),
                ),
              ],
            ]),
            const SizedBox(height: 12),
          ],
        ],
      _ => [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _Tile(
                    height: h * 2 + gap, big: true, icon: send.icon, label: send.label, sub: send.sub, onTap: send.onTap),
              ),
              const SizedBox(width: gap),
              Expanded(
                child: Column(children: [
                  for (var r = 0; r < 2; r++) ...[
                    if (r > 0) const SizedBox(height: gap),
                    Row(children: [
                      for (var c = 0; c < 2; c++) ...[
                        if (c > 0) const SizedBox(width: gap),
                        Expanded(
                          child: _Tile(
                            height: h,
                            icon: quick[r * 2 + c].icon,
                            label: quick[r * 2 + c].label,
                            onTap: quick[r * 2 + c].onTap,
                          ),
                        ),
                      ],
                    ]),
                  ],
                ]),
              ),
            ],
          ),
        ],
    };

    final List<Widget> extras = switch (palt.style) {
      PaltStyle.paper => const [],
      PaltStyle.material => [
          const SizedBox(height: 8),
          PaltSectionBox(children: [
            for (final a in more)
              ListTile(
                leading: Icon(a.icon),
                title: Text(a.label),
                subtitle: Text(a.sub, maxLines: 1, overflow: TextOverflow.ellipsis),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: a.onTap,
                enabled: a.onTap != null,
              ),
          ]),
        ],
      PaltStyle.pop => [
          for (final (i, a) in more.indexed) ...[
            const SizedBox(height: 4),
            PressDown(
              onTap: a.onTap,
              child: Container(
                height: 56,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: paltDeco(radius: 12, color: popColor(i + 4, kSurface)),
                child: Row(children: [
                  Icon(a.icon, color: kText),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(a.label.toUpperCase(),
                        style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: kText),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                  ),
                  Icon(Icons.arrow_forward_rounded, color: kText),
                ]),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ],
      _ => [
          for (final a in more) ...[
            const SizedBox(height: 8),
            SizedBox(
              height: 52,
              child: OutlinedButton.icon(
                onPressed: a.onTap,
                icon: Icon(a.icon, size: 18),
                label: Text(a.label == 'Share internet' ? 'Share internet with ${peer.deviceName}' : a.label,
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                style: OutlinedButton.styleFrom(
                  foregroundColor: kText.withValues(alpha: 0.85),
                  backgroundColor: isAurora ? Colors.white.withValues(alpha: 0.04) : null,
                  side: BorderSide(color: isAurora ? const Color(0x24FFFFFF) : kHairline),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(rad(18))),
                  textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                ),
              ),
            ),
          ],
        ],
    };

    return ListView(
      padding: EdgeInsets.fromLTRB(isPaper ? 22 : 16, 12, isPop ? 20 : (isPaper ? 22 : 16), 12),
      children: [
        _NowPlaying(device: peer.deviceName),
        ...actions,
        if (online && ScreenCapture.supported(link)) ...[
          const SizedBox(height: 8),
          ScreenCaptureTiles(key: ValueKey('capture-${peer.deviceName}'), peer: peer),
        ],
        if (online) CommandsCard(key: ValueKey(peer.deviceName), peer: peer),
        ...extras,
        if (ref.watch(peerStatusProvider)[peer.deviceName] case final st? when st.isComputer)
          ComputerVitals(status: st),
        if (online) BluetoothCard(peer: peer),
        if (peer.os != 'android') RestrictedHint(computer: peer.deviceName),
      ],
    );
  }
}

typedef _Action = ({IconData icon, String label, String sub, VoidCallback? onTap});

/// Material: the main action as a big tonal card.
class _MaterialHero extends StatelessWidget {
  final _Action a;
  const _MaterialHero({required this.a});

  @override
  Widget build(BuildContext context) => Material(
        color: kAccentSoft,
        borderRadius: BorderRadius.circular(28),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: a.onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 20, 20, 20),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(a.label, style: Theme.of(context).textTheme.headlineSmall?.copyWith(color: kOnAccentSoft)),
                  const SizedBox(height: 2),
                  Text(a.sub, style: TextStyle(color: kOnAccentSoft.withValues(alpha: 0.75), fontSize: 14)),
                ]),
              ),
              Container(
                width: 64,
                height: 64,
                decoration: ShapeDecoration(shape: const CookieBorder(lobes: 8, depth: 0.08), color: kAccent),
                child: Icon(Icons.upload_rounded, color: kOnAccent, size: 28),
              ),
            ]),
          ),
        ),
      );
}

/// Material: rows grouped in one rounded block.
class PaltSectionBox extends StatelessWidget {
  final List<Widget> children;
  const PaltSectionBox({super.key, required this.children});

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (var i = 0; i < children.length; i++)
          Container(
            margin: EdgeInsets.only(bottom: i == children.length - 1 ? 0 : 2),
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: kSurface,
              borderRadius: BorderRadius.vertical(
                top: Radius.circular(i == 0 ? 24 : 4),
                bottom: Radius.circular(i == children.length - 1 ? 24 : 4),
              ),
            ),
            child: Material(type: MaterialType.transparency, child: children[i]),
          ),
      ]);
}

/// Paper: one line of the index — number, headline, dek, arrow.
class _PaperRow extends StatelessWidget {
  final int n;
  final _Action a;
  const _PaperRow({required this.n, required this.a});

  @override
  Widget build(BuildContext context) => Opacity(
        opacity: a.onTap == null ? 0.45 : 1,
        child: InkWell(
          onTap: a.onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 13),
            decoration: BoxDecoration(border: Border(top: BorderSide(color: n == 1 ? kText : kHairline))),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(
                width: 34,
                child: Text(n.toString().padLeft(2, '0'), style: mono(fontSize: 12, color: kAccent)),
              ),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(a.label, style: display(fontSize: n == 1 ? 30 : 22)),
                  const SizedBox(height: 2),
                  Text(a.sub,
                      style: TextStyle(fontSize: 13, color: kTextSecondary, fontStyle: FontStyle.italic),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ]),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Icon(a.icon, size: 20, color: n == 1 ? kAccent : kText),
              ),
            ]),
          ),
        ),
      );
}

class _Tile extends StatelessWidget {
  final double height;
  final IconData icon;
  final String label;
  final String? sub;
  final bool big;
  final int index;
  final VoidCallback? onTap;
  const _Tile(
      {required this.height, required this.icon, required this.label, this.sub, this.big = false, this.index = 0, this.onTap});

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final Color fg;
    final BoxDecoration deco;
    final double r = rad(big ? 22 : 20);
    switch (palt.style) {
      case PaltStyle.material:
        fg = big ? kOnAccentSoft : kText;
        deco = BoxDecoration(color: big ? kAccentSoft : kSurfaceRaised, borderRadius: BorderRadius.circular(r));
      case PaltStyle.pop:
        fg = big ? kOnAccent : kText;
        deco = paltDeco(radius: big ? 16 : 14, color: big ? kAccent : popColor(index, kSurface), hero: big);
      case PaltStyle.aurora:
        fg = big ? kOnAccent : kText;
        deco = big
            ? BoxDecoration(
                gradient: kAccentGradient,
                borderRadius: BorderRadius.circular(r),
                boxShadow: [BoxShadow(color: kAccent.withValues(alpha: 0.35), blurRadius: 28, spreadRadius: -8)],
              )
            : paltDeco(radius: 20);
      case PaltStyle.paper:
      case PaltStyle.beacon:
        fg = big ? kOnAccent : (enabled ? kText.withValues(alpha: 0.88) : kTextFaint);
        deco = BoxDecoration(gradient: big ? kAccentGradient : kTileGradient, borderRadius: BorderRadius.circular(r));
    }
    final content = SizedBox(
      height: height,
      child: big
          ? Padding(
              padding: const EdgeInsets.all(16),
              child: isPop
                  ? Row(children: [
                      Container(
                        width: 54,
                        height: 54,
                        decoration: paltDeco(radius: 12, color: popColor(0, kAccent), flat: true),
                        child: Icon(icon, size: 28, color: kText),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(label.toUpperCase(), style: display(fontSize: 20, color: fg)),
                          if (sub != null) Text(sub!, style: TextStyle(fontSize: 13, color: fg.withValues(alpha: 0.85))),
                        ]),
                      ),
                    ])
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Icon(icon, size: 28, color: fg),
                        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(label, style: display(fontSize: 21, fontWeight: FontWeight.w800, color: fg)),
                          if (sub != null) Text(sub!, style: TextStyle(fontSize: 12, color: fg.withValues(alpha: 0.75))),
                        ]),
                      ],
                    ),
            )
          : Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: isPop ? 26 : 21, color: fg),
                const SizedBox(height: 6),
                Text(isPop ? label.toUpperCase() : label,
                    style: TextStyle(fontSize: 12, color: fg, fontWeight: isPop ? FontWeight.w800 : null),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ],
            ),
    );
    if (isPop) {
      return PressDown(onTap: onTap, child: Container(decoration: deco, child: content));
    }
    // Ink paints on the nearest Material, so give it one inside the fade.
    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: Material(
        type: MaterialType.transparency,
        child: Ink(
          decoration: deco,
          child: InkWell(borderRadius: BorderRadius.circular(r), onTap: onTap, child: content),
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
                  inactiveTrackColor: kText.withValues(alpha: 0.15),
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

/// Text on a bubble. Paper has no bubbles: everything is ink on the page.
Color _onBubble(bool outgoing) => outgoing && !isPaper ? kOnSent : kText;
Color _metaOn(bool outgoing) => outgoing && !isPaper ? kSentMeta : kTextFaint;

class _DayDivider extends StatelessWidget {
  final String label;
  const _DayDivider({required this.label});

  @override
  Widget build(BuildContext context) => switch (palt.style) {
        PaltStyle.paper => Padding(
            padding: const EdgeInsets.only(top: 18, bottom: 6),
            child: Row(children: [
              Expanded(child: Container(height: 1, color: kHairline)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(label, style: display(fontSize: 17).copyWith(fontStyle: FontStyle.italic, color: kTextSecondary)),
              ),
              Expanded(child: Container(height: 1, color: kHairline)),
            ]),
          ),
        PaltStyle.pop => Padding(
            padding: const EdgeInsets.only(top: 16, bottom: 10),
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: paltDeco(radius: 999, color: kText, flat: true),
                child: Text(label.toUpperCase(), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: kBg)),
              ),
            ),
          ),
        PaltStyle.material => Padding(
            padding: const EdgeInsets.only(top: 16, bottom: 8),
            child: Center(child: Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: kTextSecondary))),
          ),
        _ => Padding(
        padding: const EdgeInsets.only(top: 14, bottom: 8),
        child: Center(
          child: Text(label.toUpperCase(), style: mono(fontSize: 10, color: kTextFaint).copyWith(letterSpacing: 1.2)),
        ),
      ),
      };
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
              child: Icon(Icons.play_arrow_rounded, color: kText, size: 24),
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
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _onBubble(outgoing)),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(_formatSize(f.size), style: mono(fontSize: 10, color: _metaOn(outgoing))),
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
                  backgroundColor: outgoing && !isPaper ? Colors.black.withValues(alpha: 0.22) : kSurfaceRaised,
                  foregroundColor: _onBubble(outgoing),
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
              child: Icon(Icons.image_not_supported_outlined, color: kTextFaint, size: 20)),
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
              leading: Icon(Icons.delete_outline_rounded, color: kDanger),
              title: Text('Delete', style: TextStyle(color: kDanger)),
              subtitle: entry.isText
                  ? null
                  : Text('Removes it from this chat. Files stay on the phone.',
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
    final metaColor = _metaOn(outgoing);
    final total = entry.files.fold<int>(0, (n, f) => n + f.size);

    final body = entry.isText
        ? SelectableText(
            entry.text ?? '',
            style: TextStyle(fontSize: 14.5, color: _onBubble(outgoing), height: 1.35),
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

    final failedNote = Padding(
      padding: const EdgeInsets.fromLTRB(6, 4, 6, 0),
      child: GestureDetector(
        onTap: entry.errorMessage == null
            ? null
            : () => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(entry.errorMessage!))),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.error_outline_rounded, size: 13, color: kDanger),
          const SizedBox(width: 4),
          Text('Not delivered', style: TextStyle(fontSize: 11, color: kDanger)),
        ]),
      ),
    );

    // Paper: a transcript. Who and when in the margin, the words on the page.
    if (isPaper) {
      return GestureDetector(
        onLongPress: () => _showActions(context, ref),
        child: Container(
          padding: const EdgeInsets.fromLTRB(4, 12, 4, 12),
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: kHairline))),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(
              width: 62,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(outgoing ? 'YOU' : entry.partnerName.split(RegExp(r'[-_ ]')).first.toUpperCase(),
                    style: mono(fontSize: 10, fontWeight: FontWeight.w700, color: outgoing ? kAccent : kText)
                        .copyWith(letterSpacing: 1),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Text(_formatTime(entry.timestamp), style: mono(fontSize: 10, color: kTextFaint)),
              ]),
            ),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (entry.isText)
                  SelectableText(entry.text ?? '',
                      style: GoogleFonts.newsreader(fontSize: 18, color: kText, height: 1.35))
                else
                  body,
                if (entry.copied || picturesOnly || entry.route == 'relay')
                  Padding(padding: const EdgeInsets.only(top: 4), child: meta),
                if (failed) failedNote,
              ]),
            ),
          ]),
        ),
      );
    }

    final tail = rad(outgoing ? 18 : 6);
    final r18 = Radius.circular(rad(18));
    final shape = isMaterial
        ? BorderRadius.only(
            topLeft: const Radius.circular(22),
            topRight: const Radius.circular(22),
            bottomLeft: Radius.circular(outgoing ? 22 : 4),
            bottomRight: Radius.circular(outgoing ? 4 : 22),
          )
        : BorderRadius.only(
            topLeft: r18,
            topRight: r18,
            bottomLeft: Radius.circular(tail),
            bottomRight: Radius.circular(outgoing ? rad(6) : rad(18)),
          );
    final BoxDecoration bubble = switch (palt.style) {
      PaltStyle.pop => BoxDecoration(
          color: outgoing ? kSent : kSurface,
          borderRadius: shape,
          border: Border.all(color: failed ? kDanger : kText, width: 2),
          boxShadow: [BoxShadow(color: kText, offset: const Offset(3, 3))],
        ),
      PaltStyle.aurora => BoxDecoration(
          gradient: outgoing
              ? LinearGradient(colors: [kAccent.withValues(alpha: 0.42), const Color(0x55F0ABFC)])
              : kTileGradient,
          borderRadius: shape,
          border: Border.all(color: failed ? kDanger.withValues(alpha: 0.6) : const Color(0x24FFFFFF)),
        ),
      _ => BoxDecoration(
          color: outgoing ? kSent : (isMaterial ? kSurfaceRaised : kTile),
          border: failed ? Border.all(color: kDanger.withValues(alpha: 0.6)) : null,
          borderRadius: shape,
        ),
    };

    return Padding(
      padding: EdgeInsets.symmetric(vertical: isPop ? 6 : 4),
      child: Column(
        crossAxisAlignment: outgoing ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onLongPress: () => _showActions(context, ref),
            child: Container(
              constraints: BoxConstraints(maxWidth: maxWidth),
              padding: picturesOnly ? const EdgeInsets.all(4) : const EdgeInsets.fromLTRB(12, 9, 12, 7),
              decoration: bubble,
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
          if (failed) failedNote,
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
            Icon(Icons.forum_outlined, size: 48, color: kTextFaint),
            const SizedBox(height: 14),
            Text('Nothing shared yet', style: display(fontSize: 18)),
            const SizedBox(height: 6),
            Text(
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
        decoration: BoxDecoration(
          color: kSent,
          borderRadius: const BorderRadius.only(
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
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: kOnSent),
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

  Widget _field({TextStyle? style}) => TextField(
        controller: controller,
        focusNode: focus,
        enabled: enabled,
        minLines: 1,
        maxLines: 6,
        keyboardType: TextInputType.multiline,
        textCapitalization: TextCapitalization.sentences,
        style: style ?? TextStyle(fontSize: 15, color: kText),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: (style ?? const TextStyle()).copyWith(color: kTextFaint),
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          disabledBorder: InputBorder.none,
          filled: false,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 12),
        ),
      );

  Widget get _spinner => SizedBox(
        width: 18,
        height: 18,
        child: CircularProgressIndicator(strokeWidth: 2, color: kTextFaint),
      );

  @override
  Widget build(BuildContext context) {
    switch (palt.style) {
      case PaltStyle.material:
        return Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
          child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Expanded(
              child: Container(
                constraints: const BoxConstraints(minHeight: 56),
                decoration: BoxDecoration(color: kSurfaceRaised, borderRadius: BorderRadius.circular(28)),
                padding: const EdgeInsets.only(left: 4, right: 4),
                child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                  IconButton(
                    icon: const Icon(Icons.add_circle_outline_rounded),
                    color: kTextSecondary,
                    tooltip: 'Send files',
                    onPressed: enabled ? onAttach : null,
                  ),
                  Expanded(child: _field(style: TextStyle(fontSize: 16, color: kText))),
                  IconButton(
                    icon: const Icon(Icons.content_paste_go_rounded),
                    color: kTextSecondary,
                    tooltip: 'Send clipboard',
                    onPressed: enabled && !sending ? onPasteSend : null,
                  ),
                ]),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 56,
              height: 56,
              child: FloatingActionButton(
                heroTag: null,
                elevation: 0,
                onPressed: canSend ? onSend : null,
                backgroundColor: canSend ? kAccent : kSurfaceRaised,
                foregroundColor: canSend ? kOnAccent : kTextFaint,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(canSend ? 18 : 28)),
                child: sending ? _spinner : const Icon(Icons.send_rounded),
              ),
            ),
          ]),
        );
      case PaltStyle.paper:
        return Container(
          padding: const EdgeInsets.fromLTRB(22, 6, 12, 10),
          decoration: BoxDecoration(border: Border(top: BorderSide(color: kText, width: 1.5))),
          child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
            IconButton(
              icon: const Icon(Icons.attach_file_rounded),
              color: kText,
              tooltip: 'Send files',
              onPressed: enabled ? onAttach : null,
            ),
            Expanded(child: _field(style: GoogleFonts.newsreader(fontSize: 18, color: kText, fontStyle: FontStyle.italic))),
            IconButton(
              icon: const Icon(Icons.content_paste_go_rounded, size: 20),
              color: kTextSecondary,
              tooltip: 'Send clipboard',
              onPressed: enabled && !sending ? onPasteSend : null,
            ),
            sending
                ? Padding(padding: const EdgeInsets.all(12), child: _spinner)
                : TextButton(
                    onPressed: canSend ? onSend : null,
                    child: const Text('Send →'),
                  ),
          ]),
        );
      case PaltStyle.pop:
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 20, 14),
          child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            PressDown(
              onTap: enabled ? onAttach : null,
              child: Container(
                width: 50,
                height: 50,
                decoration: paltDeco(radius: 12, color: popColor(1, kSurface)),
                child: Icon(Icons.add_rounded, color: kText, size: 28),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Container(
                constraints: const BoxConstraints(minHeight: 50),
                decoration: paltDeco(radius: 12, color: kSurface, flat: true),
                padding: const EdgeInsets.only(left: 14, right: 2),
                child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                  Expanded(child: _field(style: TextStyle(fontSize: 15, color: kText, fontWeight: FontWeight.w600))),
                  IconButton(
                    icon: const Icon(Icons.content_paste_go_rounded, size: 20),
                    color: kText,
                    tooltip: 'Send clipboard',
                    onPressed: enabled && !sending ? onPasteSend : null,
                  ),
                ]),
              ),
            ),
            const SizedBox(width: 12),
            PressDown(
              onTap: canSend ? onSend : null,
              child: Container(
                width: 50,
                height: 50,
                decoration: paltDeco(radius: 12, color: canSend ? kAccent : kSurface),
                child: Center(
                  child: sending ? _spinner : Icon(Icons.arrow_upward_rounded, color: canSend ? kOnAccent : kText, size: 26),
                ),
              ),
            ),
          ]),
        );
      case PaltStyle.aurora:
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 4),
          child: Container(
            constraints: const BoxConstraints(minHeight: 54),
            padding: const EdgeInsets.fromLTRB(6, 5, 5, 5),
            decoration: paltDeco(radius: 27, color: Colors.white.withValues(alpha: 0.07)),
            child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
              IconButton(
                icon: const Icon(Icons.add_rounded),
                color: kAccent,
                tooltip: 'Send files',
                onPressed: enabled ? onAttach : null,
              ),
              Expanded(child: _field()),
              IconButton(
                icon: const Icon(Icons.content_paste_go_rounded, size: 19),
                color: kTextSecondary,
                tooltip: 'Send clipboard',
                onPressed: enabled && !sending ? onPasteSend : null,
              ),
              GestureDetector(
                onTap: canSend ? onSend : null,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: canSend ? kAccentGradient : null,
                    color: canSend ? null : Colors.white.withValues(alpha: 0.06),
                    boxShadow: canSend ? [BoxShadow(color: kAccent.withValues(alpha: 0.5), blurRadius: 16, spreadRadius: -3)] : null,
                  ),
                  child: Center(
                    child: sending
                        ? _spinner
                        : Icon(Icons.arrow_upward_rounded, size: 21, color: canSend ? kOnAccent : kTextFaint),
                  ),
                ),
              ),
            ]),
          ),
        );
      case PaltStyle.beacon:
    }
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 12),
      decoration: BoxDecoration(
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
                      style: TextStyle(fontSize: 15, color: kText),
                      decoration: InputDecoration(
                        hintText: hint,
                        hintStyle: TextStyle(color: kTextFaint),
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
                      ? SizedBox(
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
