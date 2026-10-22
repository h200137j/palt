/// settings_screen.dart — what this phone shares with paired computers.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/clipboard.dart';
import '../../features/notification_sync.dart';
import '../../theme/app_theme.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> with WidgetsBindingObserver {
  bool _access = true;
  bool _autoLogs = false;
  bool _autoOnTop = false;

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

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _check();
  }

  Future<void> _check() async {
    final ok = await hasNotificationAccess();
    var logs = false, onTop = false;
    try {
      final r = await const MethodChannel('palt/clipboard').invokeMethod<Map>('autoAvailable');
      logs = r?['logs'] == true;
      onTop = r?['onTop'] == true;
    } catch (_) {}
    if (mounted) {
      setState(() {
        _access = ok;
        _autoLogs = logs;
        _autoOnTop = onTop;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final sync = ref.watch(notificationSyncProvider);
    final clip = ref.watch(clipboardSettingsProvider);
    final notifier = ref.read(notificationSyncProvider.notifier);
    final apps = sync.apps.entries.toList()
      ..sort((a, b) => a.value.toLowerCase().compareTo(b.value.toLowerCase()));

    return Scaffold(
      appBar: AppBar(title: Text('Settings', style: display(fontSize: 19))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          Text('USB CABLE', style: overline()),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.usb_rounded, color: kTextSecondary),
            title: Text('Connect by USB', style: TextStyle(color: kText)),
            subtitle: Text(
                'No Wi-Fi? Plug in the cable and turn on USB tethering. PALT works over the '
                'cable, even without mobile data.',
                style: TextStyle(color: kTextSecondary, fontSize: 12.5)),
            trailing: Icon(Icons.open_in_new_rounded, size: 18, color: kTextFaint),
            onTap: () => const MethodChannel('palt/device').invokeMethod('openTetherSettings'),
          ),
          const SizedBox(height: 16),
          Text('CLIPBOARD', style: overline()),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('Take the computer\'s clipboard', style: TextStyle(color: kText)),
            subtitle: Text('Copy on the computer, paste here',
                style: TextStyle(color: kTextSecondary, fontSize: 12.5)),
            value: clip.receive,
            onChanged: ref.read(clipboardSettingsProvider.notifier).setReceive,
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('Send this phone\'s clipboard', style: TextStyle(color: kText)),
            subtitle: Text(
                _autoLogs && _autoOnTop
                    ? 'Automatically, whenever you copy something'
                    : _autoLogs
                        ? 'Almost automatic: allow "Appear on top" below to finish'
                        : 'When you open PALT, from the "Send clipboard" button on its notification, '
                            'or the Quick Settings tile. For automatic: connect by USB and run '
                            'adb shell pm grant com.h200137j.palt.palt_mobile android.permission.READ_LOGS',
                style: TextStyle(color: kTextSecondary, fontSize: 12.5)),
            value: clip.send,
            onChanged: ref.read(clipboardSettingsProvider.notifier).setSend,
          ),
          if (_autoLogs && !_autoOnTop)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.layers_rounded, color: kRelay),
              title: Text('Allow "Appear on top"', style: TextStyle(color: kText)),
              subtitle: Text('Lets PALT read a copy the moment you make it',
                  style: TextStyle(color: kTextSecondary, fontSize: 12.5)),
              trailing: Icon(Icons.open_in_new_rounded, size: 18, color: kTextFaint),
              onTap: () => const MethodChannel('palt/clipboard').invokeMethod('openAppearOnTop'),
            ),
          const SizedBox(height: 18),
          Text('NOTIFICATIONS ON YOUR COMPUTER', style: overline()),
          const SizedBox(height: 8),
          if (!_access)
            Container(
              padding: const EdgeInsets.fromLTRB(14, 12, 8, 6),
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(
                color: kAccent.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: kAccent.withValues(alpha: 0.35)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'PALT needs notification access to show this phone\'s notifications on your '
                    'computer, and to dismiss, act on and reply to them from there.',
                    style: TextStyle(color: kTextSecondary, fontSize: 13, height: 1.45),
                  ),
                  const Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: openNotificationAccessSettings,
                      child: Text('Grant access'),
                    ),
                  ),
                ],
              ),
            ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('Send notifications', style: TextStyle(color: kText)),
            subtitle: Text('Show them on paired computers',
                style: TextStyle(color: kTextSecondary, fontSize: 12.5)),
            value: sync.enabled,
            onChanged: notifier.setEnabled,
          ),
          if (sync.enabled && apps.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text('APPS', style: overline()),
            const SizedBox(height: 4),
            Text('Apps show up here after their first notification.',
                style: TextStyle(color: kTextFaint, fontSize: 12)),
            for (final a in apps)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: Text(a.value, style: TextStyle(color: kText, fontSize: 14)),
                value: !sync.muted.contains(a.key),
                onChanged: (on) => notifier.setMuted(a.key, !on),
              ),
          ],
        ],
      ),
    );
  }
}
