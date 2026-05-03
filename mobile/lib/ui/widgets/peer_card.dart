import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart' as fp;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:io';

import '../../models/peer.dart';
import '../../utils/os_icons.dart';
import '../../services/transfer_service.dart';
import '../../theme/app_theme.dart';
import 'package:google_fonts/google_fonts.dart';

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
        title: Text('Nickname', style: GoogleFonts.archivo(fontWeight: FontWeight.bold)),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(
            hintText: peer.deviceName,
            helperText: 'A recognizable name for this device',
            helperStyle: GoogleFonts.archivo(fontSize: 11),
          ),
          autofocus: true,
          style: GoogleFonts.archivo(),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
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

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Card(
        elevation: 0,
        color: kSurface,
        shape: RoundedRectangleBorder(
          borderRadius: const BorderRadius.all(Radius.circular(2)),
          side: BorderSide(color: kSecondary.withValues(alpha: 0.3)),
        ),
        child: InkWell(
          borderRadius: const BorderRadius.all(Radius.circular(2)),
          onTap: () => _handleSend(ref),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                Row(
                  children: [
                    Container(
                      width: 56,
                      height: 56,
                      color: kNeutral,
                      child: Icon(osInfo.icon, color: kSecondary, size: 28),
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
                                  style: GoogleFonts.archivo(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w700,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              IconButton(
                                icon: Icon(Icons.edit_note_rounded,
                                  size: 22,
                                  color: kSecondary,
                                ),
                                onPressed: () => _showRenameDialog(context, ref, alias ?? ''),
                                visualDensity: VisualDensity.compact,
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              Text(
                                peer.ipAddress,
                                style: GoogleFonts.ubuntuMono(
                                  fontSize: 12,
                                  color: kSecondary,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                width: 3,
                                height: 3,
                                color: kSecondary,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                osInfo.label,
                                style: GoogleFonts.archivo(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: kSecondary,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: FilledButton(
                    onPressed: () => _handleSend(ref),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.ios_share_rounded, size: 18),
                        SizedBox(width: 10),
                        Text('Send Files'),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _handleSend(WidgetRef ref) async {
    if (onSendFile != null) {
      onSendFile!();
      return;
    }

    try {
      fp.FilePickerResult? result = await fp.FilePicker.pickFiles(allowMultiple: true);
      if (result != null && result.files.isNotEmpty) {
        List<File> files = result.paths.where((path) => path != null).map((path) => File(path!)).toList();
        if (files.isNotEmpty) {
          await ref.read(transferServiceProvider).sendFiles(peer, files);
        }
      }
    } catch (e) {
      // Handled by service
    }
  }
}
