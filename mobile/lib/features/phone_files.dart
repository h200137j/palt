/// phone_files.dart — paired computers browse this phone's storage: folders,
/// thumbnails, download, upload (offers naming a folder), delete, new
/// folder. They can also take a photo with the phone, which is sent back.
///
/// It also watches for screenshots of a Wi-Fi QR code and offers to send
/// them to a computer, which then asks to join that network.
///
/// Packet types (must match desktop/phonefiles_app.go). Requests carry an
/// id and are answered by "<type>.reply" with the same id.
///   files.list    desktop → phone  {path} → {path, entries: [{name, dir,
///                                  size, modified}], access}
///   files.thumb   desktop → phone  {path, size} → {data} (base64 JPEG)
///   files.get     desktop → phone  {paths} → {} then sends them
///   files.delete  desktop → phone  {paths} → {}
///   files.mkdir   desktop → phone  {path} → {}
///   files.allow   desktop → phone  {} → {} opens "All files access"
///   storage.info  desktop → phone  {} → {total, free, categories, folders,
///                                  largest, volumes, ram} (PhoneFiles.kt)
///   camera.photo  desktop → phone  {} → {} opens the camera; the photo
///                                  follows as a transfer
///
/// For the computer's file manager (the phone mounted as a folder):
///   files.read      {path, offset, length} → {data} (base64, ≤ 512 KiB)
///   files.write     {path, offset, data, create?} → {}  create empties it first
///   files.truncate  {path, size} → {}
///   files.rename    {from, to} → {}
///   files.space     {} → {total, free}
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../models/peer.dart';
import '../providers/link_provider.dart';
import '../services/link/link.dart';
import '../services/transfer_service.dart';
import '../utils/storage_path.dart';

const _channel = MethodChannel('palt/files');

/// The computer at the other end of [l], for sending it files.
Peer _peerOf(Link l) => Peer(
    id: l.peer.id, deviceName: l.peer.name, ipAddress: '', port: 0, os: l.peer.os, deviceId: l.peer.id, paired: true);

