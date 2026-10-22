/// background_banner.dart — asks once for unrestricted battery use.
///
/// Without it Android (and Samsung's One UI especially) puts PALT to sleep
/// and paired devices lose the connection while the phone is idle.
library;

import 'package:flutter/material.dart';

import '../../services/background.dart';
import '../../theme/app_theme.dart';

class BackgroundBanner extends StatefulWidget {
  const BackgroundBanner({super.key});

  @override
  State<BackgroundBanner> createState() => _BackgroundBannerState();
}

class _BackgroundBannerState extends State<BackgroundBanner> with WidgetsBindingObserver {
  bool _restricted = false;

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

  // Re-check when the user comes back from the system prompt.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _check();
  }

  Future<void> _check() async {
    final ok = await Background.isIgnoringBatteryOptimizations();
    if (mounted) setState(() => _restricted = !ok);
  }

  @override
  Widget build(BuildContext context) {
    if (!_restricted) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
      decoration: BoxDecoration(
        color: kAccent.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: kAccent.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.battery_alert_rounded, color: kAccent, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text('Stay connected in the background',
                    style: TextStyle(color: kText, fontWeight: FontWeight.w600, fontSize: 14.5)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Allow PALT to run unrestricted so your computer can reach this phone while '
            'it\'s in your pocket. On Samsung also add PALT to Settings → Battery → '
            'Background usage limits → Never sleeping apps.',
            style: TextStyle(color: kTextSecondary, fontSize: 12.5, height: 1.45),
          ),
          const Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: Background.requestIgnoreBatteryOptimizations,
              child: Text('Allow'),
            ),
          ),
        ],
      ),
    );
  }
}
