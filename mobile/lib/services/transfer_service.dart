import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';


import '../models/history_entry.dart';
import '../providers/auto_copy_provider.dart';
import '../providers/history_provider.dart';
import '../models/peer.dart';
import '../providers/link_provider.dart';
import '../providers/pairing_provider.dart';
import '../providers/relay_provider.dart';
import 'discovery_service.dart';
import 'lan_protocol.dart';
import 'palt_conn.dart';
import '../utils/media.dart';
import '../utils/storage_path.dart';

/// Must match MaxTextBytes in desktop/internal/transfer/protocol.go
const kMaxTextBytes = 16 * 1024;

/// Where received files are saved.
const kPaltDownloadDir = '/storage/emulated/0/Download/PALT';

/// Reduces a peer-supplied name to a bare file name so it can't escape the
/// download directory (e.g. "../../x" or "/etc/passwd").
String safeFileName(String name) {
  final base = name.replaceAll('\\', '/').split('/').last;
  return (base.isEmpty || base == '.' || base == '..') ? 'file' : base;
}

final transferServiceProvider = Provider<TransferService>((ref) {
  final service = TransferService(ref);
  service.startServer();
  ref.onDispose(service.stopServer);
  return service;
});

// ── State Models ─────────────────────────────────────────────────────────────

class FileMeta {
  final String name;
  final int size;

  FileMeta({required this.name, required this.size});

  factory FileMeta.fromJson(Map<String, dynamic> json) => FileMeta(
        name: json['name'],
        size: json['size'],
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'size': size,
      };
}

class OfferData {
  /// 'offer' for a file batch, 'text' for a message carried in [text].
  final String action;
  final String transferId;
  final List<FileMeta> files;
  final int totalSize;
  final String senderName;
  final String? text;

  /// Folder a paired computer asked the files to go in (its file browser).
  final String? dest;

  /// How this offer reached us ('direct' or 'relay'). Local only.
  final String route;

  /// The sender proved it holds our pairing key, and its device ID. Local only.
  final bool paired;
  final String? senderId;

  OfferData({
    this.action = 'offer',
    required this.transferId,
    required this.files,
    required this.totalSize,
    required this.senderName,
    this.text,
    this.dest,
    this.route = Route.direct,
    this.paired = false,
    this.senderId,
  });

  bool get isText => action == 'text';

  factory OfferData.fromJson(Map<String, dynamic> json,
          {String route = Route.direct, bool paired = false, String? senderId}) =>
      OfferData(
        action: json['action'] ?? 'offer',
        transferId: json['transferId'],
        files: ((json['files'] as List?) ?? [])
            .map((e) => FileMeta.fromJson(e))
            .toList(),
        totalSize: json['totalSize'] ?? 0,
        senderName: json['senderName'],
        text: json['text'],
        dest: json['dest'] as String?,
        route: route,
        paired: paired,
        senderId: senderId,
      );

  Map<String, dynamic> toJson() => {
        'action': action,
        'transferId': transferId,
        'files': files.map((e) => e.toJson()).toList(),
        'totalSize': totalSize,
        'senderName': senderName,
        if (text != null) 'text': text,
      };
}

/// A text message that just arrived, for the UI to surface as a toast.
class IncomingText {
  final String senderName;
  final String text;
  final bool copied;
  const IncomingText(this.senderName, this.text, {this.copied = false});
}

enum TransferStatus { waiting, transferring, completed, error }

class TransferProgress {
  final String transferId;
  final int written;
  final int total;
  final String? currentFileName;
  final double? speed; // Bytes per second
  final int? sentItems;
  final int? totalItems;
  final TransferStatus status;
  final String? error;
  final String? filePath;

  /// 'direct' or 'relay'; null until the connection is up.
  final String? route;

  const TransferProgress(
    this.transferId,
    this.written,
    this.total, {
    this.currentFileName,
    this.speed,
    this.sentItems,
    this.totalItems,
    this.status = TransferStatus.transferring,
    this.error,
    this.filePath,
    this.route,
  });
}

