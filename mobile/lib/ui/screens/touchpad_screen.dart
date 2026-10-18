/// touchpad_screen.dart — the phone as a touchpad and keyboard for a
/// computer (features/remote_input.dart).
///
/// Pad: one finger moves, tap clicks, two-finger tap right-clicks,
/// three-finger tap middle-clicks, two fingers scroll, tap then hold and
/// move drags. Buttons under the pad press and hold. The keyboard button
/// opens the phone's keyboard plus a row of special keys; Ctrl, Alt, Shift
/// and Super stay down for the next key.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/remote_input.dart';
import '../../models/peer.dart';
import '../../providers/link_provider.dart';
import '../../theme/app_theme.dart';

class TouchpadScreen extends ConsumerStatefulWidget {
  final Peer peer;
  const TouchpadScreen({super.key, required this.peer});

  @override
  ConsumerState<TouchpadScreen> createState() => _TouchpadScreenState();
}

enum _State { starting, asking, ready, failed }

class _TouchpadScreenState extends ConsumerState<TouchpadScreen> with WidgetsBindingObserver {
  RemoteInput? _input;
  _State _state = _State.starting;
  String? _error;
  bool _keyboard = false;
  final _mods = <String>{};

  // Hidden text field: always holds a sentinel space so Backspace on an
  // "empty" field still reaches us.
  static const _sentinel = ' ';
  final _text = TextEditingController(text: _sentinel);
  final _focus = FocusNode();
  String _last = _sentinel;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _start();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _input?.stop();
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.paused) {
      _input?.stop();
    } else if (s == AppLifecycleState.resumed && _state == _State.ready) {
      _start();
    }
  }

  Future<void> _start() async {
    final l = ref.read(linkManagerProvider).byName(widget.peer.deviceName);
    if (!RemoteInput.supported(l)) {
      setState(() {
        _state = _State.failed;
        _error = l == null
            ? '${widget.peer.deviceName} isn\'t connected'
            : 'Update PALT on ${widget.peer.deviceName} for this';
      });
      return;
    }
    final input = RemoteInput(l!);
    if (_state != _State.ready) setState(() => _state = _State.starting);
    // The first time, GNOME asks on the computer; say so if it takes a moment.
    final asking = Timer(const Duration(milliseconds: 900), () {
      if (mounted && _state == _State.starting) setState(() => _state = _State.asking);
    });
    try {
      await input.start();
      if (mounted) {
        setState(() {
          _input = input;
          _state = _State.ready;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _state = _State.failed;
          _error = e.toString().replaceFirst('Exception: ', '');
        });
      }
    } finally {
      asking.cancel();
    }
  }

  // ── Keyboard ───────────────────────────────────────────────────────────────

  void _onText(String now) {
    final input = _input;
    if (input == null) return;
    if (now.isEmpty) {
      // The sentinel was deleted: one Backspace.
      _sendKey('BackSpace');
      _reset();
      return;
    }
    var common = 0;
    final n = math.min(now.length, _last.length);
    while (common < n && now.codeUnitAt(common) == _last.codeUnitAt(common)) {
      common++;
    }
    for (var i = common; i < _last.length; i++) {
      _sendKey('BackSpace');
    }
    final added = now.substring(common);
    if (_mods.isNotEmpty && added.characters.length == 1) {
      _sendKey(added.toLowerCase());
    } else {
      input.text(added);
    }
    _last = now;
    if (now.length > 200) _reset();
  }

  void _reset() {
    _last = _sentinel;
    _text.value = const TextEditingValue(text: _sentinel, selection: TextSelection.collapsed(offset: 1));
  }

  void _sendKey(String key) {
    _input?.key(key, Set.of(_mods));
    if (_mods.isNotEmpty) setState(_mods.clear);
  }

  void _toggleKeyboard() {
    setState(() => _keyboard = !_keyboard);
    if (_keyboard) {
      _reset();
      _focus.requestFocus();
    } else {
      _focus.unfocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.peer.deviceName, style: display(fontSize: 19)),
        actions: [
          IconButton(
            tooltip: 'Keyboard',
            onPressed: _state == _State.ready ? _toggleKeyboard : null,
            icon: Icon(_keyboard ? Icons.keyboard_hide_rounded : Icons.keyboard_rounded),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
          child: Column(children: [
            if (_keyboard) ...[
              // Offstage-ish field: tiny but focusable, so the IME stays up.
              SizedBox(
                height: 1,
                child: Opacity(
                  opacity: 0,
                  child: TextField(
                    controller: _text,
                    focusNode: _focus,
                    autocorrect: false,
                    enableSuggestions: false,
                    keyboardType: TextInputType.text,
                    textInputAction: TextInputAction.send,
                    onChanged: _onText,
                    onSubmitted: (_) {
                      _sendKey('Return');
                      _reset();
                      _focus.requestFocus();
                    },
                  ),
                ),
              ),
              _SpecialKeys(
                mods: _mods,
                onMod: (m) => setState(() => _mods.contains(m) ? _mods.remove(m) : _mods.add(m)),
                onKey: _sendKey,
              ),
              const SizedBox(height: 10),
            ],
            Expanded(child: _body()),
            if (_state == _State.ready) ...[
              const SizedBox(height: 10),
              SizedBox(
                height: 64,
                child: Row(children: [
                  Expanded(child: _HoldButton(label: 'Left', onDown: () => _input?.button('left', 'down'), onUp: () => _input?.button('left', 'up'))),
                  const SizedBox(width: 8),
                  Expanded(child: _HoldButton(label: 'Right', onDown: () => _input?.button('right', 'down'), onUp: () => _input?.button('right', 'up'))),
                ]),
              ),
            ],
          ]),
        ),
      ),
    );
  }

  Widget _body() {
    switch (_state) {
      case _State.ready:
        return _Pad(input: _input!);
      case _State.starting:
        return const Center(child: CircularProgressIndicator(color: kAccent));
      case _State.asking:
        return _Message(
          icon: Icons.desktop_windows_rounded,
          title: 'Allow on ${widget.peer.deviceName}',
          text: 'The computer is asking whether PALT may control it. Choose Share or Allow there. '
              'It only asks once.',
          busy: true,
        );
      case _State.failed:
        return _Message(
          icon: Icons.mouse_rounded,
          title: 'Touchpad unavailable',
          text: _error ?? '',
          action: TextButton(onPressed: _start, child: const Text('Try again')),
        );
    }
  }
}

