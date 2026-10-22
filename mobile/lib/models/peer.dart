/// peer.dart — Shared data model for a discovered PALT device.
///
/// JSON schema matches the Go `models.Peer` struct exactly so future
/// REST/WebSocket calls between desktop ↔ mobile are schema-compatible.
library;

/// Represents a single PALT device discovered on the local network.
class Peer {
  /// Stable unique ID — the mDNS instance name.
  final String id;

  /// Human-readable device name (hostname).
  final String deviceName;

  /// Resolved IPv4 address.
  final String ipAddress;

  /// TCP port the PALT transfer service is listening on.
  final int port;

  /// OS identifier: "linux" | "android" | "darwin" | "windows" | "unknown"
  final String os;

  /// How the peer is reachable: 'direct' (same LAN) or 'relay'.
  final String via;

  /// Stable PALT device ID ('' for builds before 2.0).
  final String deviceId;

  /// True while an authenticated link to this paired device is up.
  final bool paired;

  bool get viaRelay => via == 'relay';

  const Peer({
    required this.id,
    required this.deviceName,
    required this.ipAddress,
    required this.port,
    required this.os,
    this.via = 'direct',
    this.deviceId = '',
    this.paired = false,
  });

  factory Peer.fromJson(Map<String, dynamic> json) => Peer(
        id: json['id'] as String,
        deviceName: json['deviceName'] as String,
        ipAddress: json['ipAddress'] as String,
        port: json['port'] as int,
        os: json['os'] as String,
        via: json['via'] as String? ?? 'direct',
        deviceId: json['deviceId'] as String? ?? '',
        paired: json['paired'] as bool? ?? false,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'deviceName': deviceName,
        'ipAddress': ipAddress,
        'port': port,
        'os': os,
        'via': via,
        'deviceId': deviceId,
        'paired': paired,
      };

  @override
  String toString() => 'Peer($deviceName @ $ipAddress:$port [$os])';

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is Peer && other.id == id;

  @override
  int get hashCode => id.hashCode;
}
