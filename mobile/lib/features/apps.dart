/// apps.dart — this phone as an app dock for a paired computer: list its
/// apps, open one (or bring it forward), quit it. Which apps are pinned, and
/// in what order, is kept on the phone per computer.
///
/// Packets (all requests; must match desktop/apps_app.go):
///   apps.list     {} → {apps: [{id, name, icon}], running: [id]}
///   apps.running  {} → {running: [id]}
///   apps.icon     {id} → {png}     base64, "" when the app has none
///   apps.launch   {id} → {error?}
///   apps.quit     {id} → {error?}
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/link/link.dart';

class DockApp {
  final String id, name;

  /// Version of the icon; changes with the picture, "" when there is none.
  final String icon;
  const DockApp(this.id, this.name, this.icon);

  factory DockApp.fromJson(Map<String, dynamic> j) =>
      DockApp(j['id'] as String? ?? '', j['name'] as String? ?? '', j['icon'] as String? ?? '');
}

class DockApps {
  final Link link;
  DockApps(this.link);

  static bool supported(Link? l) => l != null && l.supports('apps.launch');

  Future<(List<DockApp>, List<String>)> list() async {
    final p = await link.request('apps.list');
    final apps = [
      for (final a in (p.body?['apps'] as List? ?? const []))
        if (a is Map<String, dynamic>) DockApp.fromJson(a),
    ];
    return (apps, _ids(p.body?['running']));
  }

  Future<List<String>> running() async => _ids((await link.request('apps.running')).body?['running']);

  static List<String> _ids(Object? v) => [for (final id in (v as List? ?? const [])) id as String];

  Future<void> launch(String id) => _call('apps.launch', id);
  Future<void> quit(String id) => _call('apps.quit', id);

  Future<void> _call(String t, String id) async {
    final p = await link.request(t, body: {'id': id});
    final err = p.body?['error'] as String?;
    if (err != null && err.isNotEmpty) throw Exception(err);
  }

  // ── Icons: memory, then disk, then the computer ───────────────────────────

  static final _memory = <String, Uint8List?>{};
  static Directory? _dir;

  /// The icon's PNG, or null when the app has none or it can't be fetched.
  Future<Uint8List?> icon(DockApp app) async {
    if (app.icon.isEmpty) return null;
    final key = '${app.id}-${app.icon}';
    if (_memory.containsKey(key)) return _memory[key];
    _dir ??= await Directory('${(await getApplicationSupportDirectory()).path}/app_icons').create(recursive: true);
    final file = File('${_dir!.path}/${Uri.encodeComponent(key)}.png');
    if (await file.exists()) return _memory[key] = await file.readAsBytes();
    try {
      final p = await link.request('apps.icon', body: {'id': app.id});
      final b64 = p.body?['png'] as String? ?? '';
      final bytes = b64.isEmpty ? null : base64Decode(b64);
      if (bytes != null) await file.writeAsBytes(bytes);
      return _memory[key] = bytes;
    } catch (_) {
      return null; // try again next time
    }
  }

  // ── Pinned apps ───────────────────────────────────────────────────────────

  static String _pinKey(String device) => 'dock.pinned.$device';

  static Future<List<String>> pinned(String device) async =>
      (await SharedPreferences.getInstance()).getStringList(_pinKey(device)) ?? const [];

  static Future<void> setPinned(String device, List<String> ids) async =>
      (await SharedPreferences.getInstance()).setStringList(_pinKey(device), ids);
}