// ── Riverpod Providers for UI ────────────────────────────────────────────────

class ActiveOfferNotifier extends StateNotifier<OfferData?> {
  ActiveOfferNotifier() : super(null);
  
  Completer<bool>? _resolution;

  Future<bool> presentOffer(OfferData offer) {
    _resolution = Completer<bool>();
    state = offer;
    return _resolution!.future;
  }

  void accept() {
    _resolution?.complete(true);
    state = null;
  }

  void reject() {
    _resolution?.complete(false);
    state = null;
  }
}

final activeOfferProvider = StateNotifierProvider<ActiveOfferNotifier, OfferData?>((ref) => ActiveOfferNotifier());

final transferProgressProvider = StateProvider<TransferProgress?>((ref) => null);

final incomingTextProvider = StateProvider<IncomingText?>((ref) => null);

/// Files that just finished arriving, for a notification while in the background.
class ReceivedFiles {
  final String senderName;
  final List<String> names;
  const ReceivedFiles(this.senderName, this.names);
}

final receivedFilesProvider = StateProvider<ReceivedFiles?>((ref) => null);

// ── Core Service ─────────────────────────────────────────────────────────────

class TransferService {
  final Ref ref;
  ServerSocket? _serverSocket;
  final _uuid = const Uuid();
  final Future<String> _localName = fetchLocalDeviceName();

  TransferService(this.ref);

  Future<void> startServer() async {
    try {
      _serverSocket = await ServerSocket.bind(InternetAddress.anyIPv4, 9876);
      print('[TransferService] Server listening on port 9876');
      _serverSocket!.listen((socket) => handleConnection(SocketConn(socket)));
    } catch (e) {
      print('[TransferService] Error starting server: $e');
    }
  }

  void stopServer() {
    _serverSocket?.close();
  }

  /// Serves one connection arriving on the LAN socket: a plain v1 exchange
  /// from any device, or a v2 encrypted one from a paired device.
  Future<void> handleConnection(PaltConn conn) async {
    final reader = ByteReader(conn.input);
    try {
      final first = await reader.read(4).timeout(const Duration(seconds: 30));
      if (first == null) {
        conn.destroy(); // a bare connect-and-close is a reachability check
        return;
      }
      if (isHelloMagic(first)) {
        final raw = (conn as SocketConn).socket;
        final accepted = await secureAccept(raw, reader, ref.read(pairingProvider).keys);
        await handlePaired(accepted.conn, accepted.from);
        return;
      }
      final json = await readOfferJson(reader, prefix: first);
      if (json == null) {
        conn.destroy();
        return;
      }
      await _serve(conn, reader, OfferData.fromJson(json, route: conn.route));
    } catch (e) {
      print('[TransferService] Connection from ${conn.remoteLabel} failed: $e');
      conn.destroy();
    }
  }

  /// Serves an encrypted connection from a paired device [fromId]: a v2 LAN
  /// connection after its handshake, or a relay pipe.
  Future<void> handlePaired(PaltConn conn, String fromId) async {
    final reader = ByteReader(conn.input);
    try {
      final json = await readOfferJson(reader).timeout(const Duration(seconds: 30));
      if (json == null) {
        conn.destroy();
        return;
      }
      final offer = OfferData.fromJson(json, route: conn.route, paired: true, senderId: fromId);
      if (offer.action == 'link') {
        await ref.read(localNameProvider.future); // never announce a placeholder name
        conn.add([0x01]);
        await conn.flush();
        await ref.read(linkManagerProvider).run(conn, reader, conn.route, initiator: false);
        return;
      }
      await _serve(conn, reader, offer);
    } catch (e) {
      print('[TransferService] Paired connection from $fromId failed: $e');
      conn.destroy();
    }
  }

