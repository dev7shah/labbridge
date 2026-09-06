import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:path/path.dart' as p;


import '../models/file_item.dart';
import '../models/transfer.dart';
import '../core/config.dart';
import 'crypto_service.dart';
import 'db_service.dart';

enum ConnectionStatus { disconnected, connecting, connected, error }

class TransferProgress {
  final String fileName;
  final int totalBytes;
  final int transferredBytes;
  final int totalChunks;
  final int completedChunks;
  final TransferDirection direction;

  TransferProgress({
    required this.fileName,
    required this.totalBytes,
    required this.transferredBytes,
    required this.totalChunks,
    required this.completedChunks,
    required this.direction,
  });

  double get progress => totalBytes > 0 ? transferredBytes / totalBytes : 0.0;
  String get percentage => '${(progress * 100).toStringAsFixed(1)}%';
}

class TransferService extends ChangeNotifier {
  final CryptoService _cryptoService = CryptoService();
  final DbService _dbService = DbService();
  static const _uuid = Uuid();
  static const int _chunkSize = 512 * 1024; // 512KB
  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;
  Uint8List? _derivedKey;
  String? _currentSessionId;
  String? get currentSessionId => _currentSessionId;

  // Stream controllers for UI updates
  final _connectionStatusController = StreamController<ConnectionStatus>.broadcast();
  final _progressController = StreamController<TransferProgress?>.broadcast();
  final _errorController = StreamController<String>.broadcast();
  final _completionController = StreamController<String>.broadcast();

  Stream<ConnectionStatus> get connectionStatus => _connectionStatusController.stream;
  Stream<TransferProgress?> get progress => _progressController.stream;
  Stream<String> get errors => _errorController.stream;
  Stream<String> get completions => _completionController.stream;

  // State for receiving
  File? _tempFile;
  IOSink? _tempSink;
  final Map<int, Uint8List> _chunkBuffer = {};
  int _receivedChunks = 0;
  int _totalChunks = 0;
  String _currentFileName = '';
  int _currentFileSize = 0;
  String? _targetFolderId;
  int _transferredBytes = 0;
  DateTime? _transferStartTime;

  // State for sending
  bool _isSending = false;
  bool _isConnecting = false;
  Completer<void>? _readyCompleter;
  Completer<int>? _ackCompleter;

  ConnectionStatus _status = ConnectionStatus.disconnected;
  ConnectionStatus get currentStatus => _status;

  /// Connect to the Worker WebSocket
  Future<void> connect(String sessionId, [String? workerUrlOverride]) async {
    if (_isConnecting || _status == ConnectionStatus.connected) return;
    _isConnecting = true;
    _status = ConnectionStatus.connecting;
    _connectionStatusController.add(ConnectionStatus.connecting);
    notifyListeners();
    _currentSessionId = sessionId;

    try {
      final workerUrl = workerUrlOverride ?? await AppConfig.getWorkerUrl();
      // Derive encryption key
      _derivedKey = _cryptoService.deriveKey(sessionId);

      // Build WebSocket URL
      final wsUrl = '$workerUrl/session/$sessionId/phone';
      _channel = WebSocketChannel.connect(Uri.parse(wsUrl));

      await _channel!.ready.timeout(const Duration(seconds: 10));

      _status = ConnectionStatus.connected;
      _connectionStatusController.add(ConnectionStatus.connected);
      notifyListeners();

      // Listen for messages
      _subscription = _channel!.stream.listen(
        _handleMessage,
        onError: (error) {
          _status = ConnectionStatus.error;
          _connectionStatusController.add(ConnectionStatus.error);
          notifyListeners();
          _errorController.add('WebSocket error: $error');
          disconnect(sendSignal: false);
        },
        onDone: () {
          _status = ConnectionStatus.disconnected;
          _connectionStatusController.add(ConnectionStatus.disconnected);
          notifyListeners();
          disconnect(sendSignal: false);
        },
      );

      // Send initial folder tree when connected
      await sendFolderTree();
    } catch (e) {
      _status = ConnectionStatus.error;
      _connectionStatusController.add(ConnectionStatus.error);
      notifyListeners();
      _errorController.add('Connection failed: $e');
    } finally {
      _isConnecting = false;
    }
  }

  void _handleMessage(dynamic message) {
    if (message is String) {
      _handleJsonMessage(message);
    } else if (message is List<int>) {
      _handleBinaryMessage(Uint8List.fromList(message));
    }
  }

