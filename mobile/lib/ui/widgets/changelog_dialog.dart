/// changelog_dialog.dart
///
/// A "What's New" dialog shown once on the first launch after an upgrade.
/// It is triggered by [HomeScreen] comparing [kAppVersion] against the
/// value stored in [SharedPreferences] under [kLastSeenVersionKey].
///
/// On dismiss, the caller is responsible for persisting [kAppVersion] to
/// SharedPreferences so the dialog doesn't appear again.

import 'package:flutter/material.dart';

import '../../utils/version.dart';

/// Shows the changelog dialog and returns a [Future] that completes when
/// the user dismisses it.
Future<void> showChangelogDialog(
  BuildContext context, {
  required String releaseNotes,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _ChangelogDialog(releaseNotes: releaseNotes),
  );
}

class _ChangelogDialog extends StatelessWidget {
  final String releaseNotes;

  const _ChangelogDialog({required this.releaseNotes});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Gradient header ──────────────────────────────────────────────
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [cs.primary, cs.primary.withOpacity(0.75)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
            child: Row(
              children: [
                Icon(Icons.auto_awesome_rounded, color: cs.onPrimary, size: 26),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          "What's New",
                          style: TextStyle(
                            color: cs.onPrimary,
                            fontWeight: FontWeight.w800,
                            fontSize: 18,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: cs.onPrimary.withOpacity(0.18),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            kAppVersion,
                            style: TextStyle(
                              color: cs.onPrimary,
                              fontWeight: FontWeight.w700,
                              fontSize: 11,
                            ),
                          ),
                        ),
                      ],
                    ),
                    Text(
                      "You're on the latest version of PALT",
                      style: TextStyle(
                        color: cs.onPrimary.withOpacity(0.75),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // ── Release notes ────────────────────────────────────────────────
          Flexible(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 320),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Text(
                  releaseNotes.isNotEmpty
                      ? releaseNotes
                      : 'Bug fixes and performance improvements.',
                  style: const TextStyle(fontSize: 13, height: 1.7),
                ),
              ),
            ),
          ),

          // ── Dismiss button ───────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              style: FilledButton.styleFrom(
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24)),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: const Text(
                'Got it!',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
