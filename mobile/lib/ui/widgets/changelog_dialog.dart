/// changelog_dialog.dart — "What's New" once per version (Beacon).
///
/// Triggered by [HomeScreen] comparing [kAppVersion] against the value
/// stored in SharedPreferences under [kLastSeenVersionKey]. On dismiss the
/// caller persists [kAppVersion] so the dialog doesn't appear again.
library;

import 'package:flutter/material.dart';

import '../../utils/version.dart';
import '../../theme/app_theme.dart';

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
    return Dialog(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("YOU'RE UP TO DATE", style: overline()),
                      const SizedBox(height: 4),
                      Text("What's new", style: display(fontSize: 21)),
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                  decoration: BoxDecoration(
                    color: kAccent.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: kAccent.withValues(alpha: 0.5)),
                  ),
                  child: Text(kAppVersion,
                      style: mono(color: kAccent, fontWeight: FontWeight.w600)),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Flexible(
              child: Container(
                width: double.infinity,
                constraints: const BoxConstraints(maxHeight: 300),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: kBg,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: kHairline),
                ),
                child: SingleChildScrollView(
                  child: Text(
                    releaseNotes.isNotEmpty
                        ? releaseNotes
                        : 'Bug fixes and performance improvements.',
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.7,
                      color: kTextSecondary,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Got it'),
            ),
          ],
        ),
      ),
    );
  }
}
