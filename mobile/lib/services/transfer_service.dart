import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'package:path_provider/path_provider.dart';

import '../models/peer.dart';

final transferServiceProvider = Provider<TransferService>((ref) {
  final service = TransferService(ref);
  service.startServer();
  ref.onDispose(service.stopServer);
  return service;
});

// ── State Models ─────────────────────────────────────────────────────────────

class OfferData {
  final String transferId;
  final String fileName;
  final int fileSize;
  final String senderName;

  OfferData({
    required this.transferId,
    required this.fileName,
    required this.fileSize,
    required this.senderName,
  });

  factory OfferData.fromJson(Map<String, dynamic> json) => OfferData(
        transferId: json['transferId'],
        fileName: json['fileName'],
        fileSize: json['fileSize'],
        senderName: json['senderName'],
      );

  Map<String, dynamic> toJson() => {
        'action': 'offer',
        'transferId': transferId,
        'fileName': fileName,
        'fileSize': fileSize,
        'senderName': senderName,
      };
}

enum TransferStatus { transferring, completed, error }

class TransferProgress {
  final String transferId;
  final int written;
  final int total;
  final TransferStatus status;
  final String? error;
  final String? filePath;

  const TransferProgress(
    this.transferId,
    this.written,
    this.total, {
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

  // Parses length-prefixed JSON handshake and streams file
  Future<void> _handleIncomingConnection(Socket socket) async {
    print('[TransferService] Got connection from ${socket.remoteAddress.address}');
    
    int expectedLength = -1;
    BytesBuilder buffer = BytesBuilder();
    OfferData? offer;
    File? outputFile;
    IOSink? fileSink;
    int bytesWritten = 0;
    
    Completer<void> streamController = Completer();

    socket.listen(
      (Uint8List data) async {
        try {
          if (offer == null) {
            // Handshake phase
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

              // Surface to UI and wait for Accept/Reject
              bool accepted = await ref.read(activeOfferProvider.notifier).presentOffer(offer!);

              if (!accepted) {
                socket.add([0x00]); // Reject
                socket.destroy();
                return;
              }

              // Accepted
              socket.add([0x01]); // Accept

              // Setup download location: Prioritize public Downloads folder so it's visible to user
              final publicDir = Directory('/storage/emulated/0/Download/PALT');
              if (!await publicDir.exists()) {
                try {
                  await publicDir.create(recursive: true);
                } catch (e) {
                  print('[TransferService] Could not create public PALT directory: $e');
                }
              }
              
              String dirPath = publicDir.path;
              if (!await publicDir.exists()) {
                final fallbackDir = await getDownloadsDirectory();
                dirPath = fallbackDir?.path ?? '/storage/emulated/0/Download';
              }
              
              outputFile = File('$dirPath/${offer!.fileName}');
              print('[TransferService] Downloading to ${outputFile!.path}');
              fileSink = outputFile!.openWrite();

              // Write any remaining bytes in the buffer directly to the file
              if (bytes.length > 4 + expectedLength) {
                final extra = bytes.sublist(4 + expectedLength);
                fileSink!.add(extra);
                bytesWritten += extra.length;
              }
              
              // Clear buffer
              buffer.clear();
            }
          } else {
            // Data streaming phase
            if (fileSink != null) {
              fileSink!.add(data);
              bytesWritten += data.length;
              
              // Report progress to UI periodically to avoid drowning Riverpod
              if (bytesWritten % (1024 * 512) < data.length || bytesWritten == offer!.fileSize) {
                ref.read(transferProgressProvider.notifier).state = 
                    TransferProgress(offer!.transferId, bytesWritten, offer!.fileSize);
              }

              if (bytesWritten >= offer!.fileSize) {
                await fileSink!.flush();
                await fileSink!.close();
                print('[TransferService] Download complete!');
                socket.destroy();
                
                // Keep the progress bar visible with a completed state and file path
                ref.read(transferProgressProvider.notifier).state = 
                    TransferProgress(offer!.transferId, bytesWritten, offer!.fileSize, 
                                     status: TransferStatus.completed, filePath: outputFile!.path);
              }
            }
          }
        } catch (e) {
          print('[TransferService] Stream processing error: $e');
          ref.read(transferProgressProvider.notifier).state = 
              TransferProgress(offer?.transferId ?? 'unknown', bytesWritten, offer?.fileSize ?? 0, 
                               status: TransferStatus.error, error: e.toString());
          socket.destroy();
        }
      },
      onDone: () => streamController.complete(),
      onError: (err) {
        print('[TransferService] Socket Error: $err');
        streamController.complete();
      },
      cancelOnError: true,
    );
    
    await streamController.future;
    await fileSink?.close();
  }

  // ── Send File ──────────────────────────────────────────────────────────────

  Future<void> sendFile(Peer peer, File file) async {
    final fileName = file.uri.pathSegments.last;
    final fileSize = await file.length();
    final transferId = _uuid.v4();
    final senderName = Platform.localHostname.isNotEmpty ? Platform.localHostname : 'Android Client';

    ref.read(transferProgressProvider.notifier).state = TransferProgress(transferId, 0, fileSize);

    try {
      final socket = await Socket.connect(peer.ipAddress, peer.port, timeout: const Duration(seconds: 5));
      print('[TransferClient] Connected to ${peer.ipAddress}:${peer.port}');

      final offer = OfferData(
        transferId: transferId,
        fileName: fileName,
        fileSize: fileSize,
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
      if (!accepted) {
        throw Exception('Peer rejected the transfer');
      }

      print('[TransferClient] Offer accepted. Sending $fileSize bytes...');

      final stream = file.openRead();
      int bytesWritten = 0;

      await for (final chunk in stream) {
        socket.add(chunk);
        bytesWritten += chunk.length;

        // Throttle progress updates
        if (bytesWritten % (1024 * 512) < chunk.length || bytesWritten == fileSize) {
            ref.read(transferProgressProvider.notifier).state = 
                TransferProgress(transferId, bytesWritten, fileSize);
        }
      }

      await socket.flush();
      socket.destroy();
      
      print('[TransferClient] Transfer complete!');
      
      ref.read(transferProgressProvider.notifier).state = 
          TransferProgress(transferId, fileSize, fileSize, status: TransferStatus.completed);
          
      Future.delayed(const Duration(seconds: 2), () {
        ref.read(transferProgressProvider.notifier).state = null;
      });

    } catch (e) {
      print('[TransferClient] Error during send: $e');
      ref.read(transferProgressProvider.notifier).state = 
                TransferProgress(transferId, 0, fileSize, status: TransferStatus.error, error: e.toString());
    }
  }
}