  /// Runs a text or file exchange whose offer has been read.
  Future<void> _serve(PaltConn socket, ByteReader reader, OfferData offer) async {
    final route = offer.route;
    if (offer.isText) {
      await _receiveText(socket, offer);
      return;
    }
    if (offer.action != 'offer') {
      print('[TransferService] Unknown action: ${offer.action}');
      socket.destroy();
      return;
    }

    // Paired devices proved they hold our key: their files come straight in.
    final accepted = offer.paired || await ref.read(activeOfferProvider.notifier).presentOffer(offer);
    if (!accepted) {
      socket.add([0x00]);
      await socket.close();
      return;
    }
    socket.add([0x01]);
    await socket.flush();

    final publicDir = Directory(kPaltDownloadDir);
    if (!await publicDir.exists()) {
      try {
        await publicDir.create(recursive: true);
      } catch (e) {
        print('[TransferService] Could not create PALT directory: $e');
      }
    }
    // A paired computer's file browser picks the folder.
    final dest = offer.paired ? storagePath(offer.dest) : null;
    final dirPath = offer.dest != null && dest != null && await Directory(dest).exists() ? dest : publicDir.path;
    final stopwatch = Stopwatch()..start();
    final totalFiles = offer.files.length;
    final hFiles = [for (final f in offer.files) HistoryFile(name: f.name, size: f.size)];
    final data = StreamIterator(reader.rest());
    var pending = Uint8List(0);
    var totalWritten = 0;

    try {
      for (int i = 0; i < totalFiles; i++) {
        final fileMeta = offer.files[i];
        // Never overwrite an earlier file with the same name.
        final savePath = uniqueFilePath(dirPath, safeFileName(fileMeta.name));
        hFiles[i] = HistoryFile(name: fileMeta.name, size: fileMeta.size, path: savePath);
        final fileSink = File(savePath).openWrite();
        var fileWritten = 0;
        try {
          while (fileWritten < fileMeta.size) {
            if (pending.isEmpty) {
              if (!await data.moveNext()) {
                throw 'Connection closed after $fileWritten of ${fileMeta.size} bytes of ${fileMeta.name}';
              }
              pending = data.current;
            }
            final take = min(fileMeta.size - fileWritten, pending.length);
            fileSink.add(Uint8List.sublistView(pending, 0, take));
            pending = Uint8List.sublistView(pending, take);
            fileWritten += take;
            totalWritten += take;

            if (totalWritten % (1024 * 512) < take || fileWritten == fileMeta.size) {
              final elapsedSec = stopwatch.elapsedMilliseconds / 1000.0;
              ref.read(transferProgressProvider.notifier).state = TransferProgress(
                  offer.transferId, fileWritten, fileMeta.size,
                  currentFileName: fileMeta.name,
                  speed: elapsedSec > 0 ? totalWritten / elapsedSec : 0.0,
                  sentItems: i + 1,
                  totalItems: totalFiles,
                  route: route);
            }
          }
        } finally {
          await fileSink.flush();
          await fileSink.close();
        }
        print('[TransferService] Downloaded File ${i + 1}/$totalFiles: ${fileMeta.name}');
      }

      socket.destroy();
      stopwatch.stop();
      for (final hFile in hFiles) {
        ref.read(historyProvider.notifier).addEntry(HistoryEntry(
              id: '${offer.transferId}_${hFile.name}',
              partnerName: offer.senderName,
              files: [hFile],
              totalSize: hFile.size,
              direction: 'incoming',
              timestamp: DateTime.now(),
              status: 'completed',
              durationMillis: stopwatch.elapsedMilliseconds,
              route: route,
            ));
      }
      ref.read(receivedFilesProvider.notifier).state =
          ReceivedFiles(offer.senderName, [for (final f in hFiles) f.name]);
      // So the gallery and other apps see them.
      unawaited(const MethodChannel('palt/files')
          .invokeMethod('scan', {'paths': [for (final f in hFiles) if (f.path != null) f.path!]})
          .catchError((Object _) {}));
      ref.read(transferProgressProvider.notifier).state = TransferProgress(
          offer.transferId, totalWritten, offer.totalSize,
          sentItems: totalFiles,
          totalItems: totalFiles,
          status: TransferStatus.completed,
          filePath: dirPath,
          route: route);
      Future.delayed(const Duration(seconds: 5), () {
        final current = ref.read(transferProgressProvider);
        if (current?.status == TransferStatus.completed && current?.transferId == offer.transferId) {
          ref.read(transferProgressProvider.notifier).state = null;
        }
      });
    } catch (e) {
      print('[TransferService] Stream processing error: $e');
      socket.destroy();
      for (final f in hFiles) {
        ref.read(historyProvider.notifier).addEntry(HistoryEntry(
              id: '${offer.transferId}_${f.name}',
              partnerName: offer.senderName,
              files: [f],
              totalSize: f.size,
              direction: 'incoming',
              timestamp: DateTime.now(),
              status: 'error',
              errorMessage: e.toString(),
              durationMillis: 0,
              route: route,
            ));
      }
      ref.read(transferProgressProvider.notifier).state = TransferProgress(
          offer.transferId, 0, offer.totalSize,
          status: TransferStatus.error, error: e.toString());
    }
  }