class _Message extends StatelessWidget {
  final IconData icon;
  final String title, text;
  final bool busy;
  final Widget? action;
  const _Message({required this.icon, required this.title, required this.text, this.busy = false, this.action});

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 40, color: kAccent),
            const SizedBox(height: 14),
            Text(title, style: display(fontSize: 20), textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(text, style: const TextStyle(color: kTextSecondary, fontSize: 13.5), textAlign: TextAlign.center),
            if (busy) ...[
              const SizedBox(height: 18),
              const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: kAccent)),
            ],
            if (action != null) ...[const SizedBox(height: 12), action!],
          ]),
        ),
      );
}

/// The touch surface. Raw pointer events, so finger counts are exact.
class _Pad extends StatefulWidget {
  final RemoteInput input;
  const _Pad({required this.input});

  @override
  State<_Pad> createState() => _PadState();
}

class _PadState extends State<_Pad> {
  static const _tapTime = Duration(milliseconds: 220);
  static const _tapSlop = 10.0; // logical px a tap may wander
  static const _dragWindow = Duration(milliseconds: 260);
  static const _speed = 1.6;
  static const _scrollSpeed = 0.6;

  final _points = <int, Offset>{};
  int _maxFingers = 0;
  DateTime _downAt = DateTime(0);
  double _travel = 0;
  DateTime _lastTap = DateTime(0);
  bool _dragging = false;
  bool _scrolling = false;

  RemoteInput get _in => widget.input;

  void _down(PointerDownEvent e) {
    if (_points.isEmpty) {
      _maxFingers = 0;
      _travel = 0;
      _downAt = DateTime.now();
      // Tap, then touch again quickly: hold the button and drag.
      if (DateTime.now().difference(_lastTap) < _dragWindow) {
        _dragging = true;
        _in.button('left', 'down');
      }
    }
    _points[e.pointer] = e.localPosition;
    _maxFingers = math.max(_maxFingers, _points.length);
  }

  void _move(PointerMoveEvent e) {
    final prev = _points[e.pointer];
    if (prev == null) return;
    _points[e.pointer] = e.localPosition;
    final d = e.localPosition - prev;
    _travel += d.distance;
    if (_points.length == 1 && _maxFingers == 1) {
      // Faster swipes go further (simple acceleration).
      final gain = _speed * (1 + math.min(d.distance / 18, 1.5));
      _in.move(d.dx * gain, d.dy * gain);
    } else if (_points.length == 2) {
      // Each finger reports separately; half each gives the average.
      // Natural scrolling: content follows the fingers.
      _scrolling = true;
      _in.scroll(-d.dx * _scrollSpeed / 2, -d.dy * _scrollSpeed / 2);
    }
  }

