import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_filex/open_filex.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'dart:math';

import '../../providers/peer_provider.dart';
import '../../providers/trust_provider.dart';
import '../../providers/update_provider.dart';
import '../../services/transfer_service.dart';
import '../../utils/version.dart';
import '../widgets/changelog_dialog.dart';
import '../widgets/local_device_card.dart';
import '../widgets/peer_card.dart';
import '../widgets/update_banner.dart';
import '../../theme/app_theme.dart';
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
    // Trigger changelog check after first frame so context is available.
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeShowChangelog());
  }

  Future<void> _maybeShowChangelog() async {
    if (_changelogShown) return;
    final prefs = await SharedPreferences.getInstance();
    final lastSeen = prefs.getString(kLastSeenVersionKey) ?? '';
    if (lastSeen != kAppVersion && mounted) {
      _changelogShown = true;
      // Fetch release notes from the update provider if already resolved.
      final updateAsync = ref.read(updateProvider);
      final notes = updateAsync.valueOrNull?.releaseNotes ?? '';
      await showChangelogDialog(context, releaseNotes: notes);
      await prefs.setString(kLastSeenVersionKey, kAppVersion);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Start Transfer Service
    ref.watch(transferServiceProvider);

    final peersAsync = ref.watch(peerListProvider);
    
    // Watch Progress
    final progress = ref.watch(transferProgressProvider);

    // Watch update state (runs once per session, cached by Riverpod)
    final updateAsync = ref.watch(updateProvider);
    final updateInfo = updateAsync.valueOrNull;

    // Listen to Incoming Offers
    ref.listen<OfferData?>(activeOfferProvider, (previous, next) {
      if (next != null) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) {
            bool alwaysTrust = false;
            bool showDetails = false;

            return StatefulBuilder(
              builder: (context, setState) {
                final isMultiple = next.files.length > 1;
                final fileCount = next.files.length;
                final sizeStr = _formatBytes(next.totalSize);
                
                return AlertDialog(
                  title: Text('Incoming ${isMultiple ? 'Files' : 'File'}', style: const TextStyle(fontWeight: FontWeight.bold)),
                  content: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${next.senderName} wants to send you ${isMultiple ? '$fileCount files' : 'a file'}:'),
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
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Text(
                                      isMultiple ? '$fileCount items' : next.files[0].name, 
                                      style: const TextStyle(fontWeight: FontWeight.w600),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  if (isMultiple)
                                    TextButton(
                                      onPressed: () => setState(() => showDetails = !showDetails),
                                      style: TextButton.styleFrom(
                                        padding: EdgeInsets.zero,
                                        minimumSize: const Size(50, 20),
                                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                      ),
                                      child: Text(showDetails ? 'Hide' : 'Details', style: const TextStyle(fontSize: 12)),
                                    ),
                                ],
                              ),
                              Text(sizeStr, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12)),
                              
                              if (isMultiple && showDetails) ...[
                                const Divider(height: 16),
                                ConstrainedBox(
                                  constraints: const BoxConstraints(maxHeight: 180),
                                  child: ListView.separated(
                                    shrinkWrap: true,
                                    itemCount: next.files.length,
                                    separatorBuilder: (context, index) => const SizedBox(height: 4),
                                    itemBuilder: (context, index) {
                                      final file = next.files[index];
                                      return Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Expanded(
                                            child: Text(
                                              file.name,
                                              style: const TextStyle(fontSize: 11),
                                              overflow: TextOverflow.ellipsis,
                                              maxLines: 1,
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Text(
                                            _formatBytes(file.size),
                                            style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 10),
                                          ),
                                        ],
                                      );
                                    },
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
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
        actions: [
          IconButton(
            icon: const Icon(Icons.history),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const HistoryScreen()),
            ),
            tooltip: 'Transfer History',
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const LocalDeviceCard(),

          // ── Update banner (shown only when a newer version exists) ─────
          if (updateInfo != null && updateInfo.isNewer)
            UpdateBanner(info: updateInfo),

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
          _buildFooter(context),
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
    
    bool isWaiting = progress.status == TransferStatus.waiting;
    String statusStr = progress.error != null ? 'Transfer Error' : (isWaiting ? 'Waiting for peer...' : 'Transferring...');
    
    if (progress.error == null && !isWaiting && progress.totalItems != null && progress.totalItems! > 1) {
        statusStr = '[${progress.sentItems}/${progress.totalItems} files] Transferring...';
    }
    
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
              Text(statusStr, style: const TextStyle(fontWeight: FontWeight.bold)),
              if (progress.error == null && !isWaiting) 
                Text('${_formatBytes(progress.written)} / ${_formatBytes(progress.total)}'),
            ],
          ),
          const SizedBox(height: 8),
          if (progress.error != null)
            Text(progress.error!, style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 12))
          else if (isWaiting)
            const LinearProgressIndicator(borderRadius: BorderRadius.all(Radius.circular(4)))
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

  Widget _buildFooter(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(
        'made with ❤️ by uriel • $kAppVersion',
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 11,
          color: Colors.grey.withOpacity(0.8),
        ),
      ),
    );
  }
}
