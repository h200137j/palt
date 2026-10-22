/// device_status.dart — a device's battery and network as instrument
/// readouts (Beacon): a small battery meter, the network it's on, and the
/// route PALT uses to reach it.
library;

import 'package:flutter/material.dart';

import '../../features/phone_features.dart';
import '../../models/peer.dart';
import '../../theme/app_theme.dart';
import 'route_badge.dart';

bool _low(DeviceStatus s) => s.battery >= 0 && s.battery <= 15 && !s.charging;

Color batteryColor(DeviceStatus s) => _low(s)
    ? kDanger
    : s.charging
        ? kOk
        : kText;

/// "HomeNet", "Mobile data · 5G", "Ethernet" — '' when unknown.
String networkLabel(DeviceStatus s) => switch (s.network) {
      'wifi' => s.ssid.isEmpty ? 'Wi-Fi' : s.ssid,
      'cellular' =>
        s.cellular.isEmpty ? 'Mobile data' : 'Mobile data · ${s.cellular}',
      'ethernet' => 'Ethernet',
      'usb' => 'USB cable only',
      _ => '',
    };

IconData networkIcon(DeviceStatus s) => switch (s.network) {
      'wifi' => Icons.wifi_rounded,
      'cellular' => Icons.signal_cellular_alt_rounded,
      'ethernet' => Icons.settings_ethernet_rounded,
      'usb' => Icons.usb_rounded,
      _ => Icons.signal_wifi_off_rounded,
    };

/// A horizontal battery glyph filled to the level.
class BatteryGlyph extends StatelessWidget {
  final DeviceStatus status;
  final double width;
  const BatteryGlyph({super.key, required this.status, this.width = 22});

  @override
  Widget build(BuildContext context) {
    final c = batteryColor(status);
    final level = status.battery.clamp(0, 100) / 100;
    final h = width * 0.5;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: width,
          height: h,
          padding: const EdgeInsets.all(1.5),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(3),
            border: Border.all(color: c.withValues(alpha: 0.7), width: 1.2),
          ),
          child: Align(
            alignment: Alignment.centerLeft,
            child: FractionallySizedBox(
              widthFactor: level.toDouble(),
              heightFactor: 1,
              child: Container(
                decoration: BoxDecoration(
                    color: c, borderRadius: BorderRadius.circular(1.5)),
              ),
            ),
          ),
        ),
        Container(
          width: 2,
          height: h * 0.45,
          decoration: BoxDecoration(
            color: c.withValues(alpha: 0.7),
            borderRadius:
                const BorderRadius.horizontal(right: Radius.circular(1)),
          ),
        ),
      ],
    );
  }
}

/// Four signal bars lit up to [level] (0-4).
class SignalBars extends StatelessWidget {
  final int level;
  const SignalBars({super.key, required this.level});

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 1; i <= 4; i++)
            Container(
              width: 3.5,
              height: 3.0 + i * 2.6,
              margin: const EdgeInsets.only(right: 1.5),
              decoration: BoxDecoration(
                color: i <= level ? kText : kHairline,
                borderRadius: BorderRadius.circular(1),
              ),
            ),
        ],
      );
}

/// One line: battery glyph + %, network icon + name. For cards.
class StatusLine extends StatelessWidget {
  final DeviceStatus? status;
  const StatusLine({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    final s = status;
    if (s == null) {
      return Text('Waiting for status…',
          style: mono(fontSize: 11.5, color: kTextFaint));
    }
    final net = networkLabel(s);
    return Row(
      children: [
        if (s.battery >= 0) ...[
          BatteryGlyph(status: s),
          const SizedBox(width: 6),
          Text('${s.battery}%',
              style: mono(fontSize: 12, color: batteryColor(s))),
          if (s.charging) Icon(Icons.bolt_rounded, size: 14, color: kOk),
          const SizedBox(width: 14),
        ],
        if (net.isNotEmpty) ...[
          if (s.network == 'cellular' && s.signal >= 0)
            SignalBars(level: s.signal)
          else
            Icon(networkIcon(s), size: 15, color: kTextSecondary),
          const SizedBox(width: 6),
          Flexible(
            child: Text(net,
                style: mono(fontSize: 12, color: kTextSecondary),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
          ),
        ],
      ],
    );
  }
}

/// The big readout under a device's title: battery, network, route.
class StatusPanel extends StatelessWidget {
  final DeviceStatus? status;
  final Peer peer;
  final bool online;
  const StatusPanel(
      {super.key,
      required this.status,
      required this.peer,
      required this.online});

  @override
  Widget build(BuildContext context) {
    final s = status ?? const DeviceStatus();
    final net = networkLabel(s);
    return Row(
      children: [
        Expanded(
          child: _Tile(
            label: 'BATTERY',
            footer: s.battery < 0
                ? (status == null ? 'not reported' : 'no battery')
                : s.charging
                    ? 'Charging'
                    : _low(s)
                        ? 'Low'
                        : 'On battery',
            footerColor: s.charging ? kOk : (_low(s) ? kDanger : null),
            child: s.battery < 0
                ? Text(online ? '—' : 'offline',
                    style: mono(fontSize: 18, color: kTextFaint))
                : Row(
                    children: [
                      Text('${s.battery}',
                          style: display(fontSize: 26, color: batteryColor(s))),
                      Text('%',
                          style: mono(fontSize: 13, color: kTextSecondary)),
                      const Spacer(),
                      BatteryGlyph(status: s, width: 30),
                    ],
                  ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _Tile(
            label: 'NETWORK',
            footer: !online
                ? 'offline'
                : peer.viaRelay
                    ? 'via relay · encrypted'
                    : '${routeLabel(peer.via, peer.ipAddress)} · ${peer.ipAddress}',
            footerColor: online ? routeColor(peer.via, peer.ipAddress) : null,
            child: Row(
              children: [
                if (s.network == 'cellular' && s.signal >= 0)
                  SignalBars(level: s.signal)
                else
                  Icon(networkIcon(s),
                      size: 20, color: net.isEmpty ? kTextFaint : kText),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(net.isEmpty ? '—' : net,
                      style: display(fontSize: 15),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Tile extends StatelessWidget {
  final String label;
  final Widget child;
  final String footer;
  final Color? footerColor;
  const _Tile(
      {required this.label,
      required this.child,
      required this.footer,
      this.footerColor});

  @override
  Widget build(BuildContext context) => Container(
        height: 92,
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(
          color: kSurface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: kHairline),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: overline()),
            child,
            Text(footer,
                style: mono(fontSize: 10.5, color: footerColor ?? kTextFaint),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
          ],
        ),
      );
}

/// Round quick-action buttons with captions, [perRow] to a row.
class QuickActions extends StatelessWidget {
  final List<({IconData icon, String label, VoidCallback? onTap})> actions;
  final int perRow;
  const QuickActions({super.key, required this.actions, this.perRow = 4});

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, box) => Wrap(
          children: [
            for (final a in actions)
              SizedBox(
                width: box.maxWidth / perRow,
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: a.onTap,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: kSurfaceRaised,
                            shape: BoxShape.circle,
                            border: Border.all(color: kHairline),
                          ),
                          child: Icon(a.icon,
                              size: 20,
                              color: a.onTap == null ? kTextFaint : kText),
                        ),
                        const SizedBox(height: 5),
                        Text(a.label,
                            style: TextStyle(
                                fontSize: 11.5,
                                color: a.onTap == null
                                    ? kTextFaint
                                    : kTextSecondary,
                                fontWeight: FontWeight.w500)),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
}