  void _up(PointerEvent e) {
    if (_points.remove(e.pointer) == null || _points.isNotEmpty) return;
    if (_scrolling) {
      _scrolling = false;
      _in.scrollEnd();
    }
    if (_dragging) {
      _dragging = false;
      _in.button('left', 'up');
      _lastTap = DateTime(0);
      return;
    }
    final quick = DateTime.now().difference(_downAt) < _tapTime;
    if (quick && _travel < _tapSlop * _maxFingers) {
      final button = switch (_maxFingers) { 1 => 'left', 2 => 'right', _ => 'middle' };
      _in.button(button);
      HapticFeedback.selectionClick();
      _lastTap = _maxFingers == 1 ? DateTime.now() : DateTime(0);
    }
  }

  @override
  Widget build(BuildContext context) => Listener(
        onPointerDown: _down,
        onPointerMove: _move,
        onPointerUp: _up,
        onPointerCancel: _up,
        // Swallow the gesture arena so the page never scrolls or pops.
        child: RawGestureDetector(
          gestures: {
            EagerGestureRecognizer: GestureRecognizerFactoryWithHandlers<EagerGestureRecognizer>(
                EagerGestureRecognizer.new, (_) {}),
          },
          child: Container(
            decoration: BoxDecoration(
              gradient: kTileGradient,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: kHairline),
            ),
            alignment: Alignment.center,
            child: const Text(
              'Move with one finger · tap to click\nTwo fingers: scroll · tap for right click\nTap then hold to drag',
              textAlign: TextAlign.center,
              style: TextStyle(color: kTextFaint, fontSize: 12.5, height: 1.6),
            ),
          ),
        ),
      );
}

/// A mouse button: down while the finger is on it.
class _HoldButton extends StatefulWidget {
  final String label;
  final VoidCallback onDown, onUp;
  const _HoldButton({required this.label, required this.onDown, required this.onUp});

  @override
  State<_HoldButton> createState() => _HoldButtonState();
}

class _HoldButtonState extends State<_HoldButton> {
  bool _held = false;

  void _set(bool held) {
    if (held == _held) return;
    setState(() => _held = held);
    if (held) {
      HapticFeedback.selectionClick();
      widget.onDown();
    } else {
      widget.onUp();
    }
  }

  @override
  Widget build(BuildContext context) => Listener(
        onPointerDown: (_) => _set(true),
        onPointerUp: (_) => _set(false),
        onPointerCancel: (_) => _set(false),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 90),
          decoration: BoxDecoration(
            gradient: _held ? kAccentGradient : kTileGradient,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: kHairline),
          ),
          alignment: Alignment.center,
          child: Text(widget.label,
              style: TextStyle(color: _held ? kOnAccent : kText, fontSize: 14, fontWeight: FontWeight.w600)),
        ),
      );
}

/// Ctrl, Alt, Shift, Super (sticky for the next key) and keys the phone's
/// keyboard lacks.
class _SpecialKeys extends StatelessWidget {
  final Set<String> mods;
  final ValueChanged<String> onMod;
  final ValueChanged<String> onKey;
  const _SpecialKeys({required this.mods, required this.onMod, required this.onKey});

  static const _modKeys = [('ctrl', 'Ctrl'), ('alt', 'Alt'), ('shift', 'Shift'), ('super', 'Super')];
  static const _keys = [
    ('Escape', 'Esc'), ('Tab', 'Tab'), ('Left', '←'), ('Up', '↑'), ('Down', '↓'), ('Right', '→'),
    ('BackSpace', '⌫'), ('Delete', 'Del'), ('Home', 'Home'), ('End', 'End'),
    ('Page_Up', 'PgUp'), ('Page_Down', 'PgDn'),
    ('F1', 'F1'), ('F2', 'F2'), ('F3', 'F3'), ('F4', 'F4'), ('F5', 'F5'), ('F6', 'F6'),
    ('F7', 'F7'), ('F8', 'F8'), ('F9', 'F9'), ('F10', 'F10'), ('F11', 'F11'), ('F12', 'F12'),
    ('Print', 'PrtSc'),
  ];

  Widget _chip(String label, bool on, VoidCallback onTap) => Padding(
        padding: const EdgeInsets.only(right: 6),
        child: Material(
          type: MaterialType.transparency,
          child: Ink(
            decoration: BoxDecoration(
              gradient: on ? kAccentGradient : kTileGradient,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: kHairline),
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Text(label,
                    style: TextStyle(color: on ? kOnAccent : kText, fontSize: 13, fontWeight: FontWeight.w600)),
              ),
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 42,
        child: ListView(scrollDirection: Axis.horizontal, children: [
          for (final (id, label) in _modKeys) _chip(label, mods.contains(id), () => onMod(id)),
          // Super alone opens GNOME's overview.
          _chip('⊞', false, () => onKey('Super_L')),
          for (final (id, label) in _keys) _chip(label, false, () => onKey(id)),
        ]),
      );
}
