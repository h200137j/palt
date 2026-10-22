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
import 'package:google_fonts/google_fonts.dart';

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
import 'palt_page.dart';
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

  /// Position in its list; Pop and Paper use it for colour and numbering.
  final int index;

  const PeerCard({super.key, required this.peer, this.index = 0});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (peer.paired) {
      return switch (palt.style) {
        PaltStyle.material => _MaterialPairedCard(peer: peer, index: index),
        PaltStyle.aurora => _AuroraPairedCard(peer: peer),
        PaltStyle.paper => _PaperPairedCard(peer: peer, index: index),
        PaltStyle.pop => _PopPairedCard(peer: peer, index: index),
        PaltStyle.beacon => _PairedCard(peer: peer),
      };
    }
    if (!isBeacon) return _NearbyRow(peer: peer, index: index);
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

// ── The other themes' cards ──────────────────────────────────────────────────

void _open(BuildContext context, Peer peer) =>
    Navigator.push(context, MaterialPageRoute(builder: (_) => DeviceScreen(peer: peer)));

/// What a paired device reports, as (icon, label, colour) facts.
List<({IconData icon, String label, Color? color})> peerFacts(WidgetRef ref, Peer peer) {
  final status = ref.watch(peerStatusProvider)[peer.deviceName];
  final playing = ref.watch(peerMediaProvider)[peer.deviceName]?.main?.playing ?? false;
  return [
    if (status != null && status.battery >= 0)
      (
        icon: status.charging ? Icons.battery_charging_full_rounded : Icons.battery_5_bar_rounded,
        label: '${status.battery}%',
        color: batteryColor(status) == kText ? null : batteryColor(status),
      ),
    if (status != null && networkLabel(status).isNotEmpty)
      (icon: networkIcon(status), label: networkLabel(status), color: null),
    if (playing) (icon: Icons.graphic_eq_rounded, label: 'Playing', color: null),
    if (status != null && status.isComputer)
      (
        icon: status.locked ? Icons.lock_rounded : Icons.lock_open_rounded,
        label: status.locked ? 'Locked' : 'Unlocked',
        color: null,
      ),
  ];
}

String _name(WidgetRef ref, Peer peer) {
  final alias = ref.watch(aliasProvider)[peer.deviceName] ?? '';
  return alias.isNotEmpty ? alias : peer.deviceName;
}

/// Material: a filled card with a cookie avatar, assist chips, and a
/// button group — Send filled, the rest tonal.
class _MaterialPairedCard extends ConsumerWidget {
  final Peer peer;
  final int index;
  const _MaterialPairedCard({required this.peer, required this.index});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final facts = peerFacts(ref, peer);
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Card(
        clipBehavior: Clip.antiAlias,
        color: cs.surfaceContainerHigh,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        child: InkWell(
          onTap: () => _open(context, peer),
          onLongPress: () => showRenameDialog(context, ref, peer),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                DeviceBadge(icon: getOsInfo(peer.os).icon, size: 52),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(_name(ref, peer),
                        style: Theme.of(context).textTheme.titleLarge, maxLines: 1, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 2),
                    Text('Connected · ${routeLabel(peer.via, peer.ipAddress)}',
                        style: TextStyle(color: cs.onSurfaceVariant, fontSize: 14)),
                  ]),
                ),
                IconButton(
                  onPressed: () => _open(context, peer),
                  icon: const Icon(Icons.arrow_forward_rounded),
                ),
              ]),
              if (facts.isNotEmpty) ...[
                const SizedBox(height: 14),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final f in facts)
                    Container(
                      height: 32,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: cs.outlineVariant),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(f.icon, size: 18, color: f.color ?? cs.primary),
                        const SizedBox(width: 6),
                        Text(f.label, style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
                      ]),
                    ),
                ]),
              ],
              const SizedBox(height: 16),
              Row(children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => pickAndSendFiles(ref, peer),
                    icon: const Icon(Icons.upload_rounded),
                    label: const Text('Send files'),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filledTonal(
                  tooltip: 'Send clipboard',
                  onPressed: () => sendClipboardTo(context, ref, peer),
                  icon: const Icon(Icons.content_paste_go_rounded),
                  style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
                ),
                const SizedBox(width: 4),
                IconButton.filledTonal(
                  tooltip: 'Ring',
                  onPressed: () => sendDevicePacket(context, ref, peer, 'ring'),
                  icon: const Icon(Icons.notifications_active_rounded),
                  style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
                ),
                const SizedBox(width: 4),
                IconButton.filledTonal(
                  tooltip: 'Media',
                  onPressed: () => _open(context, peer),
                  icon: const Icon(Icons.play_arrow_rounded),
                  style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
                ),
              ]),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Aurora: a tall pane of frosted glass, its orb glowing, round actions.
