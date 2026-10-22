/// screen_capture.dart — screenshots and screen recordings of a paired
/// computer, taken from the phone. Captures are saved on the computer; the
/// phone can ask for a copy.
///
/// Packets (all requests; must match desktop/screen_app.go):
///   screen.shot    {} → {path, name, preview?, error?}   preview: base64 JPEG
///   screen.record  {action: start|stop|status} → {recording, since?, path?, name?, error?}
///   screen.fetch   {path} → {error?}   the computer sends the file over
library;

import 'dart:convert';
import 'dart:typed_data';

import '../services/link/link.dart';

class Capture {
  final String path, name;
  final Uint8List? preview;
  const Capture(this.path, this.name, [this.preview]);
}

class RecordingState {
  final bool recording;
  final DateTime? since;

  /// The finished recording, after a stop.
  final Capture? done;
  const RecordingState(this.recording, [this.since, this.done]);
}

class ScreenCapture {
  final Link link;
  ScreenCapture(this.link);

  static bool supported(Link? l) => l != null && l.supports('screen.shot');

  Future<Capture> screenshot() async {
    final b = await _request('screen.shot', {}, const Duration(seconds: 30));
    final preview = b['preview'] as String?;
    return Capture(b['path'] as String, b['name'] as String,
        preview == null || preview.isEmpty ? null : base64Decode(preview));
  }

  Future<RecordingState> record(String action) async {
    final b = await _request('screen.record', {'action': action}, const Duration(seconds: 20));
    final since = b['since'] as int?;
    final path = b['path'] as String?;
    return RecordingState(
      b['recording'] == true,
      since == null ? null : DateTime.fromMillisecondsSinceEpoch(since),
      path == null || path.isEmpty ? null : Capture(path, b['name'] as String? ?? path.split('/').last),
    );
  }

  /// Asks the computer to send the capture over as a normal transfer.
  Future<void> fetch(Capture c) => _request('screen.fetch', {'path': c.path}, const Duration(seconds: 20));

  Future<Map<String, dynamic>> _request(String t, Map<String, dynamic> body, Duration timeout) async {
    final p = await link.request(t, body: body, timeout: timeout);
    final b = p.body ?? const {};
    final err = b['error'] as String?;
    if (err != null && err.isNotEmpty) throw Exception(err);
    return b;
  }
}