  void _handleJsonMessage(String message) {
    try {
      final data = json.decode(message) as Map<String, dynamic>;
      final type = data['type'] as String?;

      switch (type) {
        case 'transfer_init':
          _handleTransferInit(data);
          break;
        case 'folder_request':
          sendFolderTree();
          break;
        case 'ready':
          if (_readyCompleter != null && !_readyCompleter!.isCompleted) {
            _readyCompleter!.complete();
          }
          break;
        case 'ack':
          if (_ackCompleter != null && !_ackCompleter!.isCompleted) {
            final idx = data['chunk_index'] as int? ?? 0;
            _ackCompleter!.complete(idx);
          }
          break;
        case 'disconnected':
          disconnect(sendSignal: false);
          break;
        case 'cancelled':
          if (_ackCompleter != null && !_ackCompleter!.isCompleted) {
            _ackCompleter!.completeError(StateError('cancelled'));
          }
          if (_readyCompleter != null && !_readyCompleter!.isCompleted) {
            _readyCompleter!.completeError(StateError('cancelled'));
          }
          _cancelCurrentReceive(notify: true);
          break;
        case 'error':
          _errorController.add(data['message'] as String? ?? 'Unknown error');
          if (_readyCompleter != null && !_readyCompleter!.isCompleted) _readyCompleter!.completeError(StateError(data['message'] as String? ?? 'Unknown error'));
          if (_ackCompleter != null && !_ackCompleter!.isCompleted) _ackCompleter!.completeError(StateError(data['message'] as String? ?? 'Unknown error'));
          break;
      }
    } catch (e) {
      _errorController.add('Failed to parse message: $e');
    }
  }

  Future<void> _cancelCurrentReceive({bool notify = false}) async {
    _chunkBuffer.clear();
    if (_tempSink != null || _tempFile != null) {
      try {
        await _tempSink?.flush();
        await _tempSink?.close();
      } catch (_) {}
      if (_tempFile != null && await _tempFile!.exists()) {
        try {
          await _tempFile!.delete();
        } catch (_) {}
      }
      _tempSink = null;
      _tempFile = null;
    }
    if (notify) {
      _progressController.add(null);
      notifyListeners();
    }
  }

  Future<void> sendFolderTree() async {
    if (_channel == null) return;
    try {
      final folders = await _dbService.getAllFolders();
      final foldersList = folders.map((f) => {
        'id': f.id,
        'name': f.name,
        'parentId': f.parentId,
        'color': f.color,
      }).toList();
      _channel!.sink.add(json.encode({
        'type': 'folders',
        'folders': foldersList,
      }));
    } catch (e) {
      _errorController.add('Failed to send folder tree: $e');
    }
  }

  Future<void> _handleTransferInit(Map<String, dynamic> data) async {
    if (_tempSink != null || _tempFile != null) {
      _errorController.add('A transfer is already in progress, cancelling previous.');
      await _cancelCurrentReceive(notify: false);
    }

    _currentFileName = data['filename'] as String? ?? 'unknown';
    _currentFileSize = data['size'] as int? ?? 0;
    _totalChunks = data['total_chunks'] as int? ?? 0;
    _targetFolderId = data['folder_id'] as String?;
    _receivedChunks = 0;
    _transferredBytes = 0;
    _transferStartTime = DateTime.now();

    // Prepare temp file
    final tempDir = await getTemporaryDirectory();
    final tempPath = p.join(tempDir.path, 'lb_${_uuid.v4()}_${DateTime.now().millisecondsSinceEpoch}');
    _tempFile = File(tempPath);
    _tempSink = _tempFile!.openWrite();

    // Send ready signal
    _channel?.sink.add(json.encode({'type': 'ready'}));

    _progressController.add(TransferProgress(
      fileName: _currentFileName,
      totalBytes: _currentFileSize,
      transferredBytes: 0,
      totalChunks: _totalChunks,
      completedChunks: 0,
      direction: TransferDirection.received,
    ));
    notifyListeners();
  }

