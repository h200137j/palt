/// settings_screen.dart — what this phone shares with paired computers.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/clipboard.dart';
import '../../features/notification_sync.dart';
import '../../theme/app_theme.dart';
import '../widgets/palt_page.dart';
import '../widgets/theme_preview.dart';

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

    return PaltPage(
      title: 'Settings',
      kicker: 'Make PALT yours',
      slivers: [
        const SliverToBoxAdapter(child: _Appearance()),
        SliverToBoxAdapter(
          child: PaltSection(title: 'USB cable', children: [
            PaltTile(
              icon: Icons.usb_rounded,
              title: 'Connect by USB',
              subtitle: 'No Wi-Fi? Plug in the cable and turn on USB tethering. PALT works over the '
                  'cable, even without mobile data.',
              trailing: Icon(Icons.open_in_new_rounded, size: 18, color: kTextFaint),
              onTap: () => const MethodChannel('palt/device').invokeMethod('openTetherSettings'),
            ),
          ]),
        ),
        SliverToBoxAdapter(
          child: PaltSection(title: 'Clipboard', children: [
            PaltTile(
              icon: Icons.content_paste_rounded,
              title: 'Take the computer\'s clipboard',
              subtitle: 'Copy on the computer, paste here',
              value: clip.receive,
              onChanged: ref.read(clipboardSettingsProvider.notifier).setReceive,
            ),
            PaltTile(
              icon: Icons.content_paste_go_rounded,
              title: 'Send this phone\'s clipboard',
              subtitle: _autoLogs && _autoOnTop
                  ? 'Automatically, whenever you copy something'
                  : _autoLogs
                      ? 'Almost automatic: allow "Appear on top" below to finish'
                      : 'When you open PALT, from the "Send clipboard" button on its notification, '
                          'or the Quick Settings tile. For automatic: connect by USB and run '
                          'adb shell pm grant com.h200137j.palt.palt_mobile android.permission.READ_LOGS',
              value: clip.send,
              onChanged: ref.read(clipboardSettingsProvider.notifier).setSend,
            ),
            if (_autoLogs && !_autoOnTop)
              PaltTile(
                icon: Icons.layers_rounded,
                iconColor: kRelay,
                title: 'Allow "Appear on top"',
                subtitle: 'Lets PALT read a copy the moment you make it',
                trailing: Icon(Icons.open_in_new_rounded, size: 18, color: kTextFaint),
                onTap: () => const MethodChannel('palt/clipboard').invokeMethod('openAppearOnTop'),
              ),
          ]),
        ),
        SliverToBoxAdapter(
          child: PaltSection(title: 'Notifications on your computer', children: [
            if (!_access)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 8, 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'PALT needs notification access to show this phone\'s notifications on your '
                      'computer, and to dismiss, act on and reply to them from there.',
                      style: TextStyle(color: kTextSecondary, fontSize: 13, height: 1.45),
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: openNotificationAccessSettings,
                        child: const Text('Grant access'),
                      ),
                    ),
                  ],
                ),
              ),
            PaltTile(
              icon: Icons.notifications_rounded,
              title: 'Send notifications',
              subtitle: 'Show them on paired computers',
              value: sync.enabled,
              onChanged: notifier.setEnabled,
            ),
          ]),
        ),
        if (sync.enabled && apps.isNotEmpty)
          SliverToBoxAdapter(
            child: PaltSection(
              title: 'Apps',
              note: 'Apps show up here after their first notification.',
              children: [
                for (final a in apps)
                  PaltTile(
                    dense: true,
                    title: a.value,
                    value: !sync.muted.contains(a.key),
                    onChanged: (on) => notifier.setMuted(a.key, !on),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Theme gallery, and Material's own options.
class _Appearance extends StatelessWidget {
  const _Appearance();

  @override
  Widget build(BuildContext context) {
    final c = themeController;
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) => Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: EdgeInsets.fromLTRB(isMaterial ? 28 : 22, 12, 22, 4),
            child: Text(caps('APPEARANCE'), style: overline()),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(isMaterial ? 28 : 22, 0, 22, 10),
            child: Text(c.resolve(c.id).tagline, style: TextStyle(color: kTextSecondary, fontSize: 13)),
          ),
          SizedBox(
            height: 270,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
              itemCount: themeIds.length,
              separatorBuilder: (_, __) => const SizedBox(width: 14),
              itemBuilder: (_, i) => ThemePreview(
                theme: c.resolve(themeIds[i]),
                selected: c.id == themeIds[i],
                onTap: () {
                  HapticFeedback.selectionClick();
                  c.select(themeIds[i]);
                },
              ),
            ),
          ),
          if (c.id == 'material')
            PaltSection(title: 'Material', children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                child: SegmentedButton<ThemeMode>(
                  segments: const [
                    ButtonSegment(value: ThemeMode.system, icon: Icon(Icons.brightness_auto_rounded), label: Text('System')),
                    ButtonSegment(value: ThemeMode.light, icon: Icon(Icons.light_mode_rounded), label: Text('Light')),
                    ButtonSegment(value: ThemeMode.dark, icon: Icon(Icons.dark_mode_rounded), label: Text('Dark')),
                  ],
                  selected: {c.mode},
                  onSelectionChanged: (s) => c.setMode(s.first),
                ),
              ),
              if (c.wallpaperSeed != null)
                PaltTile(
                  icon: Icons.wallpaper_rounded,
                  title: 'Wallpaper colours',
                  subtitle: 'Match the colours of your home screen',
                  value: c.wallpaper,
                  onChanged: c.setWallpaper,
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  for (final s in materialSeeds) _Swatch(seed: s, selected: !c.wallpaper || c.wallpaperSeed == null ? c.seed == s : false),
                ]),
              ),
            ]),
        ]),
      ),
    );
  }
}

/// A Material colour choice: the seed's tonal trio in a circle.
class _Swatch extends StatelessWidget {
  final Color seed;
  final bool selected;
  const _Swatch({required this.seed, required this.selected});

  @override
  Widget build(BuildContext context) {
    final cs = ColorScheme.fromSeed(seedColor: seed, brightness: palt.brightness);
    return GestureDetector(
      onTap: () => themeController.setSeed(seed),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 46,
        height: 46,
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(selected ? 14 : 23),
        ),
        padding: const EdgeInsets.all(6),
        child: ClipOval(
          child: Column(children: [
            Expanded(child: Container(color: cs.primary)),
            Expanded(
              child: Row(children: [
                Expanded(child: Container(color: cs.secondaryContainer)),
                Expanded(child: Container(color: cs.tertiaryContainer)),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}