  Future<void> _receiveText(PaltConn socket, OfferData offer) async {
    final text = offer.text ?? '';
    final ok = text.isNotEmpty && utf8.encode(text).length <= kMaxTextBytes;
    socket.add([ok ? 0x01 : 0x00]);
    await socket.flush();
    socket.destroy();
    if (!ok) return;

    // Auto-copy is opt-in per device and only for paired devices, so an
    // arbitrary LAN peer can't overwrite the clipboard.
    var copied = false;
    if (offer.paired && ref.read(autoCopyProvider.notifier).isEnabled(offer.senderName)) {
      try {
        await Clipboard.setData(ClipboardData(text: text));
        copied = true;
      } catch (e) {
        print('[TransferService] Auto-copy failed: $e');
      }
    }

    ref.read(historyProvider.notifier).addEntry(HistoryEntry(
          id: offer.transferId,
          partnerName: offer.senderName,
          files: const [],
          totalSize: utf8.encode(text).length,
          direction: 'incoming',
          timestamp: DateTime.now(),
          status: 'completed',
          durationMillis: 0,
          kind: 'text',
          text: text,
          copied: copied,
          route: offer.route,
        ));
    ref.read(incomingTextProvider.notifier).state =
        IncomingText(offer.senderName, text, copied: copied);
  }

  // ── Route choice ────────────────────────────────────────────────────────────

  /// Connects to [peer]. Paired devices get an encrypted connection, over the
  /// LAN when possible, else the relay. Other devices get the plain v1
  /// protocol on the LAN. The connection's route says which way it went.
  Future<PaltConn> _dial(Peer peer) async {
    final pairing = ref.read(pairingProvider);
    final relay = await ref.read(relayClientProvider.future);
    final link = ref.read(linkManagerProvider).byName(peer.deviceName);

    if (link != null) {
      Object? lanErr;
      final ip = link.remoteIp;
      if (ip != null) {
        try {
          final port = peer.ipAddress == ip && peer.port > 0 ? peer.port : kPaltPort;
          return await secureDial(ip, port, selfId: pairing.deviceId, keys: pairing.keys);
        } catch (e) {
          lanErr = e;
        }
      }
      if (relay != null) {
        try {
          return await relay.dial(link.peer.id);
        } catch (e) {
          lanErr ??= e;
        }
      }
      throw 'Could not reach ${peer.deviceName}: $lanErr';
    }

    Object? directError;
    if (!peer.viaRelay) {
      try {
        return SocketConn(await Socket.connect(peer.ipAddress, peer.port,
            timeout: const Duration(seconds: 4)));
      } catch (e) {
        directError = e;
      }
    }
    final rp = relay?.peerByName(peer.deviceName);
    if (relay != null && rp != null) {
      print('[TransferClient] Sending to ${peer.deviceName} via relay');
      return relay.dial(rp.id);
    }
    if (directError != null) throw directError;
    throw '${peer.deviceName} is not reachable';
  }

  // ── Send Text ───────────────────────────────────────────────────────────────

