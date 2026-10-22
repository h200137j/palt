/// media.dart — helpers for showing pictures inline in device threads.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

final _imageExt = RegExp(r'\.(jpe?g|png|gif|webp|heic|heif|bmp)$', caseSensitive: false);
final _videoExt = RegExp(r'\.(mp4|mov|m4v|webm|mkv|3gp|avi)$', caseSensitive: false);

/// Whether [name] looks like a picture we can try to show inline.
bool isImageName(String name) => _imageExt.hasMatch(name);

/// Whether [name] looks like a video we can show a frame of.
bool isVideoName(String name) => _videoExt.hasMatch(name);

bool isMediaName(String name) => isImageName(name) || isVideoName(name);

const _media = MethodChannel('palt/media');

/// A video's preview frame on disk and its length.
class VideoThumb {
  final String path;
  final Duration duration;
  const VideoThumb(this.path, this.duration);
}

Future<Directory> _previewDir() async {
  final dir = Directory('${(await getApplicationSupportDirectory()).path}/previews');
  await dir.create(recursive: true);
  return dir;
}

final _videoThumbs = <String, Future<VideoThumb?>>{};

/// Frame + duration for the video at [path], made once (by the Android side,
/// see MainActivity.kt) and cached on disk. Null when it can't be read.
Future<VideoThumb?> videoThumb(String path) =>
    _videoThumbs.putIfAbsent(path, () => _makeVideoThumb(path));

Future<VideoThumb?> _makeVideoThumb(String path) async {
  try {
    final src = File(path);
    final stat = await src.stat();
    if (stat.type == FileSystemEntityType.notFound) return null;
    final key = sha1
        .convert(utf8.encode('$path|${stat.size}|${stat.modified.millisecondsSinceEpoch}'))
        .toString();
    final dir = await _previewDir();
    final jpg = File('${dir.path}/v_$key.jpg');
    final dur = File('${dir.path}/v_$key.dur');
    if (await jpg.exists()) {
      final ms = int.tryParse(await dur.readAsString().catchError((_) => '0')) ?? 0;
      return VideoThumb(jpg.path, Duration(milliseconds: ms));
    }
    final res = await _media.invokeMapMethod<String, dynamic>(
        'videoThumbnail', {'path': path, 'maxSide': 480});
    final bytes = res?['jpeg'] as Uint8List?;
    if (bytes == null) return null;
    await jpg.writeAsBytes(bytes);
    final ms = (res?['durationMs'] as num?)?.toInt() ?? 0;
    await dur.writeAsString('$ms');
    return VideoThumb(jpg.path, Duration(milliseconds: ms));
  } catch (_) {
    return null;
  }
}

/// "1:23" / "1:02:03"
String formatDuration(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes % 60;
  final s = (d.inSeconds % 60).toString().padLeft(2, '0');
  return h > 0 ? '$h:${m.toString().padLeft(2, '0')}:$s' : '$m:$s';
}

/// Pictures bigger than this aren't decoded for a preview.
const _maxPreviewSource = 40 * 1024 * 1024;

/// Writes a small PNG preview of a picture we are sending, into app storage.
///
/// Files picked for sending are temporary copies that Android may clear, so
/// the thread keeps its own preview. Returns null when it can't be made.
Future<String?> makeSentPreview(File src, String id) async {
  if (isVideoName(src.path)) {
    // The frame is cached under the app's previews folder, which outlives
    // the picker's temporary copy of the video.
    return (await videoThumb(src.path))?.path;
  }
  try {
    if (await src.length() > _maxPreviewSource) return null;
    final codec = await ui.instantiateImageCodec(await src.readAsBytes(), targetWidth: 480);
    final frame = await codec.getNextFrame();
    final png = await frame.image.toByteData(format: ui.ImageByteFormat.png);
    frame.image.dispose();
    codec.dispose();
    if (png == null) return null;
    final dir = await _previewDir();
    final out = File('${dir.path}/${id.replaceAll(RegExp(r'[^A-Za-z0-9_.-]'), '_')}.png');
    await out.writeAsBytes(png.buffer.asUint8List(png.offsetInBytes, png.lengthInBytes));
    return out.path;
  } catch (_) {
    return null;
  }
}

/// A path in [dir] for [name] that doesn't overwrite an existing file:
/// "a.jpg", then "a (1).jpg", "a (2).jpg", …
String uniqueFilePath(String dir, String name) {
  var path = '$dir/$name';
  if (!File(path).existsSync()) return path;
  final dot = name.lastIndexOf('.');
  final base = dot > 0 ? name.substring(0, dot) : name;
  final ext = dot > 0 ? name.substring(dot) : '';
  for (var i = 1;; i++) {
    path = '$dir/$base ($i)$ext';
    if (!File(path).existsSync()) return path;
  }
}
