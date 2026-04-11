/// peer.dart — Shared data model for a discovered PALT device.
///
/// JSON schema matches the Go `models.Peer` struct exactly so future
/// REST/WebSocket calls between desktop ↔ mobile are schema-compatible.

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

  const Peer({
    required this.id,
    required this.deviceName,
    required this.ipAddress,
    required this.port,
    required this.os,
  });

  factory Peer.fromJson(Map<String, dynamic> json) => Peer(
        id: json['id'] as String,
        deviceName: json['deviceName'] as String,
        ipAddress: json['ipAddress'] as String,
        port: json['port'] as int,
        os: json['os'] as String,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'deviceName': deviceName,
        'ipAddress': ipAddress,
        'port': port,
        'os': os,
      };

  @override
  String toString() => 'Peer($deviceName @ $ipAddress:$port [$os])';

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is Peer && other.id == id;

  @override
  int get hashCode => id.hashCode;
}
