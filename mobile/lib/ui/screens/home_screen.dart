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
import '../../providers/update_visibility_provider.dart';
import '../../models/peer.dart';
import '../../theme/app_theme.dart';
import 'package:google_fonts/google_fonts.dart';
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
      body: Stack(
        children: [
          _buildBody(context, ref, peersAsync, updateInfo, progress),
          if (progress != null)
            Positioned(
              left: 16,
              right: 16,
              bottom: 16,
              child: _buildProgress(context, ref, progress),
            ),
        ],
      ),
      floatingActionButton: progress == null ? FloatingActionButton.extended(
        onPressed: () => ref.invalidate(discoveryServiceProvider),
        icon: const Icon(Icons.refresh_rounded),
        label: const Text('Scan'),
      ) : null,
    );

  }

  Widget _buildBody(BuildContext context, WidgetRef ref, AsyncValue<List<Peer>> peersAsync, dynamic updateInfo, TransferProgress? progress) {
    final bannerVisible = ref.watch(updateBannerVisibleProvider);

    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: [
          SliverAppBar(
            expandedHeight: 140.0,
            floating: false,
            pinned: true,
            flexibleSpace: FlexibleSpaceBar(
              title: Text('PALT', 
                style: GoogleFonts.outfit(
                  fontWeight: FontWeight.w900,
                  letterSpacing: -1.2,
                  color: Theme.of(context).colorScheme.onSurface,
                )
              ),
              centerTitle: false,
              titlePadding: const EdgeInsetsDirectional.only(start: 20, bottom: 16),
              background: Container(
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  gradient: RadialGradient(
                    center: Alignment.topRight,
                    radius: 1.5,
                    colors: [
                      kPaltYellow.withOpacity(0.05),
                      Theme.of(context).colorScheme.surface,
                    ],
                  ),
                ),
              ),
            ),
            actions: [
              if (updateInfo?.isNewer == true && !bannerVisible)
                IconButton(
                  icon: Icon(Icons.new_releases, color: kGoogleBlue),
                  onPressed: () => ref.read(updateBannerVisibleProvider.notifier).state = true,
                ),
              IconButton(
                icon: const Icon(Icons.history_rounded),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const HistoryScreen()),
                ),
              ),
              const SizedBox(width: 8),
            ],
          ),

          if (bannerVisible && updateInfo != null)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.only(top: 8),
                child: UpdateBanner(info: updateInfo),
              ),
            ),

          const SliverToBoxAdapter(
            child: LocalDeviceCard(),
          ),

          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(left: 20, top: 32, bottom: 12),
              child: Row(
                children: [
                  const Text(
                    'NEARBY DEVICES',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.2,
                      color: Colors.grey,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    width: 4,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.withOpacity(0.3),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  peersAsync.when(
                    data: (peers) => Text(
                      '${peers.length} FOUND',
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                        color: Colors.grey,
                      ),
                    ),
                    error: (_, __) => const Text('OFFLINE'),
                    loading: () => const SizedBox(width: 8, height: 8, child: CircularProgressIndicator(strokeWidth: 2)),
                  ),
                ],
              ),
            ),
          ),

          peersAsync.when(
            data: (peers) => peers.isEmpty
                ? const SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.radar, size: 48, color: Colors.grey),
                          SizedBox(height: 16),
                          Text('Discovery active...', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.w600)),
                          SizedBox(height: 4),
                          Text('Wait for a device to appear', style: TextStyle(color: Colors.grey, fontSize: 12)),
                        ],
                      ),
                    ),
                  )
                : SliverPadding(
                    padding: const EdgeInsets.only(bottom: 20),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) => PeerCard(peer: peers[index]),
                        childCount: peers.length,
                      ),
                    ),
                  ),
            error: (err, _) => SliverFillRemaining(
              hasScrollBody: false,
              child: Center(child: Text('Error: $err')),
            ),
            loading: () => const SliverFillRemaining(
              hasScrollBody: false,
              child: Center(child: CircularProgressIndicator()),
            ),
          ),

          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(top: 40, bottom: 120),
              child: _buildFooter(context),
            ),
          ),
        ],
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
    
    return Container(
      decoration: BoxDecoration(
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Card(
        elevation: 0,
        clipBehavior: Clip.antiAlias,
        color: Colors.white.withOpacity(0.85),
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(color: Colors.white.withOpacity(0.5), width: 1.5),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: BackdropFilter(
            filter: ColorFilter.mode(Colors.white.withOpacity(0.2), BlendMode.overlay),
            child: Stack(
              children: [
                // progress Background Fill
                if (!isError && !isWaiting)
                  Positioned.fill(
                    child: FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: percent,
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              kPaltYellow.withOpacity(0.15),
                              kPaltYellow.withOpacity(0.05),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                
                // Content
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: isError ? Colors.red.withOpacity(0.1) : (isWaiting ? Colors.grey.withOpacity(0.1) : kPaltYellow.withOpacity(0.1)),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              isError ? Icons.error_outline_rounded : (isWaiting ? Icons.hourglass_empty_rounded : Icons.sync_rounded),
                              size: 20,
                              color: isError ? Colors.red : (isWaiting ? Colors.grey : kPaltYellow),
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  isError ? 'Transfer Failed' : (isWaiting ? 'Waiting for Peer...' : progress.currentFileName ?? 'Transferring...'),
                                  style: GoogleFonts.outfit(fontWeight: FontWeight.w700, fontSize: 16),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                if (!isError && !isWaiting)
                                  Text(
                                    '${progress.sentItems ?? 0} of ${progress.totalItems ?? 0} files • $speedStr',
                                    style: TextStyle(fontSize: 12, color: Colors.grey[600], fontWeight: FontWeight.w500),
                                  ),
                              ],
                            ),
                          ),
                          if (!isError && !isWaiting)
                            Text(
                               '${(percent * 100).toInt()}%',
                               style: GoogleFonts.outfit(
                                 fontWeight: FontWeight.w900,
                                 color: Theme.of(context).colorScheme.primary,
                                 fontSize: 18,
                               ),
                            ),
                        ],
                      ),
    
                      if (isError) ...[
                        const SizedBox(height: 12),
                        Text(
                          progress.error ?? 'Unknown error',
                          style: TextStyle(color: Colors.red[700], fontSize: 13, fontWeight: FontWeight.w500),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.tonal(
                            onPressed: () => ref.read(transferProgressProvider.notifier).state = null,
                            child: const Text('Dismiss'),
                          ),
                        ),
                      ] else if (isWaiting) ...[
                        const SizedBox(height: 16),
                        LinearProgressIndicator(
                          minHeight: 2,
                          backgroundColor: Colors.grey.withOpacity(0.1),
                          color: kPaltYellow.withOpacity(0.5),
                        ),
                      ] else ...[
                        const SizedBox(height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              '${_formatBytes(progress.written)} of ${_formatBytes(progress.total)}',
                              style: TextStyle(fontSize: 11, color: Colors.grey[600], fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: LinearProgressIndicator(
                            value: percent,
                            minHeight: 6,
                            backgroundColor: Colors.black.withOpacity(0.05),
                            valueColor: AlwaysStoppedAnimation<Color>(kPaltYellow),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
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
