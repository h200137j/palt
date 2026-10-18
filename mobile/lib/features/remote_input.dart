/// remote_input.dart — this phone as a touchpad and keyboard for a paired
/// computer. Pointer moves and scrolls are summed and sent at most once a
/// frame so a fast swipe doesn't flood the link.
///
/// Packets (must match desktop/input_app.go):
///   input.start   {} → {error?}   (request; the computer may ask the user once)
///   input.stop    {}
///   input.move    {dx, dy}
///   input.button  {button: left|right|middle, state: click|down|up}
///   input.scroll  {dx, dy, finish?}
///   input.key     {key, mods?}    key: Return, BackSpace, Tab, Escape, Delete,
///                                 Home, End, Page_Up, Page_Down, Left, Up,
///                                 Right, Down, Insert, Print, Menu, space,
///                                 Super_L, F1–F12, or one character
///   input.text    {text}
library;

import 'dart:async';

import '../services/link/link.dart';

class RemoteInput {
  final Link link;
  RemoteInput(this.link);

  static bool supported(Link? l) => l != null && l.supports('input.move');

  /// Starts control on the computer; throws with the computer's reason.
  Future<void> start() async {
    final p = await link.request('input.start', timeout: const Duration(minutes: 3));
    final err = p.body?['error'] as String?;
    if (err != null && err.isNotEmpty) throw Exception(err);
  }

  void stop() => _send('input.stop', {});

  double _mx = 0, _my = 0, _sx = 0, _sy = 0;
  Timer? _flush;

  void move(double dx, double dy) {
    _mx += dx;
    _my += dy;
    _schedule();
  }

  void scroll(double dx, double dy) {
    _sx += dx;
    _sy += dy;
    _schedule();
  }

  /// Ends a scroll gesture so the computer can coast (kinetic scrolling).
  void scrollEnd() {
    _sendNow();
    _send('input.scroll', {'dx': 0.0, 'dy': 0.0, 'finish': true});
  }

  void button(String button, [String state = 'click']) {
    _sendNow();
    _send('input.button', {'button': button, 'state': state});
  }

  void key(String key, [Set<String> mods = const {}]) =>
      _send('input.key', {'key': key, if (mods.isNotEmpty) 'mods': mods.toList()});

  void text(String text) {
    if (text.isNotEmpty) _send('input.text', {'text': text});
  }

  void _schedule() => _flush ??= Timer(const Duration(milliseconds: 12), _sendNow);

  void _sendNow() {
    _flush?.cancel();
    _flush = null;
    if (_mx != 0 || _my != 0) {
      _send('input.move', {'dx': _mx, 'dy': _my});
      _mx = _my = 0;
    }
    if (_sx != 0 || _sy != 0) {
      _send('input.scroll', {'dx': _sx, 'dy': _sy});
      _sx = _sy = 0;
    }
  }

  void _send(String t, Map<String, dynamic> body) => link.send(t, body: body).catchError((Object _) {});
}