class _AuroraPairedCard extends ConsumerWidget {
  final Peer peer;
  const _AuroraPairedCard({required this.peer});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final facts = peerFacts(ref, peer);
    Widget action(IconData icon, String label, VoidCallback onTap, {bool lit = false}) => Expanded(
          child: GestureDetector(
            onTap: onTap,
            child: Column(children: [
              Container(
                width: 52,
                height: 52,
                decoration: lit
                    ? BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: kAccentGradient,
                        boxShadow: [BoxShadow(color: kAccent.withValues(alpha: 0.5), blurRadius: 20, spreadRadius: -4)],
                      )
                    : paltDeco(shape: BoxShape.circle),
                child: Icon(icon, size: 22, color: lit ? kOnAccent : kText),
              ),
              const SizedBox(height: 6),
              Text(label, style: TextStyle(fontSize: 11.5, color: kTextSecondary)),
            ]),
          ),
        );
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 6),
      decoration: paltDeco(radius: 30, gradient: kCardGradient, hero: true),
      clipBehavior: Clip.antiAlias,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: () => _open(context, peer),
          onLongPress: () => showRenameDialog(context, ref, peer),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
            child: Column(children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                DeviceBadge(icon: getOsInfo(peer.os).icon, size: 54),
                const Spacer(),
                RouteBadge(route: peer.via, ip: peer.ipAddress),
              ]),
              const SizedBox(height: 18),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(_name(ref, peer),
                    style: display(fontSize: 26, fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  facts.isEmpty ? 'Connected' : facts.map((f) => f.label).join('  ·  '),
                  style: TextStyle(color: kTextSecondary, fontSize: 13),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const Spacer(),
              Row(children: [
                action(Icons.arrow_upward_rounded, 'Send', () => pickAndSendFiles(ref, peer), lit: true),
                action(Icons.content_paste_go_rounded, 'Clipboard', () => sendClipboardTo(context, ref, peer)),
                action(Icons.notifications_active_rounded, 'Ring', () => sendDevicePacket(context, ref, peer, 'ring')),
                action(Icons.tune_rounded, 'Control', () => _open(context, peer)),
              ]),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Paper: a device as a newspaper article — headline, deck, and actions as
/// a line of red links.
class _PaperPairedCard extends ConsumerWidget {
  final Peer peer;
  final int index;
  const _PaperPairedCard({required this.peer, required this.index});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final facts = peerFacts(ref, peer);
    final status = ref.watch(peerStatusProvider)[peer.deviceName];
    final deck = [
      'Connected over ${routeLabel(peer.via, peer.ipAddress).replaceFirst('via ', 'the ')}',
      if (status != null && status.battery >= 0) 'battery at ${status.battery}%${status.charging ? ' and charging' : ''}',
      if (facts.any((f) => f.label == 'Playing')) 'playing music',
      if (status != null && status.isComputer) status.locked ? 'screen locked' : 'unlocked',
    ].join(', ');
    Widget link(String label, VoidCallback onTap) => InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(label,
                style: TextStyle(
                  color: kAccent,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                  decoration: TextDecoration.underline,
                  decorationColor: kAccent.withValues(alpha: 0.4),
                )),
          ),
        );
    return InkWell(
      onTap: () => _open(context, peer),
      onLongPress: () => showRenameDialog(context, ref, peer),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 16, 22, 4),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('NO. ${index + 1} · ${getOsInfo(peer.os).label.toUpperCase()}',
                    style: mono(fontSize: 10, color: kAccent).copyWith(letterSpacing: 1.6)),
                const SizedBox(height: 4),
                Text(_name(ref, peer), style: display(fontSize: 32), maxLines: 2, overflow: TextOverflow.ellipsis),
              ]),
            ),
            const SizedBox(width: 12),
            DeviceBadge(icon: getOsInfo(peer.os).icon, size: 46),
          ]),
          const SizedBox(height: 8),
          Text('$deck.',
              style: GoogleFonts.getFont('Newsreader', fontSize: 16, fontStyle: FontStyle.italic, color: kTextSecondary, height: 1.35)),
          const SizedBox(height: 8),
          Divider(height: 1, color: kHairline),
          Wrap(spacing: 18, children: [
            link('Send a file', () => pickAndSendFiles(ref, peer)),
            link('Clipboard', () => sendClipboardTo(context, ref, peer)),
            link('Ring', () => sendDevicePacket(context, ref, peer, 'ring')),
            link('Open →', () => _open(context, peer)),
          ]),
          const SizedBox(height: 6),
          Container(height: 1, color: kText),
        ]),
      ),
    );
  }
}

