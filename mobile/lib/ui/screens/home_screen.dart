/// home_screen.dart — PALT mobile root screen (Beacon).
///
/// Layout: pinned app bar (lamp + wordmark) → update banner → local beacon
/// card → nearby devices list → footer. Incoming offers surface as a modal
/// bottom sheet; live transfers dock as a card above the bottom edge.
/// Pull down anywhere to rescan the network.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_filex/open_filex.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'dart:io';
import 'dart:math';

import '../../features/bluetooth.dart';
import '../../features/phone_features.dart';

import '../../providers/peer_provider.dart';
import '../../providers/update_provider.dart';
import '../../services/update_service.dart';
import '../../services/transfer_service.dart';
import '../../utils/version.dart';
import '../widgets/changelog_dialog.dart';
import '../widgets/beacon_pulse.dart';
import '../widgets/local_device_card.dart';
import '../widgets/peer_card.dart';
import '../widgets/route_badge.dart';
import 'pair_screen.dart';
import 'settings_screen.dart';
import '../widgets/asleep_devices.dart';
import '../widgets/background_banner.dart';
import '../../providers/link_provider.dart';
import '../widgets/update_banner.dart';
import '../../providers/update_visibility_provider.dart';
import '../../models/peer.dart';
import '../../theme/app_theme.dart';
import 'device_screen.dart';
import 'history_screen.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  bool _changelogShown = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _maybeShowChangelog();
      // Things that happened before this screen existed (app opened from
      // a notification or the share menu).
      final offer = ref.read(activeOfferProvider);
      if (offer != null) _showOfferSheet(offer);
      final intake = ref.read(intakeProvider);
      if (intake != null) _handleIntake(intake);
      _askPhonePermission().then((_) => _askSmsPermission()).then((_) => _askBluetoothPermission());
    });
  }

  /// Mobile network type and the Wi-Fi name for the computer's status
  /// readout. Asked once.
  Future<void> _askPhonePermission() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool('palt_asked_status_perms') == true) return;
    await prefs.setBool('palt_asked_status_perms', true);
    await [Permission.phone, Permission.contacts, Permission.locationWhenInUse].request();
    refreshPhoneStatus();
  }

  /// Texts on paired computers. Asked once, after the status permissions.
  Future<void> _askSmsPermission() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool('palt_asked_sms_calls_perms') == true) return;
    await prefs.setBool('palt_asked_sms_calls_perms', true);
    // Phone covers calling, answering and the call log.
    await [Permission.sms, Permission.contacts, Permission.phone].request();
  }

  /// Names and batteries of connected Bluetooth devices, for computers.
  /// Asked once.
  Future<void> _askBluetoothPermission() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool('palt_asked_bluetooth_perm') == true) return;
    await prefs.setBool('palt_asked_bluetooth_perm', true);
    await Permission.bluetoothConnect.request();
    refreshBluetooth();
  }

  void _handleIntake(Map<String, dynamic> m) {
    ref.read(intakeProvider.notifier).state = null;
    final peers = ref.read(peerListProvider).valueOrNull ?? <Peer>[];
    final open = m['openDevice'] as String?;
    if (open != null) {
      final peer = peers.where((p) => p.deviceName == open).firstOrNull;
      if (peer != null) {
        Navigator.of(context).popUntil((r) => r.isFirst);
        Navigator.push(context, MaterialPageRoute(builder: (_) => DeviceScreen(peer: peer)));
      }
      return;
    }
    final paths = ((m['paths'] as List?) ?? []).whereType<String>().toList();
    final text = m['text'] as String?;
    if (paths.isEmpty && (text == null || text.trim().isEmpty)) return;
    _showSendToSheet(paths, text);
  }

  /// "Send to…" for things shared from other apps.
  void _showSendToSheet(List<String> paths, String? text) {
    final what = paths.isNotEmpty
        ? (paths.length == 1 ? paths.first.split('/').last : '${paths.length} files')
        : (text!.length > 60 ? '${text.substring(0, 60)}…' : text);
    showModalBottomSheet(
      context: context,
      builder: (ctx) => Consumer(builder: (ctx, ref, _) {
        final peers = [...?ref.watch(peerListProvider).valueOrNull]
          ..sort((a, b) => (b.paired ? 1 : 0) - (a.paired ? 1 : 0));
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('SEND TO', style: overline()),
                const SizedBox(height: 4),
                Text(what, style: TextStyle(color: kTextSecondary, fontSize: 13), maxLines: 2, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 12),
                if (peers.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Text('No devices connected right now.', style: TextStyle(color: kTextFaint)),
                  ),
                for (final p in peers)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(p.paired ? Icons.link_rounded : Icons.devices_other_rounded,
                        color: p.paired ? kOk : kTextSecondary),
                    title: Text(p.deviceName, style: TextStyle(color: kText)),
                    trailing: RouteBadge(route: p.via, ip: p.ipAddress),
                    onTap: () {
                      Navigator.pop(ctx);
                      final svc = ref.read(transferServiceProvider);
                      final send = paths.isNotEmpty
                          ? svc.sendFiles(p, [for (final x in paths) File(x)])
                          : svc.sendText(p, text!);
                      send.catchError((Object e) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
                        }
                      });
                    },
                  ),
              ],
            ),
          ),
        );
      }),
    );
  }

  Future<void> _maybeShowChangelog() async {
    if (_changelogShown) return;
    final prefs = await SharedPreferences.getInstance();
    final lastSeen = prefs.getString(kLastSeenVersionKey) ?? '';
    if (lastSeen != kAppVersion && mounted) {
      _changelogShown = true;
      final notes = await UpdateService.notesFor(kAppVersion);
      if (!mounted) return;
      await showChangelogDialog(context, releaseNotes: notes);
      await prefs.setString(kLastSeenVersionKey, kAppVersion);
    }
  }

  Future<void> _rescan() async {
    await ref.read(discoveryServiceProvider).rescan();
    ref.read(connectorProvider).kick();
    // Give mDNS a beat to re-browse so the refresh feels real.
    await Future.delayed(const Duration(milliseconds: 900));
  }

  // ── Incoming offer bottom sheet ────────────────────────────────────────────

  void _showOfferSheet(OfferData offer) {
    showModalBottomSheet(
      context: context,
      isDismissible: false,
      enableDrag: false,
      isScrollControlled: true,
      builder: (context) => _OfferSheet(
        offer: offer,
        onReject: () {
          ref.read(activeOfferProvider.notifier).reject();
          Navigator.pop(context);
        },
        onAccept: () {
          ref.read(activeOfferProvider.notifier).accept();
          Navigator.pop(context);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(transferServiceProvider);

    final peersAsync = ref.watch(peerListProvider);
    final progress = ref.watch(transferProgressProvider);
    final updateAsync = ref.watch(updateProvider);
    final updateInfo = updateAsync.valueOrNull;

    ref.listen<Map<String, dynamic>?>(intakeProvider, (_, next) {
      if (next != null) _handleIntake(next);
    });

    ref.listen<OfferData?>(activeOfferProvider, (previous, next) {
      if (next != null) _showOfferSheet(next);
    });

    ref.listen<IncomingText?>(incomingTextProvider, (previous, next) {
      if (next == null) return;
      // Already visible in the thread when that device's screen is open.
      if (ref.read(openDeviceNameProvider) == next.senderName) return;
      final preview = next.text.length > 80
          ? '${next.text.substring(0, 80)}…'
          : next.text;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              '${next.senderName}: $preview${next.copied ? ' — copied to clipboard' : ''}'),
        ),
      );
    });

    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(child: DecoratedBox(decoration: BoxDecoration(gradient: kPageGlow))),
          RefreshIndicator(
            onRefresh: _rescan,
            color: kAccent,
            backgroundColor: kSurfaceRaised,
            child: _buildBody(context, ref, peersAsync, updateInfo),
          ),
          if (progress != null)
            Positioned(
              left: 16,
              right: 16,
              bottom: 16,
              child: _buildProgress(context, ref, progress),
            ),
        ],
      ),
    );
  }

  Widget _buildBody(BuildContext context, WidgetRef ref,
      AsyncValue<List<Peer>> peersAsync, dynamic updateInfo) {
    final bannerVisible = ref.watch(updateBannerVisibleProvider);
    final peers = peersAsync.valueOrNull ?? <Peer>[];
    final paired = peers.where((p) => p.paired).toList();
    final nearby = peers.where((p) => !p.paired).toList();

    return CustomScrollView(
      physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
      slivers: [
        SliverAppBar(
          pinned: true,
          toolbarHeight: 68,
          backgroundColor: kBg,
          titleSpacing: 20,
          title: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // The transmit lamp
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: kAccent,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(color: kAccent.withValues(alpha: 0.16), spreadRadius: 5),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              Text('PALT', style: display(fontSize: 24, fontWeight: FontWeight.w800)),
            ],
          ),
          actions: [
            if (updateInfo?.isNewer == true &&
                !ref.watch(updateBannerVisibleProvider))
              IconButton(
                icon: Icon(Icons.arrow_circle_up_rounded, color: kAccent),
                tooltip: 'Update available',
                onPressed: () => ref
                    .read(updateBannerVisibleProvider.notifier)
                    .state = true,
              ),
            IconButton(
              icon: Icon(Icons.history_rounded, color: kTextSecondary),
              tooltip: 'History',
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const HistoryScreen()),
              ),
            ),
            IconButton(
              icon: Icon(Icons.tune_rounded, color: kTextSecondary),
              tooltip: 'Settings',
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SettingsScreen()),
              ),
            ),
            const SizedBox(width: 8),
          ],
        ),

        if (bannerVisible && updateInfo != null)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: UpdateBanner(info: updateInfo),
            ),
          ),

        const SliverToBoxAdapter(child: BackgroundBanner()),

        const SliverToBoxAdapter(child: LocalDeviceCard()),

        if (paired.isNotEmpty) ...[
          _sectionHeader('YOUR DEVICES', '${paired.length} connected'),
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, i) => PeerCard(peer: paired[i]),
              childCount: paired.length,
            ),
          ),
        ],

        const SliverToBoxAdapter(child: AsleepDevices()),

        if (nearby.isNotEmpty) ...[
          _sectionHeader('NEARBY', 'not paired'),
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, i) => PeerCard(peer: nearby[i]),
              childCount: nearby.length,
            ),
          ),
        ],

        if (peers.isEmpty)
          peersAsync.when(
            data: (_) => SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 48),
                child: _buildEmptyState(),
              ),
            ),
            error: (err, _) => SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(40),
                child: Text(
                  'Discovery hit a problem: $err\nPull down to try again.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: kTextSecondary, fontSize: 13),
                ),
              ),
            ),
            loading: () => const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.all(48),
                child: Center(child: CircularProgressIndicator()),
              ),
            ),
          ),

        SliverFillRemaining(
          hasScrollBody: false,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              const SizedBox(height: 28),
              _pairButton(context),
              const SizedBox(height: 14),
              _buildFooter(context),
              // Room for the live transfer card.
              SizedBox(height: ref.watch(transferProgressProvider) != null ? 150 : 18),
            ],
          ),
        ),
      ],
    );
  }

  Widget _sectionHeader(String title, String trailing) => SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 26, 20, 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(child: Text(title, style: overline(color: kTextSecondary))),
              Text(trailing, style: mono(color: kTextFaint)),
            ],
          ),
        ),
      );

  /// Pairing lives here, at the thumb, instead of a header icon.
  Widget _pairButton(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: CustomPaint(
          painter: _DashedBorder(color: kHairline, radius: 18),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PairScreen())),
              child: SizedBox(
                height: 56,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.qr_code_scanner_rounded, color: kAccent, size: 20),
                    const SizedBox(width: 10),
                    Text('Pair a device',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: kAccent)),
                  ],
                ),
              ),
            ),
          ),
        ),
      );

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          BeaconPulse(
            active: true,
            size: 84,
            child: Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(
                color: kSurface,
                shape: BoxShape.circle,
                border: Border.all(color: kHairline),
              ),
              child: Icon(Icons.wifi_tethering_rounded,
                  size: 34, color: kAccent),
            ),
          ),
          const SizedBox(height: 26),
          Text('Listening for devices', style: display(fontSize: 19)),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Text(
              'Open PALT on another device on this Wi‑Fi — it appears here the moment it announces itself.',
              textAlign: TextAlign.center,
              style: TextStyle(color: kTextSecondary, fontSize: 13, height: 1.5),
            ),
          ),
          const SizedBox(height: 12),
          Text('broadcasting on _palt._tcp.local',
              style: mono(fontSize: 11, color: kTextFaint)),
        ],
      ),
    );
  }

  // ── Live transfer card ─────────────────────────────────────────────────────

  Widget _buildProgress(
      BuildContext context, WidgetRef ref, TransferProgress progress) {
    final isCompleted = progress.status == TransferStatus.completed;
    final isError = progress.status == TransferStatus.error;
    final isWaiting = progress.status == TransferStatus.waiting;
    final stateColor = isError ? kDanger : (isCompleted ? kOk : kAccent);

    final percent = progress.total > 0 ? progress.written / progress.total : 0.0;
    final speedStr = progress.speed != null
        ? '${_formatBytes(progress.speed!.toInt())}/s'
        : '—';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: kSurfaceRaised,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: stateColor.withValues(alpha: 0.4)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: stateColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  isError
                      ? Icons.error_outline_rounded
                      : isCompleted
                          ? Icons.check_circle_outline_rounded
                          : isWaiting
                              ? Icons.hourglass_empty_rounded
                              : Icons.swap_vert_rounded,
                  size: 19,
                  color: stateColor,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isError
                          ? 'Transfer failed'
                          : isCompleted
                              ? 'Transfer complete'
                              : isWaiting
                                  ? 'Waiting for the other device…'
                                  : (progress.currentFileName ?? 'Transferring…'),
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                        color: kText,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (!isError && !isWaiting && !isCompleted)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          'file ${progress.sentItems ?? 1} of ${progress.totalItems ?? 1}',
                          style: TextStyle(
                              fontSize: 12, color: kTextSecondary),
                        ),
                      ),
                  ],
                ),
              ),
              if (progress.route != null && !isError) ...[
                const SizedBox(width: 8),
                RouteBadge(route: progress.route),
              ],
              if (isCompleted && progress.filePath != null)
                TextButton.icon(
                  onPressed: () {
                    OpenFilex.open(progress.filePath!);
                    ref.read(transferProgressProvider.notifier).state = null;
                  },
                  icon: const Icon(Icons.folder_open_rounded, size: 17),
                  style: TextButton.styleFrom(foregroundColor: kOk),
                  label: const Text('Open'),
                ),
              if (isCompleted || isError)
                IconButton(
                  icon: Icon(Icons.close_rounded,
                      size: 19, color: kTextFaint),
                  onPressed: () =>
                      ref.read(transferProgressProvider.notifier).state = null,
                ),
            ],
          ),
          if (isError) ...[
            const SizedBox(height: 10),
            Text(
              progress.error ?? 'Unknown error',
              style: TextStyle(
                  color: kDanger, fontSize: 12.5, fontWeight: FontWeight.w500),
            ),
          ] else ...[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: isWaiting ? null : (isCompleted ? 1.0 : percent),
                minHeight: 5,
                backgroundColor: kHairline,
                valueColor: AlwaysStoppedAnimation<Color>(stateColor),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${_formatBytes(progress.written)} / ${_formatBytes(progress.total)}',
                  style: mono(fontSize: 10.5, color: kTextFaint),
                ),
                Text(
                  isCompleted
                      ? 'done'
                      : isWaiting
                          ? 'waiting'
                          : '$speedStr · ${(percent * 100).toInt()}%',
                  style: mono(fontSize: 10.5),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) return "0 B";
    const suffixes = ["B", "KB", "MB", "GB", "TB"];
    var i = (log(bytes) / log(1024)).floor();
    return '${(bytes / pow(1024, i)).toStringAsFixed(1)} ${suffixes[i]}';
  }

  Widget _buildFooter(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: Text(
        'PALT $kAppVersion · made with ❤️ by uriel',
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 11, color: kTextFaint),
      ),
    );
  }
}

