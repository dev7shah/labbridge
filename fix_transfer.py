import re

with open('mobile/lib/services/transfer_service.dart', 'r') as f:
    content = f.read()

# 1. Add _ackedChunks
content = content.replace('  bool _isSending = false;', '  bool _isSending = false;\n  int _ackedChunks = 0;')

# 2. Update ack handler
ack_old = """        case 'ack':
          if (_ackCompleter != null && !_ackCompleter!.isCompleted) {
            final idx = data['chunk_index'] as int? ?? 0;
            _ackCompleter!.complete(idx);
          }
          break;"""
ack_new = """        case 'ack':
          if (_isSending) {
            _ackedChunks++;
          }
          break;"""
content = content.replace(ack_old, ack_new)

# 3. Add _isSending = false to peer_disconnected
peer_old = """        case 'peer_disconnected':
          _errorController.add('PC disconnected. Waiting for reconnect...');"""
peer_new = """        case 'peer_disconnected':
          _isSending = false;
          _errorController.add('PC disconnected. Waiting for reconnect...');"""
content = content.replace(peer_old, peer_new)

# 4. Add _isSending = false to cancelled
cancel_old = """        case 'cancelled':
          if (_ackCompleter != null && !_ackCompleter!.isCompleted) {"""
cancel_new = """        case 'cancelled':
          _isSending = false;
          if (_ackCompleter != null && !_ackCompleter!.isCompleted) {"""
content = content.replace(cancel_old, cancel_new)

# 5. Add _isSending = false to error
err_old = """        case 'error':
          _errorController.add(data['message'] as String? ?? 'Unknown error');"""
err_new = """        case 'error':
          _isSending = false;
          _errorController.add(data['message'] as String? ?? 'Unknown error');"""
content = content.replace(err_old, err_new)

# 6. Replace sendFile block
send_old = """      try {
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
      }"""

send_new = """      try {
        _ackedChunks = 0;
        if (fileSize == 0) {
          final encrypted = _cryptoService.encryptChunk(Uint8List(0), _derivedKey!, 0);
          _channel?.sink.add(encrypted);
        } else {
          while (chunkIndex < totalChunks) {
            while (chunkIndex - _ackedChunks >= 16) {
              await Future.delayed(const Duration(milliseconds: 10));
              if (!_isSending) return;
            }
            if (!_isSending) return;

            final chunk = await raf.read(_chunkSize);
            if (chunk.isEmpty) break;

            final encrypted = _cryptoService.encryptChunk(
              chunk,
              _derivedKey!,
              chunkIndex,
            );

            _channel?.sink.add(encrypted);

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
        
        // Wait for all chunks to be acknowledged
        int watchdog = 0;
        while (_ackedChunks < totalChunks) {
          await Future.delayed(const Duration(milliseconds: 50));
          if (!_isSending) return;
          watchdog += 50;
          if (watchdog > 15000) {
            _errorController.add('Transfer stalled waiting for acks');
            return;
          }
        }
        
        if (fileSize == 0) {
          _progressController.add(TransferProgress(
            fileName: fileName,
            totalBytes: 0,
            transferredBytes: 0,
            totalChunks: 1,
            completedChunks: 1,
            direction: TransferDirection.sent,
          ));
          notifyListeners();
        }
      } finally {
        await raf.close();
      }"""

content = content.replace(send_old, send_new)

with open('mobile/lib/services/transfer_service.dart', 'w') as f:
    f.write(content)
