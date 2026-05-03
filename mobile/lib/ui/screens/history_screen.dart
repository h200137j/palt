import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/history_provider.dart';

import '../../utils/version.dart';
import '../../theme/app_theme.dart';
import 'package:google_fonts/google_fonts.dart';

class HistoryScreen extends ConsumerWidget {
  const HistoryScreen({super.key});

  String _formatSize(int bytes) {
    if (bytes == 0) return '0 B';
    const suffixes = ['B', 'KB', 'MB', 'GB', 'TB'];
    var i = 0;
    double size = bytes.toDouble();
    while (size >= 1024 && i < suffixes.length - 1) {
      size /= 1024;
      i++;
    }
    return '${size.toStringAsFixed(1)} ${suffixes[i]}';
  }

  String _formatDuration(int ms) {
    if (ms < 1000) return '${ms}ms';
    return '${(ms / 1000).toStringAsFixed(1)}s';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(historyProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text('History',
          style: GoogleFonts.archivo(fontWeight: FontWeight.w900)
        ),
        actions: [
          if (history.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_outline_rounded),
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Clear History'),
                    content: const Text('Are you sure you want to wipe the transfer log?'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
                      TextButton(
                        onPressed: () {
                          ref.read(historyProvider.notifier).clearHistory();
                          Navigator.pop(ctx);
                        },
                        child: const Text('Clear'),
                      ),
                    ],
                  ),
                );
              },
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: history.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.history_toggle_off_rounded, size: 80, color: kSecondary.withValues(alpha: 0.3)),
                        const SizedBox(height: 16),
                        Text('No transfer history found', style: TextStyle(fontSize: 14, color: kSecondary.withValues(alpha: 0.6))),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    itemCount: history.length,
                    itemBuilder: (context, index) {
                      final entry = history[index];
                      final isIncoming = entry.direction == 'incoming';
                      final isSuccess = entry.status == 'completed';

                      return Container(
                        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                        decoration: BoxDecoration(
                          color: kSurface,
                          borderRadius: const BorderRadius.all(Radius.circular(2)),
                          border: Border.all(color: kSecondary.withValues(alpha: 0.3)),
                        ),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          leading: Container(
                            width: 48,
                            height: 48,
                            color: isIncoming
                                ? kSecondary.withValues(alpha: 0.1)
                                : kTertiary.withValues(alpha: 0.2),
                            child: Icon(
                              isIncoming ? Icons.south_west_rounded : Icons.north_east_rounded,
                              color: isIncoming ? kSecondary : kPrimary,
                              size: 20,
                            ),
                          ),
                          title: Text(
                            entry.files.length == 1 ? entry.files[0].name : '${entry.files.length} items',
                            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                          ),
                          subtitle: Padding(
                            padding: const EdgeInsets.only(top: 4.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${isIncoming ? 'From' : 'To'}: ${entry.partnerName} • ${_formatSize(entry.totalSize)}',
                                  style: const TextStyle(fontSize: 12, color: kSecondary),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '${entry.timestamp.toLocal().toString().split('.')[0]} • ${_formatDuration(entry.durationMillis)}',
                                  style: TextStyle(fontSize: 11, color: kSecondary.withValues(alpha: 0.6)),
                                ),
                              ],
                            ),
                          ),
                          trailing: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            color: isSuccess
                                ? Colors.green.withValues(alpha: 0.1)
                                : Colors.red.withValues(alpha: 0.1),
                            child: Text(
                              isSuccess ? 'SUCCESS' : 'FAILED',
                              style: TextStyle(
                                color: isSuccess ? Colors.green : Colors.red,
                                fontSize: 9,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                          onTap: !isSuccess && entry.errorMessage != null
                              ? () {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text('Error: ${entry.errorMessage}'),
                                      behavior: SnackBarBehavior.floating,
                                      shape: const RoundedRectangleBorder(
                                        borderRadius: BorderRadius.all(Radius.circular(2)),
                                      ),
                                    ),
                                  );
                                }
                              : null,
                        ),
                      );
                    },
                  ),
          ),
          _buildFooter(context),
        ],
      ),
    );
  }

  Widget _buildFooter(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.only(bottom: 24, top: 8),
      child: Text(
        'made with ❤️ by uriel • $kAppVersion',
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
          color: kSecondary.withValues(alpha: 0.4),
        ),
      ),
    );
  }
}
