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
    final isCompleted = progress.status == TransferStatus.completed;
    final isError = progress.status == TransferStatus.error;
    final isWaiting = progress.status == TransferStatus.waiting;

    if (isCompleted) {
      return Padding(
        padding: const EdgeInsets.all(16.0),
        child: Card(
          elevation: 4,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.green.withOpacity(0.1), Colors.green.withOpacity(0.05)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.green),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'All files transferred successfully!',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                if (progress.filePath != null)
                  TextButton.icon(
                    onPressed: () {
                      OpenFilex.open(progress.filePath!);
                      ref.read(transferProgressProvider.notifier).state = null;
                    },
                    icon: const Icon(Icons.folder_open, size: 18),
                    label: const Text('View'),
                  ),
                IconButton(
                  icon: const Icon(Icons.close, size: 20),
                  onPressed: () => ref.read(transferProgressProvider.notifier).state = null,
                ),
              ],
            ),
          ),
        ),
      );
    }

    final percent = progress.total > 0 ? progress.written / progress.total : 0.0;
    final speedStr = progress.speed != null ? '${_formatBytes(progress.speed!.toInt())}/s' : '--';
    
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Card(
        elevation: 8,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Stack(
          children: [
            // progress Background Fill
            if (!isError && !isWaiting)
              Positioned.fill(
                child: FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: percent,
                  child: Container(
                    color: kPaltYellow.withOpacity(0.2),
                  ),
                ),
              ),
            
            // Content
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        isError ? Icons.error_outline : (isWaiting ? Icons.hourglass_empty : Icons.sync),
                        size: 20,
                        color: isError ? Colors.red : (isWaiting ? Colors.grey : kPaltYellow),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              isError ? 'Transfer Failed' : (isWaiting ? 'Waiting for Peer...' : progress.currentFileName ?? 'Transferring...'),
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (!isError && !isWaiting)
                              Text(
                                '${progress.sentItems ?? 0} of ${progress.totalItems ?? 0} files • $speedStr',
                                style: const TextStyle(fontSize: 12, color: Colors.grey),
                              ),
                          ],
                        ),
                      ),
                      if (!isError && !isWaiting)
                        Text(
                           '${(percent * 100).toInt()}%',
                           style: TextStyle(
                             fontWeight: FontWeight.w900,
                             color: Theme.of(context).colorScheme.primary,
                             fontSize: 16,
                           ),
                        ),
                    ],
                  ),

                  if (isError) ...[
                    const SizedBox(height: 8),
                    Text(
                      progress.error ?? 'Unknown error',
                      style: TextStyle(color: Colors.red[700], fontSize: 13),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        onPressed: () => ref.read(transferProgressProvider.notifier).state = null,
                        child: const Text('Dismiss'),
                      ),
                    ),
                  ] else if (isWaiting) ...[
                    const SizedBox(height: 12),
                    const LinearProgressIndicator(minHeight: 2),
                  ] else ...[
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '${_formatBytes(progress.written)} of ${_formatBytes(progress.total)}',
                          style: const TextStyle(fontSize: 11, color: Colors.grey),
                        ),
                        // Small accent bar at the very bottom of the card content
                      ],
                    ),
                    const SizedBox(height: 4),
                    LinearProgressIndicator(
                      value: percent,
                      minHeight: 4,
                      borderRadius: BorderRadius.circular(2),
                      backgroundColor: Colors.grey.withOpacity(0.1),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) return "0 B";
    const suffixes = ["B", "KB", "MB", "GB", "TB"];
        var i = (log(bytes) / log(1024)).floor();
    return '${(bytes / pow(1024, i)).toStringAsFixed(1)} ${suffixes[i]}';
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
