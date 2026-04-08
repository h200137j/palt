/// discovery_service.dart
///
/// mDNS advertisement + peer browsing for PALT on Android.
///
/// Responsibilities:
///   1. Advertises this device as `_palt._tcp` via Android NSD.
///   2. Browses for other `_palt._tcp` instances.
///   3. Surfaces the peer list as a [Stream<List<Peer>>] consumed by Riverpod.
///
/// Dependencies (pubspec.yaml):
///   nsd: ^2.0.0
///   network_info_plus: ^6.0.0
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:nsd/nsd.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:device_info_plus/device_info_plus.dart';

import '../models/peer.dart';

/// mDNS service type — must match the Go discovery package.
const _kServiceType = '_palt._tcp';

/// TCP port advertised. Matches [paltPort] in Go app.go.
const _kPaltPort = 9876;

/// Manages mDNS advertising and peer discovery for the Android client.
class DiscoveryService {
  // ── State ──────────────────────────────────────────────────────────────────
  Registration? _registration;
  Discovery? _discovery;

  final Map<String, Peer> _peers = {};
  final _controller = StreamController<List<Peer>>.broadcast();

  String _localIp = '';
  String _deviceName = 'palt-device';

  // ── Public API ─────────────────────────────────────────────────────────────

  /// Live stream of the discovered peer list.
  /// Emits a new snapshot on every add/remove.
  Stream<List<Peer>> get peers => _controller.stream;

  /// Synchronous snapshot of the current peer list.
  List<Peer> get currentPeers => List.unmodifiable(_peers.values);

  /// Starts advertising and browsing. Safe to call multiple times.
  Future<void> start() async {
    _localIp = await getLocalIpAddress();
    _deviceName = await _fetchDeviceName();
    await _advertise();
    await _browse();
  }

  /// Stops advertising and browsing, closes the stream.
  Future<void> stop() async {
    if (_discovery != null) {
      await stopDiscovery(_discovery!);
      _discovery = null;
    }
    if (_registration != null) {
      await unregister(_registration!);
      _registration = null;
    }
    if (!_controller.isClosed) await _controller.close();
  }

  // ── Advertisement ──────────────────────────────────────────────────────────

  Future<void> _advertise() async {
    if (_registration != null) return;

    final name = _deviceName;

    final service = Service(
      name: name,
      type: _kServiceType,
      port: _kPaltPort,
      txt: _encodeTxt({'os': 'android', 'app': 'palt'}),
    );

    try {
      _registration = await register(service);
      _log('Advertising as "$name" on port $_kPaltPort');
    } catch (e) {
      _log('ERROR advertising: $e');
    }
  }

  // ── Discovery ──────────────────────────────────────────────────────────────

  Future<void> _browse() async {
    if (_discovery != null) return;

    try {
      _discovery = await startDiscovery(
        _kServiceType,
        autoResolve: true,
        ipLookupType: IpLookupType.v4,
      );

      _discovery!.addServiceListener((service, status) {
        if (status == ServiceStatus.found) {
          _onFound(service);
        } else if (status == ServiceStatus.lost) {
          _onLost(service);
        }
      });

      _log('Browsing for $_kServiceType...');
    } catch (e) {
      _log('ERROR browsing: $e');
    }
  }

  // ── Handlers ───────────────────────────────────────────────────────────────

  void _onFound(Service service) {
    final name = service.name ?? 'unknown';
    final addresses = service.addresses;

    if (addresses == null || addresses.isEmpty) {
      _log('Found "$name" but no address resolved — skipping.');
      return;
    }

    final ip = addresses.first.address;

    // Skip self by comparing IPs natively
    if (ip == _localIp || ip == '127.0.0.1') {
      _log('Ignoring self via IP match: $ip');
      return;
    }
    final port = service.port ?? _kPaltPort;
    final txt = _decodeTxt(service.txt);
    final peerOS = txt['os'] ?? 'unknown';

    final peer = Peer(
      id: ip,
      deviceName: name,
      ipAddress: ip,
      port: port,
      os: peerOS,
    );

    _peers[ip] = peer;
    _emit();
    _log('Peer found: $peer');
  }

  void _onLost(Service service) {
    final name = service.name ?? '';
    int removedCount = 0;
    _peers.removeWhere((key, value) {
      if (value.deviceName == name) {
        removedCount++;
        return true;
      }
      return false;
    });
    if (removedCount > 0) {
      _emit();
      _log('Peer lost: $name');
    }
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  void _emit() {
    if (!_controller.isClosed) {
      _controller.add(List.unmodifiable(_peers.values));
    }
  }

  Map<String, Uint8List?> _encodeTxt(Map<String, String> map) =>
      map.map((k, v) => MapEntry(k, Uint8List.fromList(v.codeUnits)));

  Map<String, String> _decodeTxt(Map<String, Uint8List?>? txt) {
    if (txt == null) return {};
    return txt.map(
      (k, v) => MapEntry(k, v != null ? String.fromCharCodes(v) : ''),
    );
  }

  void _log(String msg) => print('[DiscoveryService] $msg'); // ignore: avoid_print

  Future<String> _fetchDeviceName() async {
    try {
      if (Platform.isAndroid) {
        final info = await DeviceInfoPlugin().androidInfo;
        return info.model;
      } else if (Platform.isIOS) {
        final info = await DeviceInfoPlugin().iosInfo;
        return info.name;
      }
    } catch (_) {}
    return Platform.localHostname.isNotEmpty ? Platform.localHostname : 'palt-mobile';
  }
}

/// Returns the device's own WiFi IP for display purposes.
Future<String> getLocalIpAddress() async {
  try {
    final info = NetworkInfo();
    return (await info.getWifiIP()) ?? 'Unknown';
  } catch (_) {
    return 'Unknown';
  }
}
