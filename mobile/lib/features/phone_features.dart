/// phone_features.dart — the everyday live features over links: battery and
/// signal reports, find my phone, pings, and notifications for messages.
///
/// Packet types (must match desktop/features_app.go):
///   status       either way       [DeviceStatus]: battery and network, on
///                                 link up and whenever they change
///   ring         either way       {} ring loudly to be found
///   ring.stop    either way       {}
///   user_ping    either way       {message?}
library;

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/link_provider.dart';
import '../services/link/link.dart';
import '../services/transfer_service.dart';
import 'remote_input.dart';
import 'wake.dart';

const _device = MethodChannel('palt/device');
const _intent = MethodChannel('palt/intent');

/// What a device reports about itself (Go DeviceStatus).
class DeviceStatus {
  final int battery; // 0-100, -1 none/unknown
  final bool charging;
  final String network; // wifi | cellular | ethernet | ''
  final String ssid;
  final String cellular; // 5G, LTE, … when on mobile data
  final int signal; // 0-4, -1 unknown
  final bool internet; // reaches the internet, not just the LAN

  // Computers only (desktop/computer_status_linux.go); never sent by phones.
  final bool locked;
  final int cpu; // % load
  final int ramUsed, ramTotal, diskFree, diskTotal; // bytes
  final int uptime; // seconds
  final int temp; // °C, 0 unknown
  final String wakeMac, wakeAddr;
  final bool wakeReady;

  const DeviceStatus({
    this.battery = -1,
    this.charging = false,
    this.network = '',
    this.ssid = '',
    this.cellular = '',
    this.signal = -1,
    this.internet = false,
    this.locked = false,
    this.cpu = 0,
    this.ramUsed = 0,
    this.ramTotal = 0,
    this.diskFree = 0,
    this.diskTotal = 0,
    this.uptime = 0,
    this.temp = 0,
    this.wakeMac = '',
    this.wakeAddr = '',
    this.wakeReady = false,
  });

  /// True when the device reported computer details.
  bool get isComputer => ramTotal > 0;

  factory DeviceStatus.fromJson(Map<String, dynamic> j) => DeviceStatus(
        battery: (j['battery'] as num?)?.toInt() ?? -1,
        charging: j['charging'] as bool? ?? false,
        network: j['network'] as String? ?? '',
        ssid: j['ssid'] as String? ?? '',
        cellular: j['cellular'] as String? ?? '',
        signal: (j['signal'] as num?)?.toInt() ?? -1,
        internet: j['internet'] as bool? ?? false,
        locked: j['locked'] as bool? ?? false,
        cpu: (j['cpu'] as num?)?.toInt() ?? 0,
        ramUsed: (j['ramUsed'] as num?)?.toInt() ?? 0,
        ramTotal: (j['ramTotal'] as num?)?.toInt() ?? 0,
        diskFree: (j['diskFree'] as num?)?.toInt() ?? 0,
        diskTotal: (j['diskTotal'] as num?)?.toInt() ?? 0,
        uptime: (j['uptime'] as num?)?.toInt() ?? 0,
        temp: (j['temp'] as num?)?.toInt() ?? 0,
        wakeMac: j['wakeMac'] as String? ?? '',
        wakeAddr: j['wakeAddr'] as String? ?? '',
        wakeReady: j['wakeReady'] as bool? ?? false,
      );

  Map<String, dynamic> toJson() => {
        'battery': battery,
        'charging': charging,
        'network': network,
        'ssid': ssid,
        'cellular': cellular,
        'signal': signal,
        'internet': internet,
      };
}

/// This phone's own status, as last sent.
final localStatusProvider = StateProvider<DeviceStatus?>((ref) => null);

/// Status reported by each linked device, by device name.
final peerStatusProvider = StateProvider<Map<String, DeviceStatus>>((ref) => const {});

/// Re-reads and sends this phone's status now (e.g. after a network change).
void Function() refreshPhoneStatus = () {};

/// A share from another app or a notification tap, for the UI to act on:
/// {paths: [..], text: ..} or {openDevice: name}.
final intakeProvider = StateProvider<Map<String, dynamic>?>((ref) => null);

bool get appInForeground => WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;

int _notifId = 100;

/// Shows a phone notification. [url] adds an "Open link" button; tapping
/// opens [device]'s chat.
Future<void> showPhoneNotification(String title, String text, {String? device, String? url}) async {
  try {
    await _device.invokeMethod('notify', {
      'id': _notifId++,
      'title': title,
      'text': text,
      'device': device,
      'url': url,
    });
  } catch (_) {}
}

/// The text as a URL when it is nothing but one web link.
String? singleUrl(String text) {
  final t = text.trim();
  if (t.contains(RegExp(r'\s'))) return null;
  final u = Uri.tryParse(t);
  if (u == null || (u.scheme != 'http' && u.scheme != 'https') || u.host.isEmpty) return null;
  return t;
}

