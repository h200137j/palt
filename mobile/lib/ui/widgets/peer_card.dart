import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:io';

import '../../models/peer.dart';
import '../../utils/os_icons.dart';
import '../../services/transfer_service.dart';

import '../../providers/alias_provider.dart';

class PeerCard extends ConsumerWidget {
  final Peer peer;
  final VoidCallback? onSendFile;

  const PeerCard({super.key, required this.peer, this.onSendFile});

  void _showRenameDialog(BuildContext context, WidgetRef ref, String currentAlias) {
    final controller = TextEditingController(text: currentAlias);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Set Nickname'),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(
            hintText: peer.deviceName,
            helperText: 'Enter a recognizable name for this device',
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              ref.read(aliasProvider.notifier).setAlias(peer.deviceName, controller.text.trim());
              Navigator.pop(context);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final osInfo = getOsInfo(peer.os);
    final aliases = ref.watch(aliasProvider);
    final alias = aliases[peer.deviceName];
    final hasAlias = alias != null && alias.isNotEmpty;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundColor: osInfo.color.withOpacity(0.12),
                  child: Icon(osInfo.icon, color: osInfo.color, size: 28),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              hasAlias ? alias : peer.deviceName,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.edit, size: 18),
                            onPressed: () => _showRenameDialog(context, ref, alias ?? ''),
                            visualDensity: VisualDensity.compact,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            tooltip: 'Rename device',
                          ),
                        ],
                      ),
                      if (hasAlias)
                        Text(
                          'Hostname: ${peer.deviceName}',
                          style: TextStyle(
                            fontSize: 11,
                            color: Theme.of(context).textTheme.bodySmall?.color,
                          ),
                        ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Text(
                            '${peer.ipAddress}:${peer.port}',
                            style: TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 12,
                              color: Theme.of(context).textTheme.bodySmall?.color,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: osInfo.color.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Row(
                              children: [
                                Icon(osInfo.icon, size: 10, color: osInfo.color),
                                const SizedBox(width: 4),
                                Text(
                                  osInfo.label,
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                    color: osInfo.color,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(height: 1),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () async {
                  if (onSendFile != null) {
                    onSendFile!();
                    return;
                  }

                    try {
                    FilePickerResult? result = await FilePicker.pickFiles(allowMultiple: true);
                    if (result != null && result.files.isNotEmpty) {
                      List<File> files = result.paths.where((path) => path != null).map((path) => File(path!)).toList();
                      if (files.isNotEmpty) {
                        await ref.read(transferServiceProvider).sendFiles(peer, files);
                      }
                    }
                  } catch (e) {
                    // Silently ignore as the TransferService handles notifying via progress overlay
                  }
                },
                icon: const Icon(Icons.send, size: 16),
                label: const Text('Send Files'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