// ── Offer bottom sheet ────────────────────────────────────────────────────────

class _OfferSheet extends StatefulWidget {
  final OfferData offer;
  final VoidCallback onReject;
  final VoidCallback onAccept;

  const _OfferSheet({
    required this.offer,
    required this.onReject,
    required this.onAccept,
  });

  @override
  State<_OfferSheet> createState() => _OfferSheetState();
}

class _OfferSheetState extends State<_OfferSheet> {

  String _formatBytes(int bytes) {
    if (bytes <= 0) return "0 B";
    const suffixes = ["B", "KB", "MB", "GB", "TB"];
    var i = (log(bytes) / log(1024)).floor();
    return '${(bytes / pow(1024, i)).toStringAsFixed(1)} ${suffixes[i]}';
  }

  @override
  Widget build(BuildContext context) {
    final offer = widget.offer;
    final fileCount = offer.files.length;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
            20, 12, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Grab handle
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: kHairline,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: kOk.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.south_west_rounded,
                      color: kOk, size: 20),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text('INCOMING TRANSFER', style: overline()),
                          const SizedBox(width: 8),
                          RouteBadge(route: offer.route),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        offer.senderName,
                        style: display(fontSize: 19),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // File manifest
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: kBg,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: kHairline),
              ),
              child: Column(
                children: [
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 170),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: offer.files.length,
                      itemBuilder: (context, index) {
                        final file = offer.files[index];
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  file.name,
                                  style: TextStyle(
                                      fontSize: 13, color: kText),
                                  overflow: TextOverflow.ellipsis,
                                  maxLines: 1,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Text(_formatBytes(file.size),
                                  style: mono(
                                      fontSize: 11, color: kTextFaint)),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                  const Divider(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '$fileCount file${fileCount != 1 ? 's' : ''}',
                        style: TextStyle(
                            fontSize: 12, color: kTextSecondary),
                      ),
                      Text(_formatBytes(offer.totalSize),
                          style: mono(
                              color: kText, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '${offer.senderName} isn\'t paired. Pair it (link icon at the top) '
              'and its files come in without asking.',
              style: TextStyle(fontSize: 12.5, color: kTextFaint),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: widget.onReject,
                    child: const Text('Decline'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: widget.onAccept,
                    child: const Text('Accept'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// A rounded dashed outline.
class _DashedBorder extends CustomPainter {
  final Color color;
  final double radius;
  const _DashedBorder({required this.color, required this.radius});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final path = Path()
      ..addRRect(RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(radius)));
    for (final m in path.computeMetrics()) {
      for (var d = 0.0; d < m.length; d += 10) {
        canvas.drawPath(m.extractPath(d, d + 5), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorder old) => old.color != color || old.radius != radius;
}