/// Pop: a white slab with a loud name band, sticker facts and fat buttons.
class _PopPairedCard extends ConsumerWidget {
  final Peer peer;
  final int index;
  const _PopPairedCard({required this.peer, required this.index});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final facts = peerFacts(ref, peer);
    Widget block(int c, IconData icon, String label, VoidCallback onTap) => Expanded(
          child: PressDown(
            onTap: onTap,
            child: Container(
              height: 62,
              decoration: paltDeco(radius: 10, color: c < 0 ? kAccent : popColor(c, kAccent)),
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(icon, size: 22, color: c < 0 ? kOnAccent : kText),
                const SizedBox(height: 2),
                Text(label,
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: c < 0 ? kOnAccent : kText)),
              ]),
            ),
          ),
        );
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 6, 22, 14),
      child: PressDown(
        onTap: () => _open(context, peer),
        onLongPress: () => showRenameDialog(context, ref, peer),
        child: Container(
          decoration: paltDeco(radius: 18, color: kSurface, hero: true),
          clipBehavior: Clip.antiAlias,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Container(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              decoration: BoxDecoration(
                color: popColor(index + 3, kAccent),
                border: Border(bottom: BorderSide(color: kText, width: 2)),
              ),
              child: Row(children: [
                DeviceBadge(icon: getOsInfo(peer.os).icon, size: 44, lit: false),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(_name(ref, peer).toUpperCase(),
                      style: display(fontSize: 21), maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: paltDeco(radius: 999, color: kText, flat: true),
                  child: Text('LIVE', style: mono(fontSize: 10, fontWeight: FontWeight.w700, color: kSurface)),
                ),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final f in facts)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                      decoration: paltDeco(radius: 999, color: kBg, flat: true),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(f.icon, size: 15, color: f.color ?? kText),
                        const SizedBox(width: 5),
                        Text(f.label, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: kText)),
                      ]),
                    ),
                ]),
                const SizedBox(height: 14),
                Row(children: [
                  block(-1, Icons.arrow_upward_rounded, 'SEND', () => pickAndSendFiles(ref, peer)),
                  const SizedBox(width: 8),
                  block(0, Icons.content_paste_go_rounded, 'CLIP', () => sendClipboardTo(context, ref, peer)),
                  const SizedBox(width: 8),
                  block(1, Icons.notifications_active_rounded, 'RING', () => sendDevicePacket(context, ref, peer, 'ring')),
                  const SizedBox(width: 8),
                  block(2, Icons.play_arrow_rounded, 'MEDIA', () => _open(context, peer)),
                ]),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

/// A device that isn't paired, as each theme lists it.
class _NearbyRow extends ConsumerWidget {
  final Peer peer;
  final int index;
  const _NearbyRow({required this.peer, required this.index});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final icon = getOsInfo(peer.os).icon;
    final name = _name(ref, peer);
    final sendButton = switch (palt.style) {
      PaltStyle.material => FilledButton.tonal(
          onPressed: () => pickAndSendFiles(ref, peer),
          child: const Text('Send'),
        ),
      PaltStyle.pop => PressDown(
          onTap: () => pickAndSendFiles(ref, peer),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            decoration: paltDeco(radius: 8, color: popColor(index + 1, kAccent)),
            child: Text('SEND', style: TextStyle(fontWeight: FontWeight.w800, color: kText, fontSize: 13)),
          ),
        ),
      PaltStyle.paper => TextButton(
          onPressed: () => pickAndSendFiles(ref, peer),
          child: const Text('Send →'),
        ),
      _ => OutlinedButton(
          onPressed: () => pickAndSendFiles(ref, peer),
          style: OutlinedButton.styleFrom(minimumSize: const Size(0, 38), padding: const EdgeInsets.symmetric(horizontal: 16)),
          child: const Text('Send'),
        ),
    };
    final row = InkWell(
      onTap: () => _open(context, peer),
      onLongPress: () => showRenameDialog(context, ref, peer),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: isPaper ? 22 : 14, vertical: 12),
        child: Row(children: [
          DeviceBadge(icon: icon, size: 42, lit: false, index: index),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name,
                  style: isPaper
                      ? display(fontSize: 20)
                      : TextStyle(fontSize: 15, fontWeight: isPop ? FontWeight.w700 : FontWeight.w500, color: kText),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
              const SizedBox(height: 3),
              Row(children: [
                RouteBadge(route: peer.via, ip: peer.ipAddress),
                const SizedBox(width: 8),
                Flexible(
                  child: Text('Files and text only',
                      style: TextStyle(fontSize: 12, color: kTextSecondary), maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
              ]),
            ]),
          ),
          const SizedBox(width: 8),
          sendButton,
        ]),
      ),
    );
    return switch (palt.style) {
      PaltStyle.material => Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 2),
          child: Material(
            color: kSurface,
            borderRadius: BorderRadius.circular(20),
            clipBehavior: Clip.antiAlias,
            child: row,
          ),
        ),
      PaltStyle.paper => Column(children: [row, Divider(height: 1, indent: 22, endIndent: 22, color: kHairline)]),
      _ => Padding(
          padding: const EdgeInsets.fromLTRB(18, 4, 22, 8),
          child: Container(
            decoration: paltDeco(radius: 18, color: isPop ? kSurface : null),
            clipBehavior: isPop ? Clip.none : Clip.antiAlias,
            child: Material(type: MaterialType.transparency, child: row),
          ),
        ),
    };
  }
}