  Future<void> _handleBinaryMessage(Uint8List data) async {
    if (_tempSink == null || _derivedKey == null) return;

    try {
      // Decrypt chunk
      final result = _cryptoService.decryptChunk(data, _derivedKey!, _receivedChunks);
      final decrypted = result.plaintext;
      final chunkIndex = result.chunkIndex;

      // Store chunk in buffer to tolerate out-of-order delivery
      _chunkBuffer[chunkIndex] = decrypted;

      // Flush contiguous chunks to disk
      while (_chunkBuffer.containsKey(_receivedChunks)) {
        final chunkData = _chunkBuffer.remove(_receivedChunks)!;
        _tempSink!.add(chunkData);
        await _tempSink!.flush();
        _receivedChunks++;
        _transferredBytes += chunkData.length;
      }

      if (_receivedChunks >= _totalChunks) {
        final sinkToClose = _tempSink;
        final fileToSave = _tempFile;
        final fileNameToSave = _currentFileName;
        final fileSizeToSave = _currentFileSize;
        final folderIdToSave = _targetFolderId;

        _tempSink = null;
        _tempFile = null;

        // Send ack right after detaching
        _channel?.sink.add(json.encode({
          'type': 'ack',
          'chunk_index': chunkIndex,
        }));

        _progressController.add(TransferProgress(
          fileName: fileNameToSave,
          totalBytes: fileSizeToSave,
          transferredBytes: _transferredBytes,
          totalChunks: _totalChunks,
          completedChunks: _receivedChunks,
          direction: TransferDirection.received,
        ));
        notifyListeners();

        await _finalizeReceive(
          sink: sinkToClose,
          file: fileToSave,
          fileName: fileNameToSave,
          fileSize: fileSizeToSave,
          folderId: folderIdToSave,
        );
      } else {
        // Send ack for non-final chunks
        _channel?.sink.add(json.encode({
          'type': 'ack',
          'chunk_index': chunkIndex,
        }));

        _progressController.add(TransferProgress(
          fileName: _currentFileName,
          totalBytes: _currentFileSize,
          transferredBytes: _transferredBytes,
          totalChunks: _totalChunks,
          completedChunks: _receivedChunks,
          direction: TransferDirection.received,
        ));
        notifyListeners();
      }
    } catch (e) {
      _errorController.add('Decryption failed: $e');
      _channel?.sink.add(json.encode({'type': 'cancelled'}));
      _cancelCurrentReceive(notify: true);
    }
  }

  Future<void> _finalizeReceive({
    IOSink? sink,
    File? file,
    required String fileName,
    required int fileSize,
    String? folderId,
  }) async {
    _chunkBuffer.clear();
    await sink?.flush();
    await sink?.close();

    if (file == null) return;

    try {
      // Move to app documents directory
      final docsDir = await getApplicationDocumentsDirectory();
      final cueFlexDir = Directory(p.join(docsDir.path, 'CueFlex'));
      if (!await cueFlexDir.exists()) {
        await cueFlexDir.create(recursive: true);
      }

      final safeFileName = p.basename(fileName.replaceAll(RegExp(r'[\\/]+'), '_'));
      final targetPath = p.join(cueFlexDir.path, safeFileName);
      if (!p.isWithin(cueFlexDir.path, targetPath)) {
        throw Exception('Invalid file target path');
      }
      final targetFile = await file.copy(targetPath);
      if (await file.exists()) {
        await file.delete();
      }

      // Save to database
      final fileId = _uuid.v4();
      final now = DateTime.now().millisecondsSinceEpoch;

      await _dbService.insertFile(FileItem(
        id: fileId,
        name: safeFileName,
        localPath: targetFile.path,
        size: fileSize,
        folderId: folderId,
        receivedAt: now,
      ));

      await _dbService.insertTransfer(Transfer(
        id: _uuid.v4(),
        fileName: fileName,
        size: fileSize,
        direction: TransferDirection.received,
        status: TransferStatus.completed,
        folderId: folderId,
        completedAt: now,
      ));

      _completionController.add(fileName);
      _progressController.add(null);
      notifyListeners();
    } catch (e) {
      _errorController.add('Failed to save file: $e');
      _progressController.add(null);
    }
  }

