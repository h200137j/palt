/// peer_card.dart — a device on the home screen (Beacon).
///
/// Paired devices get a hero card: identity and route, battery, network and
/// what's playing, and the four actions used most (Send in amber). Devices
/// that aren't paired are a slim row with a Send button — files and text
/// only. Tapping either opens the device screen; long-press renames.
library;

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart' as fp;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/device_actions.dart';
import '../../features/media.dart';
import '../../features/phone_features.dart';
import 'device_status.dart';
import 'dart:io';

import '../../models/peer.dart';
import '../../utils/os_icons.dart';
import '../../services/transfer_service.dart';
import '../../theme/app_theme.dart';

import '../../providers/alias_provider.dart';
import '../screens/device_screen.dart';
import 'route_badge.dart';

/// Opens the system file picker and streams the chosen files to [peer].
Future<void> pickAndSendFiles(WidgetRef ref, Peer peer) async {
  try {
    final result = await fp.FilePicker.pickFiles(allowMultiple: true);
    if (result == null || result.files.isEmpty) return;
    final files = result.paths
        .where((path) => path != null)
        .map((path) => File(path!))
        .toList();
    if (files.isNotEmpty) {
      await ref.read(transferServiceProvider).sendFiles(peer, files);
    }
  } catch (e) {
    // Handled by service
  }
}

void showRenameDialog(BuildContext context, WidgetRef ref, Peer peer) {
  final controller = TextEditingController(text: ref.read(aliasProvider)[peer.deviceName] ?? '');
  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('RENAME DEVICE', style: overline()),
          const SizedBox(height: 4),
          Text(
            peer.deviceName,
            style: display(fontSize: 19),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
      content: TextField(
        controller: controller,
        decoration: const InputDecoration(
          hintText: 'Nickname — leave empty to reset',
          helperText: 'Only this phone sees the nickname',
        ),
        autofocus: true,
        style: TextStyle(color: kText),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            ref.read(aliasProvider.notifier).setAlias(peer.deviceName, controller.text.trim());
            Navigator.pop(context);
          },
          child: const Text('Save'),
        ),
      ],
    ),
  );
}

class PeerCard extends ConsumerWidget {
  final Peer peer;

  const PeerCard({super.key, required this.peer});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (peer.paired) return _PairedCard(peer: peer);
    final osInfo = getOsInfo(peer.os);
    final alias = ref.watch(aliasProvider)[peer.deviceName] ?? '';

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      decoration: BoxDecoration(
        color: kSurface,
        borderRadius: BorderRadius.circular(18),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => DeviceScreen(peer: peer)),
          ),
          onLongPress: () => showRenameDialog(context, ref, peer),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: kSurfaceRaised,
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Icon(osInfo.icon, color: kTextSecondary, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        alias.isNotEmpty ? alias : peer.deviceName,
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: kText),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          RouteBadge(route: peer.via, ip: peer.ipAddress),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text('Files and text only',
                                style: TextStyle(fontSize: 12, color: kTextSecondary),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: () => pickAndSendFiles(ref, peer),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 36),
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                  child: const Text('Send'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A paired device as the hero of the home screen.
class _PairedCard extends ConsumerWidget {
  final Peer peer;
  const _PairedCard({required this.peer});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final osInfo = getOsInfo(peer.os);
    final alias = ref.watch(aliasProvider)[peer.deviceName] ?? '';
    final status = ref.watch(peerStatusProvider)[peer.deviceName];
    final playing = ref.watch(peerMediaProvider)[peer.deviceName]?.main?.playing ?? false;
    void open() => Navigator.push(context, MaterialPageRoute(builder: (_) => DeviceScreen(peer: peer)));

    final stats = <Widget>[
      if (status != null && status.battery >= 0)
        _Stat(
          lead: BatteryGlyph(status: status, width: 18),
          label: '${status.battery}%',
          color: batteryColor(status) == kText ? kTextSecondary : batteryColor(status),
        ),
      if (status != null && networkLabel(status).isNotEmpty)
        _Stat(lead: Icon(networkIcon(status), size: 15, color: kTextSecondary), label: networkLabel(status)),
      if (playing) _Stat(lead: Icon(Icons.music_note_rounded, size: 15, color: kTextSecondary), label: 'Playing'),
      if (status != null && status.isComputer)
        _Stat(
          lead: Icon(status.locked ? Icons.lock_rounded : Icons.lock_open_rounded, size: 15, color: kTextSecondary),
          label: status.locked ? 'Locked' : 'Unlocked',
        ),
    ];

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
      decoration: BoxDecoration(
        gradient: kCardGradient,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: kHairline),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: open,
          onLongPress: () => showRenameDialog(context, ref, peer),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: kAccent.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Icon(osInfo.icon, color: kAccent, size: 28),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(alias.isNotEmpty ? alias : peer.deviceName,
                              style: display(fontSize: 21, fontWeight: FontWeight.w800),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                          const SizedBox(height: 5),
                          Row(
                            children: [
                              Container(
                                width: 7,
                                height: 7,
                                decoration: BoxDecoration(color: kOk, shape: BoxShape.circle),
                              ),
                              const SizedBox(width: 7),
                              Text('Connected', style: TextStyle(fontSize: 13, color: kTextSecondary)),
                              const SizedBox(width: 8),
                              RouteBadge(route: peer.via, ip: peer.ipAddress),
                            ],
                          ),
                        ],
                      ),
                    ),
                    Icon(Icons.chevron_right_rounded, color: kTextFaint),
                  ],
                ),
                if (stats.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  const Divider(height: 1),
                  const SizedBox(height: 14),
                  Wrap(spacing: 18, runSpacing: 8, children: stats),
                ],
                const SizedBox(height: 18),
                Row(
                  children: [
                    _CardAction(
                      icon: Icons.arrow_upward_rounded,
                      label: 'Send',
                      primary: true,
                      onTap: () => pickAndSendFiles(ref, peer),
                    ),
                    const SizedBox(width: 8),
                    _CardAction(
                      icon: Icons.content_paste_go_rounded,
                      label: 'Clipboard',
                      onTap: () => sendClipboardTo(context, ref, peer),
                    ),
                    const SizedBox(width: 8),
                    _CardAction(
                      icon: Icons.notifications_active_rounded,
                      label: 'Ring',
                      onTap: () => sendDevicePacket(context, ref, peer, 'ring'),
                    ),
                    const SizedBox(width: 8),
                    _CardAction(
                      icon: Icons.play_arrow_rounded,
                      label: 'Media',
                      onTap: open,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final Widget lead;
  final String label;
  final Color? color;
  const _Stat({required this.lead, required this.label, this.color});

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          lead,
          const SizedBox(width: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 150),
            child: Text(label, style: mono(fontSize: 12, color: color ?? kTextSecondary), maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
        ],
      );
}

class _CardAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool primary;
  const _CardAction({required this.icon, required this.label, required this.onTap, this.primary = false});

  @override
  Widget build(BuildContext context) {
    final fg = primary ? kOnAccent : kText.withValues(alpha: 0.85);
    return Expanded(
      child: Ink(
        decoration: BoxDecoration(
          gradient: primary ? kAccentGradient : null,
          color: primary ? null : Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(16),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: SizedBox(
            height: 64,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 21, color: fg),
                const SizedBox(height: 4),
                Text(label,
                    style: TextStyle(fontSize: 12, fontWeight: primary ? FontWeight.w600 : FontWeight.w500, color: fg),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