/// Wires the features into the running core. Call once from startCore.
void setupPhoneFeatures(ProviderContainer c) {
  final links = c.read(linkManagerProvider);

  links.handle('input.focus', RemoteInput.onFocus);
  links.handle('ring', (l, p) => _device.invokeMethod('ring', {'from': l.peer.name}));
  links.handle('ring.stop', (l, p) => _device.invokeMethod('stopRing'));
  links.handle('user_ping', (l, p) {
    final msg = (p.body?['message'] as String?) ?? '';
    return showPhoneNotification(l.peer.name, msg.isEmpty ? 'Ping!' : msg, device: l.peer.name);
  });

  // A computer has no internet: offer hotspot / USB tethering.
  links.handle('internet.request',
      (l, p) => _device.invokeMethod('askTether', {'from': l.peer.name}));

  // A computer shared its Wi-Fi: ask before saving it (WifiShare.kt).
  links.handle('wifi.share', (l, p) {
    final b = p.body;
    if (b == null || (b['ssid'] as String? ?? '').isEmpty) return null;
    return _device.invokeMethod('wifiOffer', {
      'ssid': b['ssid'],
      'password': b['password'] ?? '',
      'security': b['security'] ?? '',
      'hidden': b['hidden'] ?? false,
      'from': l.peer.name,
    });
  });

  links.handle('status', (l, p) {
    if (p.body == null) return;
    final st = DeviceStatus.fromJson(p.body!);
    c.read(peerStatusProvider.notifier).update((m) => {...m, l.peer.name: st});
    if (st.wakeMac.isNotEmpty) c.read(wakeTargetsProvider.notifier).remember(l.peer.name, st);
  });

  // This phone's status: to each device as it links up, and on any change.
  Map<String, dynamic> battery = const {'level': -1, 'charging': false};
  String? lastSent;
  Future<Map<String, dynamic>> current() async {
    Map<String, dynamic> net = const {};
    try {
      net = Map<String, dynamic>.from(await _device.invokeMethod('connectivity') as Map);
    } catch (_) {}
    return DeviceStatus(
      battery: (battery['level'] as num?)?.toInt() ?? -1,
      charging: battery['charging'] as bool? ?? false,
      network: net['network'] as String? ?? '',
      ssid: net['ssid'] as String? ?? '',
      cellular: net['cellular'] as String? ?? '',
      signal: (net['signal'] as num?)?.toInt() ?? -1,
      internet: net['internet'] as bool? ?? false,
    ).toJson();
  }

  Future<void> send({Link? only}) async {
    final st = await current();
    c.read(localStatusProvider.notifier).state = DeviceStatus.fromJson(st);
    final key = st.toString();
    if (only != null) {
      if (only.supports('status')) only.send('status', body: st).catchError((_) {});
      return;
    }
    if (key == lastSent) return;
    lastSent = key;
    links.broadcast('status', body: st);
  }

  refreshPhoneStatus = () => send();
  // Android only reveals the Wi-Fi name to the app on screen: re-read on open.
  AppLifecycleListener(onResume: () => send());

  _device.setMethodCallHandler((call) async {
    if (call.method == 'battery') {
      battery = Map<String, dynamic>.from(call.arguments as Map);
      await send();
    }
  });
  _device.invokeMethod('battery').then((b) {
    battery = Map<String, dynamic>.from(b as Map);
  }, onError: (_) {});
  Timer.periodic(const Duration(seconds: 60), (_) => send());

  final told = <Link>{};
  c.listen<AsyncValue<List<Link>>>(linksProvider, (_, next) {
    final current = next.valueOrNull ?? const <Link>[];
    told.removeWhere((l) => !current.contains(l));
    final names = {for (final l in current) l.peer.name};
    c.read(peerStatusProvider.notifier).update((m) => {
          for (final e in m.entries)
            if (names.contains(e.key)) e.key: e.value
        });
    for (final l in current) {
      if (told.add(l)) send(only: l);
    }
  });

  // Messages arriving while the app isn't on screen.
  c.listen<IncomingText?>(incomingTextProvider, (_, t) {
    if (t == null || appInForeground) return;
    final url = singleUrl(t.text);
    showPhoneNotification(t.senderName, t.copied ? '${t.text}\n(copied to clipboard)' : t.text,
        device: t.senderName, url: url);
  });
  c.listen<OfferData?>(activeOfferProvider, (_, offer) {
    if (offer == null || appInForeground) return;
    final n = offer.files.length;
    showPhoneNotification(offer.senderName, 'Wants to send you $n file${n == 1 ? '' : 's'} — tap to accept or decline',
        device: offer.senderName);
  });
  c.listen<ReceivedFiles?>(receivedFilesProvider, (_, r) {
    if (r == null || appInForeground) return;
    final n = r.names.length;
    showPhoneNotification(r.senderName, n == 1 ? 'Sent you ${r.names.first}' : 'Sent you $n files',
        device: r.senderName);
  });

  // Shares from other apps and notification taps.
  Future<void> take() async {
    try {
      final m = await _intent.invokeMethod('take');
      if (m != null) c.read(intakeProvider.notifier).state = Map<String, dynamic>.from(m as Map);
    } catch (_) {}
  }

  _intent.setMethodCallHandler((call) async {
    if (call.method == 'ready') await take();
  });
  take();
}
