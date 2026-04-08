/// peer_provider.dart — Riverpod state layer for PALT peer discovery.
///
/// Architecture:
///   discoveryServiceProvider  → singleton DiscoveryService (auto-started)
///   localIpProvider           → AsyncProvider for the device's own IP
///   peerListProvider          → StreamProvider (live List<Peer>)
///   peerNotifierProvider      → AsyncNotifier with imperative rescan()
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/peer.dart';
import '../services/discovery_service.dart';

// ─── DiscoveryService singleton ────────────────────────────────────────────────

final discoveryServiceProvider = Provider<DiscoveryService>((ref) {
  final service = DiscoveryService();

  service.start().catchError((Object e) {
    print('[PeerProvider] Failed to start discovery: $e'); // ignore: avoid_print
  });

  ref.onDispose(service.stop);
  return service;
});

// ─── Local IP ──────────────────────────────────────────────────────────────────

final localIpProvider = FutureProvider<String>((ref) async {
  return getLocalIpAddress();
});

// ─── Live peer list ────────────────────────────────────────────────────────────

/// Emits a new snapshot every time a peer joins or leaves.
final peerListProvider = StreamProvider<List<Peer>>((ref) {
  return ref.watch(discoveryServiceProvider).peers;
});

// End of peer_provider.dart