void setupPhoneFiles(ProviderContainer c) {
  final links = c.read(linkManagerProvider);

  void answer(String type, Future<Map<String, dynamic>> Function(Link l, Map<String, dynamic> b) work) {
    links.handle(type, (l, p) {
      unawaited(() async {
        Map<String, dynamic> reply;
        try {
          reply = await work(l, p.body ?? const {});
        } on PlatformException catch (e) {
          reply = {'error': e.message ?? e.code};
        } on FileSystemException catch (e) {
          reply = {'error': e.osError?.message ?? e.message};
        } catch (e) {
          reply = {'error': e.toString()};
        }
        await l.send('$type.reply', id: p.id, body: reply).catchError((Object _) {});
      }());
    });
  }

  List<String> paths(Object? list) {
    final out = <String>[];
    for (final p in (list as List?) ?? const []) {
      final s = storagePath(p as String?);
      if (s == null || s == kStorageRoot) throw 'Not allowed: $p';
      out.add(s);
    }
    return out;
  }

  Future<bool> access() async => await _channel.invokeMethod<bool>('hasAccess') ?? false;

  answer('files.list', (l, b) async {
    final path = storagePath(b['path'] as String?);
    if (path == null) throw 'Not allowed';
    if (!await access()) return {'path': path, 'entries': [], 'access': false};
    final entries = <Map<String, dynamic>>[];
    await for (final e in Directory(path).list(followLinks: false)) {
      final name = e.path.substring(e.path.lastIndexOf('/') + 1);
      try {
        final st = await e.stat();
        entries.add({
          'name': name,
          'dir': st.type == FileSystemEntityType.directory,
          'size': st.size,
          'modified': st.modified.millisecondsSinceEpoch,
        });
      } catch (_) {}
    }
    return {'path': path, 'entries': entries, 'access': true};
  });

  answer('files.thumb', (l, b) async {
    final path = storagePath(b['path'] as String?);
    if (path == null) throw 'Not allowed';
    final bytes = await _channel.invokeMethod<Uint8List>('thumb', {
      'path': path,
      'size': ((b['size'] as num?)?.toInt() ?? 256).clamp(64, 512),
    });
    return {'data': bytes == null ? '' : base64Encode(bytes)};
  });

  answer('files.get', (l, b) async {
    final files = [for (final p in paths(b['paths'])) File(p)];
    for (final f in files) {
      if (!await f.exists()) throw '${f.path.split('/').last} is a folder or gone';
    }
    unawaited(c.read(transferServiceProvider).sendFiles(_peerOf(l), files));
    return {};
  });

  answer('files.delete', (l, b) async {
    final ps = paths(b['paths']);
    for (final p in ps) {
      await FileSystemEntity.isDirectory(p) ? await Directory(p).delete(recursive: true) : await File(p).delete();
    }
    await _channel.invokeMethod('scan', {'paths': ps});
    return {};
  });

  answer('files.mkdir', (l, b) async {
    final p = paths([b['path']]).first;
    await Directory(p).create(recursive: true);
    return {};
  });

  // Changed files reach the gallery and other apps through a media scan,
  // batched so a copy of many files scans once.
  final toScan = <String>{};
  Timer? scanTimer;
  void scanLater(Iterable<String> ps) {
    toScan.addAll(ps);
    scanTimer?.cancel();
    scanTimer = Timer(const Duration(seconds: 2), () {
      final list = toScan.toList();
      toScan.clear();
      unawaited(_channel.invokeMethod('scan', {'paths': list}).catchError((Object _) {}));
    });
  }

  answer('files.read', (l, b) async {
    final p = paths([b['path']]).first;
    final offset = (b['offset'] as num?)?.toInt() ?? 0;
    final length = ((b['length'] as num?)?.toInt() ?? 0).clamp(0, 512 * 1024);
    final f = await File(p).open();
    try {
      await f.setPosition(offset);
      return {'data': base64Encode(await f.read(length))};
    } finally {
      await f.close();
    }
  });

  answer('files.write', (l, b) async {
    final p = paths([b['path']]).first;
    final data = base64Decode(b['data'] as String? ?? '');
    // append mode opens read-write without emptying; write mode empties.
    final f = await File(p).open(mode: b['create'] == true ? FileMode.write : FileMode.append);
    try {
      await f.setPosition((b['offset'] as num?)?.toInt() ?? 0);
      await f.writeFrom(data);
    } finally {
      await f.close();
    }
    scanLater([p]);
    return {};
  });

  answer('files.truncate', (l, b) async {
    final p = paths([b['path']]).first;
    final f = await File(p).open(mode: FileMode.append);
    try {
      await f.truncate((b['size'] as num?)?.toInt() ?? 0);
    } finally {
      await f.close();
    }
    scanLater([p]);
    return {};
  });

  answer('files.rename', (l, b) async {
    final ps = paths([b['from'], b['to']]);
    final type = await FileSystemEntity.type(ps[0], followLinks: false);
    if (type == FileSystemEntityType.notFound) throw 'No such file or directory';
    type == FileSystemEntityType.directory
        ? await Directory(ps[0]).rename(ps[1])
        : await File(ps[0]).rename(ps[1]);
    scanLater(ps);
    return {};
  });

  answer('files.space', (l, b) async {
    final r = await _channel.invokeMethod<Map>('space');
    return Map<String, dynamic>.from(r ?? const {});
  });

  answer('storage.info', (l, b) async {
    final info = await _channel.invokeMethod<Map>('storage');
    return Map<String, dynamic>.from(info ?? const {});
  });

  answer('files.allow', (l, b) async {
    await _channel.invokeMethod('allow');
    return {};
  });

  // The computer that asked for the photo in progress.
  String? photoFor;
  answer('camera.photo', (l, b) async {
    await _channel.invokeMethod('photo');
    photoFor = l.peer.id;
    return {};
  });

  _channel.setMethodCallHandler((call) async {
    switch (call.method) {
      case 'photo':
        final path = call.arguments as String?;
        final l = photoFor == null ? null : links.get(photoFor!);
        photoFor = null;
        if (path != null && l != null) {
          await c.read(transferServiceProvider).sendFiles(_peerOf(l), [File(path)]);
        }
      case 'screenshot':
        await _checkWifiQr(links, call.arguments as String);
      case 'sendWifi':
        final m = Map<String, dynamic>.from(call.arguments as Map);
        final l = links.get(m['computer'] as String? ?? '');
        if (l != null) await c.read(transferServiceProvider).sendFiles(_peerOf(l), [File(m['path'] as String)]);
    }
  });
  unawaited(_channel.invokeMethod('watchScreenshots').catchError((Object _) {}));
}

/// Offers a new screenshot to computers when it shows a Wi-Fi QR code.
Future<void> _checkWifiQr(LinkManager links, String path) async {
  final computers = [
    for (final l in links.links)
      if (l.peer.os != 'android') {'id': l.peer.id, 'name': l.peer.name},
  ];
  if (computers.isEmpty) return;
  final scanner = MobileScannerController(autoStart: false);
  try {
    final capture = await scanner.analyzeImage(path, formats: const [BarcodeFormat.qrCode]);
    for (final b in capture?.barcodes ?? const <Barcode>[]) {
      final ssid = b.wifi?.ssid;
      if (b.type == BarcodeType.wifi && ssid != null) {
        await _channel.invokeMethod('offerWifi', {'path': path, 'ssid': ssid, 'computers': computers});
        return;
      }
    }
  } catch (_) {
    // not a picture the scanner can read
  } finally {
    unawaited(scanner.dispose());
  }
}
