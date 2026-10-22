/// restricted_hint.dart — explains how to turn on texts and calls for a
/// computer when Android blocks them.
///
/// Android treats SMS and the call log as "restricted settings" for apps
/// installed outside the Play Store: asking just fails until the user
/// unlocks them in App info → ⋮ → Allow restricted settings.
library;

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../theme/app_theme.dart';

class RestrictedHint extends StatefulWidget {
  final String computer;
  const RestrictedHint({super.key, required this.computer});

  @override
  State<RestrictedHint> createState() => _RestrictedHintState();
}

class _RestrictedHintState extends State<RestrictedHint> with WidgetsBindingObserver {
  bool _missing = false;
  bool _asked = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _check();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Re-check when the user comes back from App info.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _check();
  }

  Future<void> _check() async {
    final ok = await Permission.sms.isGranted && await Permission.phone.isGranted;
    if (mounted) setState(() => _missing = !ok);
  }

  Future<void> _allow() async {
    if (!_asked) {
      final r = await [Permission.sms, Permission.phone, Permission.contacts].request();
      _asked = true;
      if (r.values.every((s) => s.isGranted)) return _check();
    }
    // Asking did nothing: Android blocked it as a restricted setting.
    await openAppSettings();
  }

  @override
  Widget build(BuildContext context) {
    if (!_missing) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(top: 14),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
      decoration: BoxDecoration(
        color: kAccent.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kAccent.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.sms_rounded, color: kAccent, size: 19),
            const SizedBox(width: 8),
            Expanded(
              child: Text('Texts and calls are off',
                  style: TextStyle(color: kText, fontWeight: FontWeight.w600, fontSize: 14)),
            ),
          ]),
          const SizedBox(height: 6),
          Text(
            '${widget.computer} can show your messages and calls once PALT may read them. '
            'If Android won\'t ask: App info → ⋮ (top right) → Allow restricted settings, '
            'then Permissions → SMS and Phone → Allow.',
            style: TextStyle(color: kTextSecondary, fontSize: 12.5, height: 1.45),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(onPressed: _allow, child: Text(_asked ? 'Open App info' : 'Allow')),
          ),
        ],
      ),
    );
  }
}