  /// Sends a text message and records it in history. Throws with a
  /// user-readable message when the peer can't take it.
  Future<void> sendText(Peer peer, String text) async {
    final transferId = _uuid.v4();
    final bytes = utf8.encode(text).length;
    String? error;
    String? route;

    try {
      if (text.trim().isEmpty) throw 'Message is empty';
      if (bytes > kMaxTextBytes) {
        throw 'Message is too long (max ${kMaxTextBytes ~/ 1024} KB)';
      }

      final socket = await _dial(peer);
      route = socket.route;
      try {
        final offer = OfferData(
          action: 'text',
          transferId: transferId,
          files: const [],
          totalSize: 0,
          senderName: await _localName,
          text: text,
        );
        final jsonBytes = utf8.encode(jsonEncode(offer.toJson()));
        final lengthBuffer = ByteData(4)
          ..setUint32(0, jsonBytes.length, Endian.big);
        socket.add(lengthBuffer.buffer.asUint8List());
        socket.add(jsonBytes);
        await socket.flush();

        final verdict = Completer<int>();
        socket.input.listen(
          (data) {
            if (!verdict.isCompleted && data.isNotEmpty) verdict.complete(data[0]);
          },
          onError: (e) {
            if (!verdict.isCompleted) verdict.completeError(e);
          },
          // Builds without text support drop the connection without a verdict.
          onDone: () {
            if (!verdict.isCompleted) {
              verdict.completeError(
                  'This device does not support text messages — update PALT on it');
            }
          },
          cancelOnError: true,
        );

        final v = await verdict.future.timeout(const Duration(seconds: 10),
            onTimeout: () => throw 'No reply from ${peer.deviceName}');
        if (v != 0x01) throw 'Message rejected by ${peer.deviceName}';
      } finally {
        socket.destroy();
      }
    } on SocketException catch (e) {
      error = 'Could not reach ${peer.deviceName}: ${e.osError?.message ?? e.message}';
    } catch (e) {
      error = e.toString();
    }

    ref.read(historyProvider.notifier).addEntry(HistoryEntry(
          id: transferId,
          partnerName: peer.deviceName,
          files: const [],
          totalSize: bytes,
          direction: 'outgoing',
          timestamp: DateTime.now(),
          status: error == null ? 'completed' : 'error',
          errorMessage: error,
          durationMillis: 0,
          kind: 'text',
          text: text,
          route: route,
        ));

    if (error != null) throw error;
  }

  // ── Send Files ──────────────────────────────────────────────────────────────

