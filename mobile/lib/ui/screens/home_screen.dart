import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_filex/open_filex.dart';

import 'dart:math';

import '../../providers/peer_provider.dart';
import '../../providers/trust_provider.dart';
import '../../services/transfer_service.dart';
import '../widgets/local_device_card.dart';
import '../widgets/peer_card.dart';
import '../../theme/app_theme.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Start Transfer Service
    ref.watch(transferServiceProvider);

    final peersAsync = ref.watch(peerListProvider);
    
    // Watch Progress
    final progress = ref.watch(transferProgressProvider);

    // Listen to Incoming Offers
    ref.listen<OfferData?>(activeOfferProvider, (previous, next) {
      if (next != null) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) {
            bool alwaysTrust = false;
            final sizeStr = _formatBytes(next.fileSize);
            
            return StatefulBuilder(
              builder: (context, setState) {
                return AlertDialog(
                  title: const Text('Incoming File', style: TextStyle(fontWeight: FontWeight.bold)),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${next.senderName} wants to send you a file:'),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(next.fileName, style: const TextStyle(fontWeight: FontWeight.w600)),
                            Text(sizeStr, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12)),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      CheckboxListTile(
                        value: alwaysTrust,
                        onChanged: (val) => setState(() => alwaysTrust = val ?? false),
                        title: const Text('Always trust this sender', style: TextStyle(fontSize: 14)),
                        controlAffinity: ListTileControlAffinity.leading,
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        visualDensity: VisualDensity.compact,
                      ),
                    ],
                  ),
                  actions: [
                    TextButton(
                      onPressed: () {
                        ref.read(activeOfferProvider.notifier).reject();
                        Navigator.pop(context);
                      },
                      child: const Text('Decline'),
                    ),
                    FilledButton(
                      onPressed: () {
                        if (alwaysTrust) {
                          ref.read(trustProvider.notifier).trust(next.senderName);
                        }
                        ref.read(activeOfferProvider.notifier).accept();
                        Navigator.pop(context);
                      },
                      child: const Text('Accept'),
                    ),
                  ],
                );
              }
            );
          },
        );
      }
    });

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: kPaltYellow,
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Icon(Icons.wifi, color: kOnYellow, size: 20),
            ),
            const SizedBox(width: 12),
            const Text('PALT'),
          ],
        ),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const LocalDeviceCard(),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Text(
              'Nearby Devices',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: peersAsync.when(
              data: (peers) {
                if (peers.isEmpty) {
                  return const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.wifi_find, size: 64, color: Colors.grey),
                        SizedBox(height: 16),
                        Text(
                          'Scanning the network...',
                          style: TextStyle(fontSize: 18, color: Colors.grey),
                        ),
                      ],
                    ),
                  );
                }
                return ListView.builder(
                  itemCount: peers.length,
                  itemBuilder: (context, index) {
                    final peer = peers[index];
                    return PeerCard(peer: peer);
                  },
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, trace) => Center(
                child: Text('Error: $e', style: const TextStyle(color: Colors.red)),
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          // Native riverpod refresh logic for streams/singletons
          ref.invalidate(discoveryServiceProvider);
        },
        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
        tooltip: 'Refresh Network',
        child: const Icon(Icons.refresh),
      ),
      bottomNavigationBar: progress != null ? _buildProgress(context, ref, progress) : null,
    );
  }

  Widget _buildProgress(BuildContext context, WidgetRef ref, TransferProgress progress) {
    if (progress.status == TransferStatus.completed) {
      return Container(
        color: Theme.of(context).colorScheme.surfaceContainer,
        padding: const EdgeInsets.only(bottom: 24, left: 16, right: 8, top: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Padding(
              padding: EdgeInsets.only(left: 8.0),
              child: Text(
                'Transfer Complete!',
                style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green),
              ),
            ),
            Row(
              children: [
                if (progress.filePath != null)
                  TextButton(
                    onPressed: () {
                      OpenFilex.open(progress.filePath!);
                      ref.read(transferProgressProvider.notifier).state = null;
                    },
                    child: const Text('Open'),
                  ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => ref.read(transferProgressProvider.notifier).state = null,
                  tooltip: 'Close',
                ),
              ],
            )
          ],
        ),
      );
    }

    final percent = progress.total > 0 ? progress.written / progress.total : 0.0;
    
    return Container(
      color: Theme.of(context).colorScheme.surfaceContainer,
      padding: const EdgeInsets.only(bottom: 24, left: 16, right: 16, top: 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(progress.error != null ? 'Transfer Error' : 'Transferring...', 
                   style: const TextStyle(fontWeight: FontWeight.bold)),
              if (progress.error == null) 
                Text('${(percent * 100).toStringAsFixed(0)}%'),
            ],
          ),
          const SizedBox(height: 8),
          if (progress.error != null)
            Text(progress.error!, style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 12))
          else
            LinearProgressIndicator(value: percent, borderRadius: BorderRadius.circular(4)),
        ],
      ),
    );
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) return "0 B";
    const suffixes = ["B", "KB", "MB", "GB", "TB"];
    var i = (log(bytes) / log(1024)).floor();
    return '${(bytes / pow(1024, i)).toStringAsFixed(2)} ${suffixes[i]}';
  }
}