  Future<void> sendFile(File file) async {
    if (_channel == null || _derivedKey == null) {
      _errorController.add('Not connected');
      return;
    }
    if (_isSending) {
      _errorController.add('A file transfer is already in progress');
      return;
    }
    
    final fileSize = await file.length();
    if (fileSize > 500 * 1024 * 1024) {
      _errorController.add('File exceeds 500MB limit');
      return;
    }

    _isSending = true;

    final fileName = p.basename(file.path);
    final totalChunks = fileSize == 0 ? 1 : (fileSize / _chunkSize).ceil();

    _readyCompleter = Completer<void>();

    try {
      // Send transfer_init
      _channel!.sink.add(json.encode({
        'type': 'transfer_init',
        'filename': fileName,
        'size': fileSize,
        'total_chunks': totalChunks,
      }));

      _transferStartTime = DateTime.now();

      // Wait for 'ready' signal from server/peer before sending chunks
      await _readyCompleter!.future.timeout(const Duration(seconds: 15));
      _readyCompleter = null;

      // Read and send chunks using RandomAccessFile
      final raf = await file.open(mode: FileMode.read);
      int chunkIndex = 0;
      int transferred = 0;

      try {
        if (fileSize == 0) {
          final encrypted = _cryptoService.encryptChunk(
            Uint8List(0),
            _derivedKey!,
            0,
          );
          _ackCompleter = Completer<int>();
          _channel?.sink.add(encrypted);
          try {
            await _ackCompleter!.future.timeout(const Duration(seconds: 15));
          } on StateError {
            return;
          }
          _ackCompleter = null;
          
          _progressController.add(TransferProgress(
            fileName: fileName,
            totalBytes: 0,
            transferredBytes: 0,
            totalChunks: 1,
            completedChunks: 1,
            direction: TransferDirection.sent,
          ));
          notifyListeners();
        } else {
          while (true) {
            final chunk = await raf.read(_chunkSize);
            if (chunk.isEmpty) break;

            final encrypted = _cryptoService.encryptChunk(
              chunk,
              _derivedKey!,
              chunkIndex,
            );

            _ackCompleter = Completer<int>();
            _channel?.sink.add(encrypted);

            // Wait for peer to ACK this chunk
            try {
              await _ackCompleter!.future.timeout(const Duration(seconds: 15));
            } on StateError {
              // Disconnected intentionally
              return;
            }
            _ackCompleter = null;

            transferred += chunk.length;
            chunkIndex++;

            _progressController.add(TransferProgress(
              fileName: fileName,
              totalBytes: fileSize,
              transferredBytes: transferred,
              totalChunks: totalChunks,
              completedChunks: chunkIndex,
              direction: TransferDirection.sent,
            ));
            notifyListeners();
          }
        }
      } finally {
        await raf.close();
      }

      // Record transfer as completed
      final now = DateTime.now().millisecondsSinceEpoch;
      await _dbService.insertTransfer(Transfer(
        id: _uuid.v4(),
        fileName: fileName,
        size: fileSize,
        direction: TransferDirection.sent,
        status: TransferStatus.completed,
        completedAt: now,
      ));

      _completionController.add(fileName);
      _progressController.add(null);
      notifyListeners();
    } catch (e) {
      // Record transfer as failed
      final now = DateTime.now().millisecondsSinceEpoch;
      await _dbService.insertTransfer(Transfer(
        id: _uuid.v4(),
        fileName: fileName,
        size: fileSize,
        direction: TransferDirection.sent,
        status: TransferStatus.failed,
        completedAt: now,
      ));
      _errorController.add('Transfer failed: $e');
      _progressController.add(null);
      notifyListeners();
      rethrow;
    } finally {
      _isSending = false;
      _readyCompleter = null;
      _ackCompleter = null;
    }
  }

  /// Set the target folder for incoming files
  void setTargetFolder(String? folderId) {
    _targetFolderId = folderId;
  }

  /// Calculate transfer speed in bytes per second
  double getTransferSpeed() {
    if (_transferStartTime == null || _transferredBytes == 0) return 0;
    final elapsed = DateTime.now().difference(_transferStartTime!).inMilliseconds;
    if (elapsed == 0) return 0;
    return _transferredBytes / (elapsed / 1000);
  }

  /// Disconnect from WebSocket
  Future<void> disconnect({bool sendSignal = true}) async {
    if (sendSignal && _channel != null) {
      try {
        _channel!.sink.add(json.encode({'type': 'disconnected'}));
      } catch (_) {}
    }
    await _subscription?.cancel();
    _subscription = null;
    await _channel?.sink.close();
    _channel = null;
    _derivedKey = null;
    _currentSessionId = null;

    if (_readyCompleter != null && !_readyCompleter!.isCompleted) {
      _readyCompleter!.completeError(StateError('Disconnected'));
    }
    if (_ackCompleter != null && !_ackCompleter!.isCompleted) {
      _ackCompleter!.completeError(StateError('Disconnected'));
    }
    _readyCompleter = null;
    _ackCompleter = null;
    _isSending = false;

    _chunkBuffer.clear();
    if (_tempSink != null || _tempFile != null) {
      try {
        await _tempSink?.flush();
        await _tempSink?.close();
      } catch (_) {}
      if (_tempFile != null && await _tempFile!.exists()) {
        try {
          await _tempFile!.delete();
        } catch (_) {}
      }
      _tempSink = null;
      _tempFile = null;
    }

    _status = ConnectionStatus.disconnected;
    _connectionStatusController.add(ConnectionStatus.disconnected);
    _progressController.add(null);
    notifyListeners();
  }

  /// Clean up resources
  @override
  void dispose() {
    _subscription?.cancel();
    _subscription = null;
    _channel?.sink.close();
    _channel = null;
    _derivedKey = null;
    _currentSessionId = null;

    if (_readyCompleter != null && !_readyCompleter!.isCompleted) {
      _readyCompleter!.completeError(StateError('Disposed'));
    }
    if (_ackCompleter != null && !_ackCompleter!.isCompleted) {
      _ackCompleter!.completeError(StateError('Disposed'));
    }
    _readyCompleter = null;
    _ackCompleter = null;
    _tempSink?.close();
    _tempSink = null;
    _tempFile = null;
    _status = ConnectionStatus.disconnected;
    _connectionStatusController.close();
    _progressController.close();
    _errorController.close();
    _completionController.close();
    super.dispose();
  }
}