  Future<void> sendFiles(Peer peer, List<File> files) async {
    int totalSize = 0;
    List<FileMeta> metaFiles = [];

    for (var file in files) {
      final size = await file.length();
      totalSize += size;
      metaFiles.add(FileMeta(name: file.uri.pathSegments.last, size: size));
    }

    if (metaFiles.isEmpty) return;

    final transferId = _uuid.v4();
    final senderName = await _localName;
    final totalFiles = metaFiles.length;
    final stopwatch = Stopwatch();

    ref.read(transferProgressProvider.notifier).state = 
        TransferProgress(transferId, 0, totalSize, sentItems: 0, totalItems: totalFiles);

    List<HistoryFile> hFiles = metaFiles.map((m) => HistoryFile(name: m.name, size: m.size)).toList();
    String? route;

    try {
      final socket = await _dial(peer);
      route = socket.route;
      print('[TransferClient] Connected to ${socket.remoteLabel} ($route)');
      stopwatch.start();

      final offer = OfferData(
        transferId: transferId,
        files: metaFiles,
        totalSize: totalSize,
        senderName: senderName,
      );

      final jsonBytes = utf8.encode(jsonEncode(offer.toJson()));
      final lengthBuffer = ByteData(4)..setUint32(0, jsonBytes.length, Endian.big);
      socket.add(lengthBuffer.buffer.asUint8List());
      socket.add(jsonBytes);

      ref.read(transferProgressProvider.notifier).state = TransferProgress(
        transferId,
        0,
        totalSize,
        sentItems: 0,
        totalItems: totalFiles,
        status: TransferStatus.waiting,
        route: route,
      );

      // Wait for 1-byte verdict
      final completer = Completer<bool>();
      socket.input.listen(
        (data) {
          if (!completer.isCompleted && data.isNotEmpty) {
            completer.complete(data[0] == 0x01);
          }
        },
        onError: (err) {
          if (!completer.isCompleted) completer.completeError(err);
        },
      );

      final accepted = await completer.future.timeout(const Duration(minutes: 1));
      if (!accepted) {
        ref.read(transferProgressProvider.notifier).state = TransferProgress(
          transferId,
          0,
          totalSize,
          status: TransferStatus.error,
          error: 'Transfer rejected by peer',
          route: route,
        );
        socket.destroy();
        return;
      }

      print('[TransferClient] Offer accepted. Sending $totalFiles files...');

      int totalWritten = 0;

      for (int i = 0; i < files.length; i++) {
        final stream = files[i].openRead();
        final fileSize = metaFiles[i].size;
        int fileWritten = 0;

        final mappedStream = stream.map((chunk) {
          fileWritten += chunk.length;
          totalWritten += chunk.length;

          if (totalWritten % (1024 * 512) < chunk.length || fileWritten == fileSize) {
              final elapsedSec = stopwatch.elapsedMilliseconds / 1000.0;
              final speed = elapsedSec > 0 ? totalWritten / elapsedSec : 0.0;

              ref.read(transferProgressProvider.notifier).state = 
                  TransferProgress(transferId, fileWritten, fileSize, 
                                   currentFileName: metaFiles[i].name,
                                   speed: speed,
                                   sentItems: i+1, totalItems: totalFiles,
                                   route: route);
          }
          return chunk;
        });

        await socket.addStream(mappedStream);

      }

      await socket.flush();
      socket.destroy();
      stopwatch.stop();

      print('[TransferClient] Transfer complete!');

      // Keep previews of sent pictures/videos so the thread can show them.
      for (var i = 0; i < hFiles.length; i++) {
        final f = hFiles[i];
        hFiles[i] = HistoryFile(
          name: f.name,
          size: f.size,
          path: files[i].path,
          preview: isMediaName(f.name) ? await makeSentPreview(files[i], '${transferId}_$i') : null,
        );
      }

      for (var hFile in hFiles) {
        final entry = HistoryEntry(
          id: '${transferId}_${hFile.name}',
          partnerName: peer.deviceName,
          files: [hFile],
          totalSize: hFile.size,
          direction: 'outgoing',
          timestamp: DateTime.now(),
          status: 'completed',
          durationMillis: stopwatch.elapsedMilliseconds,
          route: route,
        );
        ref.read(historyProvider.notifier).addEntry(entry);
      }
      
      ref.read(transferProgressProvider.notifier).state = 
          TransferProgress(transferId, totalSize, totalSize, 
                           sentItems: totalFiles, totalItems: totalFiles, 
                           status: TransferStatus.completed, route: route);
          
      Future.delayed(const Duration(seconds: 5), () {
        final current = ref.read(transferProgressProvider);
        if (current?.status == TransferStatus.completed && current?.transferId == transferId) {
          ref.read(transferProgressProvider.notifier).state = null;
        }
      });

    } catch (e) {
      print('[TransferClient] Error during send: $e');
      stopwatch.stop();

      for (var hFile in hFiles) {
        final entry = HistoryEntry(
          id: '${transferId}_${hFile.name}',
          partnerName: peer.deviceName,
          files: [hFile],
          totalSize: hFile.size,
          direction: 'outgoing',
          timestamp: DateTime.now(),
          status: 'error',
          errorMessage: e.toString(),
          durationMillis: stopwatch.elapsedMilliseconds,
          route: route,
        );
        ref.read(historyProvider.notifier).addEntry(entry);
      }

      ref.read(transferProgressProvider.notifier).state = 
                TransferProgress(transferId, 0, totalSize, status: TransferStatus.error, error: e.toString());
    }
  }
}
