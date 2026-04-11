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
        title: Text('Nickname', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(
            hintText: peer.deviceName,
            helperText: 'A recognizable name for this device',
            helperStyle: GoogleFonts.outfit(fontSize: 11),
          ),
          autofocus: true,
          style: GoogleFonts.outfit(),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text('Cancel', style: GoogleFonts.outfit())),
          FilledButton(
            onPressed: () {
              ref.read(aliasProvider.notifier).setAlias(peer.deviceName, controller.text.trim());
              Navigator.pop(context);
            },
            child: Text('Save', style: GoogleFonts.outfit()),
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
        color: Theme.of(context).colorScheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(color: Colors.black.withOpacity(0.04), width: 1),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
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
                      decoration: BoxDecoration(
                        color: osInfo.color.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(18),
                      ),
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
                                  style: GoogleFonts.outfit(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: -0.5,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              IconButton(
                                icon: Icon(Icons.edit_note_rounded, 
                                  size: 22, 
                                  color: Theme.of(context).colorScheme.primary.withOpacity(0.5)
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
                                  color: Colors.grey[600],
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                width: 3,
                                height: 3,
                                decoration: BoxDecoration(
                                  color: Colors.grey.withOpacity(0.4),
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                osInfo.label,
                                style: GoogleFonts.outfit(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.grey[600],
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
                  height: 52,
                  child: FilledButton.tonal(
                    onPressed: () => _handleSend(ref),
                    style: FilledButton.styleFrom(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      backgroundColor: kPaltYellow.withOpacity(0.1),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.ios_share_rounded, size: 18),
                        const SizedBox(width: 10),
                        Text('Send Files', 
                          style: GoogleFonts.outfit(
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.2,
                          )
                        ),
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
