/// history_screen.dart — transfer log (Beacon).
///
/// Entries grouped by day. Direction encoded consistently with the rest of
/// the app: outgoing ↑ amber, incoming ↓ green. Wire-derived values in mono.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/history_entry.dart';
import '../../providers/history_provider.dart';

import '../../utils/version.dart';
import '../../theme/app_theme.dart';
import '../widgets/palt_page.dart';

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

  String _formatTime(DateTime t) {
    final local = t.toLocal();
    final h = local.hour.toString().padLeft(2, '0');
    final m = local.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  /// "Today" / "Yesterday" / "Mon, 14 Jul"
  String _dayLabel(DateTime t) {
    final d = t.toLocal();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(d.year, d.month, d.day);
    final diff = today.difference(day).inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${weekdays[d.weekday - 1]}, ${d.day} ${months[d.month - 1]}';
  }

  void _confirmClear(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Clear history?', style: display(fontSize: 19)),
        content: Text(
          'The whole transfer log is removed. Files already on this phone stay where they are.',
          style: TextStyle(color: kTextSecondary, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: kDanger,
              foregroundColor: kBg,
            ),
            onPressed: () {
              ref.read(historyProvider.notifier).clearHistory();
              Navigator.pop(ctx);
            },
            child: const Text('Clear'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(historyProvider);

    // Group by day, preserving order.
    final groups = <String, List<dynamic>>{};
    for (final entry in history) {
      groups.putIfAbsent(_dayLabel(entry.timestamp), () => []).add(entry);
    }

    final clear = history.isEmpty
        ? null
        : (isPop
            ? PopIconButton(icon: Icons.delete_outline_rounded, color: popColor(1, kSurface), onTap: () => _confirmClear(context, ref))
            : IconButton(
                icon: Icon(Icons.delete_outline_rounded, color: isMaterial ? null : kTextSecondary),
                tooltip: 'Clear history',
                onPressed: () => _confirmClear(context, ref),
              ));

    return PaltPage(
      title: 'History',
      kicker: '${history.length} transfer${history.length == 1 ? '' : 's'} on record',
      actions: [if (clear != null) clear, const SizedBox(width: 8)],
      slivers: [
        if (history.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.history_rounded, size: 56, color: kTextFaint),
                  const SizedBox(height: 16),
                  Text('No transfers yet', style: display(fontSize: 19)),
                  const SizedBox(height: 6),
                  Text(
                    'Every file and message you send or receive is logged here.',
                    style: TextStyle(fontSize: 13, color: kTextSecondary),
                  ),
                ],
              ),
            ),
          )
        else
          for (final group in groups.entries)
            SliverToBoxAdapter(
              child: PaltSection(title: group.key, children: [
                for (final entry in group.value)
                  _HistoryTile(
                    entry: entry,
                    formatSize: _formatSize,
                    formatDuration: _formatDuration,
                    formatTime: _formatTime,
                  ),
              ]),
            ),
        SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.only(top: 24), child: _buildFooter(context))),
      ],
    );
  }

  Widget _buildFooter(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.only(bottom: 24, top: 8),
      child: Text(
        'made with ❤️ by uriel • $kAppVersion',
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 10, color: kTextFaint),
      ),
    );
  }
}

class _HistoryTile extends StatelessWidget {
  final HistoryEntry entry;
  final String Function(int) formatSize;
  final String Function(int) formatDuration;
  final String Function(DateTime) formatTime;

  const _HistoryTile({
    required this.entry,
    required this.formatSize,
    required this.formatDuration,
    required this.formatTime,
  });

  @override
  Widget build(BuildContext context) {
    final isIncoming = entry.direction == 'incoming';
    final failed = entry.status != 'completed';
    final dirColor = failed ? kDanger : (isIncoming ? kOk : kAccent);

    return GestureDetector(
      onTap: failed && entry.errorMessage != null
          ? () => ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(entry.errorMessage!)),
              )
          : null,
      child: Container(
      padding: EdgeInsets.symmetric(horizontal: isPaper ? 4 : 16, vertical: 12),
      color: Colors.transparent,
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: isPop
                ? paltDeco(radius: 8, color: failed ? kDanger : popColor(isIncoming ? 2 : 0, kAccent), flat: true)
                : BoxDecoration(
                    color: dirColor.withValues(alpha: isPaper ? 0 : 0.1),
                    shape: BoxShape.circle,
                    border: isPaper ? Border.all(color: dirColor) : null,
                  ),
            child: Icon(
              failed
                  ? Icons.error_outline_rounded
                  : entry.isText
                  ? Icons.chat_bubble_outline_rounded
                  : (isIncoming
                      ? Icons.south_west_rounded
                      : Icons.north_east_rounded),
              color: isPop && !failed ? kText : dirColor,
              size: 17,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.isText
                      ? entry.text ?? ''
                      : entry.files.length == 1
                      ? entry.files[0].name
                      : '${entry.files.length} files',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: kText,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text.rich(
                  TextSpan(
                    style: TextStyle(fontSize: 12, color: kTextSecondary),
                    children: [
                      TextSpan(text: isIncoming ? 'from ' : 'to '),
                      TextSpan(
                        text: entry.partnerName,
                        style: TextStyle(
                          color: kText,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      if (failed)
                        TextSpan(
                          text: ' — failed',
                          style: TextStyle(color: kDanger),
                        ),
                    ],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(entry.isText ? 'message' : formatSize(entry.totalSize),
                  style: mono(color: kText, fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              Text(
                entry.isText
                    ? formatTime(entry.timestamp)
                    : '${formatDuration(entry.durationMillis)} · ${formatTime(entry.timestamp)}',
                style: mono(fontSize: 10.5, color: kTextFaint),
              ),
            ],
          ),
        ],
      ),
      ),
    );
  }
}
