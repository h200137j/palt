import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'package:path_provider/path_provider.dart';

import '../models/peer.dart';
import '../providers/trust_provider.dart';

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
  final String transferId;
  final List<FileMeta> files;
  final int totalSize;
  final String senderName;

  OfferData({
    required this.transferId,
    required this.files,
    required this.totalSize,
    required this.senderName,
  });

  factory OfferData.fromJson(Map<String, dynamic> json) => OfferData(
        transferId: json['transferId'],
        files: (json['files'] as List).map((e) => FileMeta.fromJson(e)).toList(),
        totalSize: json['totalSize'],
        senderName: json['senderName'],
      );

  Map<String, dynamic> toJson() => {
        'action': 'offer',
        'transferId': transferId,
        'files': files.map((e) => e.toJson()).toList(),
        'totalSize': totalSize,
        'senderName': senderName,
      };
}

enum TransferStatus { transferring, completed, error }

class TransferProgress {
  final String transferId;
  final int written;
  final int total;
  final int? sentItems;
  final int? totalItems;
  final TransferStatus status;
  final String? error;
  final String? filePath;

  const TransferProgress(
    this.transferId,
    this.written,
    this.total, {
    this.sentItems,
    this.totalItems,
    this.status = TransferStatus.transferring,
    this.error,
    this.filePath,
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

// ── Core Service ─────────────────────────────────────────────────────────────

class TransferService {
  final Ref ref;
  ServerSocket? _serverSocket;
  final _uuid = const Uuid();

  TransferService(this.ref);

  Future<void> startServer() async {
    try {
      _serverSocket = await ServerSocket.bind(InternetAddress.anyIPv4, 9876);
      print('[TransferService] Server listening on port 9876');
      _serverSocket!.listen(_handleIncomingConnection);
    } catch (e) {
      print('[TransferService] Error starting server: $e');
    }
  }

  void stopServer() {
    _serverSocket?.close();
  }

  // Parses length-prefixed JSON handshake and streams multiple files sequentially
  Future<void> _handleIncomingConnection(Socket socket) async {
    print('[TransferService] Got connection from ${socket.remoteAddress.address}');
    
    final iterator = StreamIterator(socket);
    BytesBuilder buffer = BytesBuilder();
    int expectedLength = -1;
    OfferData? offer;
    bool handshakeComplete = false;

    try {
      // 1. Handshake Phase
      while (await iterator.moveNext()) {
        final data = iterator.current;
        buffer.add(data);
        final bytes = buffer.toBytes();

        if (expectedLength == -1 && bytes.length >= 4) {
          expectedLength = ByteData.view(bytes.buffer).getUint32(0, Endian.big);
        }

        if (expectedLength != -1 && bytes.length >= 4 + expectedLength) {
          // We have the full JSON
          final jsonBytes = bytes.sublist(4, 4 + expectedLength);
          final jsonStr = utf8.decode(jsonBytes);
          offer = OfferData.fromJson(jsonDecode(jsonStr));

          // Surface to UI
          final isTrusted = ref.read(trustProvider.notifier).isTrusted(offer.senderName);
          bool accepted = false;
          
          if (isTrusted) {
            print('[TransferService] Auto-accepting from trusted sender: ${offer.senderName}');
            accepted = true;
          } else {
            accepted = await ref.read(activeOfferProvider.notifier).presentOffer(offer);
          }

          if (!accepted) {
            socket.add([0x00]); // Reject
            socket.destroy();
            return;
          }

          // Accepted
          socket.add([0x01]);

          // Shift overflow bytes left over from the handshake segment
          buffer.clear();
          if (bytes.length > 4 + expectedLength) {
            buffer.add(bytes.sublist(4 + expectedLength));
          }

          handshakeComplete = true;
          break; // Exit to data phase
        }
      }

      if (!handshakeComplete || offer == null) {
        socket.destroy();
        return;
      }

      // 2. Setup download directory
      final publicDir = Directory('/storage/emulated/0/Download/PALT');
      if (!await publicDir.exists()) {
        try {
          await publicDir.create(recursive: true);
        } catch (e) {
          print('[TransferService] Could not create PALT directory: $e');
        }
      }
      
      String dirPath = publicDir.path;
      if (!await publicDir.exists()) {
        final fallbackDir = await getDownloadsDirectory();
        dirPath = fallbackDir?.path ?? '/storage/emulated/0/Download';
      }

      // 3. Sequential Multi-file Pipelining
      int totalWritten = 0;
      final totalFiles = offer.files.length;

      for (int i = 0; i < totalFiles; i++) {
        final fileMeta = offer.files[i];
        final savePath = '$dirPath/${fileMeta.name}';
        final fileSink = File(savePath).openWrite();
        int fileWritten = 0;

        // Drain overflow buffer first
        if (buffer.isNotEmpty) {
          final bytesStr = buffer.toBytes();
          final available = bytesStr.length;
          final needed = fileMeta.size - fileWritten;

          if (available <= needed) {
            fileSink.add(bytesStr);
            fileWritten += available;
            totalWritten += available;
            buffer.clear();
          } else {
            fileSink.add(bytesStr.sublist(0, needed));
            fileWritten += needed;
            totalWritten += needed;
            buffer.clear();
            buffer.add(bytesStr.sublist(needed));
          }
        }

        // Stream exactly remaining raw files bytes directly from socket iterator
        while (fileWritten < fileMeta.size && await iterator.moveNext()) {
          final data = iterator.current;
          int needed = fileMeta.size - fileWritten;

          if (data.length <= needed) {
            fileSink.add(data);
            fileWritten += data.length;
            totalWritten += data.length;
          } else {
            fileSink.add(data.sublist(0, needed));
            fileWritten += needed;
            totalWritten += needed;
            
            // Re-buffer the overflow bytes for the next file loop!
            buffer.add(data.sublist(needed));
          }

          // Report progress 
          if (totalWritten % (1024 * 512) < data.length || fileWritten == fileMeta.size) {
            ref.read(transferProgressProvider.notifier).state = 
                TransferProgress(offer.transferId, totalWritten, offer.totalSize, 
                                 sentItems: i+1, totalItems: totalFiles);
          }
        }

        await fileSink.flush();
        await fileSink.close();
        print('[TransferService] Downloaded File ${i+1}/${totalFiles}: ${fileMeta.name}');
      }

      print('[TransferService] Batch Download complete!');
      socket.destroy();
      
      ref.read(transferProgressProvider.notifier).state = 
          TransferProgress(offer.transferId, totalWritten, offer.totalSize, 
                           sentItems: totalFiles, totalItems: totalFiles,
                           status: TransferStatus.completed, filePath: dirPath);

    } catch (e) {
      print('[TransferService] Stream processing error: $e');
      ref.read(transferProgressProvider.notifier).state = 
          TransferProgress(offer?.transferId ?? 'unknown', 0, offer?.totalSize ?? 0, 
                           status: TransferStatus.error, error: e.toString());
      socket.destroy();
    }
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
    final senderName = Platform.localHostname.isNotEmpty ? Platform.localHostname : 'Android Client';
    final totalFiles = metaFiles.length;

    ref.read(transferProgressProvider.notifier).state = 
        TransferProgress(transferId, 0, totalSize, sentItems: 0, totalItems: totalFiles);

    try {
      final socket = await Socket.connect(peer.ipAddress, peer.port, timeout: const Duration(seconds: 5));
      print('[TransferClient] Connected to ${peer.ipAddress}:${peer.port}');

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

      // Wait for 1-byte verdict
      final completer = Completer<bool>();
      socket.listen(
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
      if (!accepted) throw Exception('Peer rejected the transfer');

      print('[TransferClient] Offer accepted. Sending $totalFiles files...');

      int totalWritten = 0;

      for (int i = 0; i < files.length; i++) {
        final stream = files[i].openRead();
        final fileSize = metaFiles[i].size;
        int fileWritten = 0;

        await for (final chunk in stream) {
          socket.add(chunk);
          fileWritten += chunk.length;
          totalWritten += chunk.length;

          if (totalWritten % (1024 * 512) < chunk.length || fileWritten == fileSize) {
              ref.read(transferProgressProvider.notifier).state = 
                  TransferProgress(transferId, totalWritten, totalSize, sentItems: i+1, totalItems: totalFiles);
          }
        }
      }

      await socket.flush();
      socket.destroy();
      
      print('[TransferClient] Transfer complete!');
      
      ref.read(transferProgressProvider.notifier).state = 
          TransferProgress(transferId, totalSize, totalSize, 
                           sentItems: totalFiles, totalItems: totalFiles, 
                           status: TransferStatus.completed);
          
      Future.delayed(const Duration(seconds: 2), () {
        ref.read(transferProgressProvider.notifier).state = null;
      });

    } catch (e) {
      print('[TransferClient] Error during send: $e');
      ref.read(transferProgressProvider.notifier).state = 
                TransferProgress(transferId, 0, totalSize, status: TransferStatus.error, error: e.toString());
    }
  }
}
