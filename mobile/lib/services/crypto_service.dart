import 'dart:convert';
import 'dart:typed_data';
import 'dart:math';
import 'package:pointycastle/export.dart';

class DecryptedChunkResult {
  final Uint8List plaintext;
  final int chunkIndex;
  DecryptedChunkResult(this.plaintext, this.chunkIndex);
}

class CryptoService {
  /// Derive a 256-bit key from session ID using HKDF with SHA-256
  Uint8List deriveKey(String sessionId) {
    final ikm = Uint8List.fromList(utf8.encode(sessionId));
    final salt = Uint8List.fromList(utf8.encode('doctransit-v2'));
    final info = Uint8List.fromList(utf8.encode('file-transfer'));

    // HKDF-Extract
    final hmacExtract = HMac(SHA256Digest(), 64)..init(KeyParameter(salt));
    final prk = Uint8List(hmacExtract.macSize);
    hmacExtract.update(ikm, 0, ikm.length);
    hmacExtract.doFinal(prk, 0);

    // HKDF-Expand
    const outputLength = 32;
    final hmacExpand = HMac(SHA256Digest(), 64)..init(KeyParameter(prk));
    final n = (outputLength + hmacExpand.macSize - 1) ~/ hmacExpand.macSize;
    final okm = Uint8List(n * hmacExpand.macSize);
    var prev = Uint8List(0);

    for (var i = 1; i <= n; i++) {
      hmacExpand.reset();
      hmacExpand.update(prev, 0, prev.length);
      hmacExpand.update(info, 0, info.length);
      final counterByte = Uint8List.fromList([i]);
      hmacExpand.update(counterByte, 0, 1);
      prev = Uint8List(hmacExpand.macSize);
      hmacExpand.doFinal(prev, 0);
      okm.setRange((i - 1) * hmacExpand.macSize, i * hmacExpand.macSize, prev);
    }

    return Uint8List.fromList(okm.sublist(0, outputLength));
  }

  /// Encrypt a chunk using AES-256-GCM
  /// IV: 8 random bytes + 4 bytes from chunkIndex (big-endian)
  /// Returns: IV (12) + ciphertext + authTag (16)
  Uint8List encryptChunk(Uint8List plaintext, Uint8List key, int chunkIndex) {
    final random = Random.secure();
    final iv = Uint8List(12);

    // 8 random bytes
    for (var i = 0; i < 8; i++) {
      iv[i] = random.nextInt(256);
    }

    // 4 bytes from chunkIndex (big-endian)
    iv[8] = (chunkIndex >> 24) & 0xFF;
    iv[9] = (chunkIndex >> 16) & 0xFF;
    iv[10] = (chunkIndex >> 8) & 0xFF;
    iv[11] = chunkIndex & 0xFF;

    final cipher = GCMBlockCipher(AESEngine())
      ..init(
        true,
        AEADParameters(
          KeyParameter(key),
          128, // auth tag length in bits
          iv,
          Uint8List(0), // no AAD
        ),
      );

    final ciphertext = Uint8List(cipher.getOutputSize(plaintext.length));
    final len = cipher.processBytes(plaintext, 0, plaintext.length, ciphertext, 0);
    final finalLen = cipher.doFinal(ciphertext, len);
    final actualCiphertext = ciphertext.sublist(0, len + finalLen);

    // Combine: IV + ciphertext (includes auth tag from GCM)
    final result = Uint8List(12 + actualCiphertext.length);
    result.setRange(0, 12, iv);
    result.setRange(12, result.length, actualCiphertext);

    return result;
  }

  /// Decrypt a chunk using AES-256-GCM
  /// Input: IV (12) + ciphertext + authTag (16) concatenated
  /// Returns DecryptedChunkResult containing plaintext bytes and chunkIndex from IV
  DecryptedChunkResult decryptChunk(Uint8List combined, Uint8List key, int fallbackIndex) {
    final iv = combined.sublist(0, 12);
    final ciphertextWithTag = combined.sublist(12);

    final ivData = ByteData.sublistView(iv);
    final extractedIndex = ivData.getUint32(8, Endian.big);
    final chunkIndex = (extractedIndex >= 0) ? extractedIndex : fallbackIndex;

    final cipher = GCMBlockCipher(AESEngine())
      ..init(
        false,
        AEADParameters(
          KeyParameter(key),
          128,
          iv,
          Uint8List(0),
        ),
      );

    final plaintext = Uint8List(cipher.getOutputSize(ciphertextWithTag.length));
    final len = cipher.processBytes(
      ciphertextWithTag,
      0,
      ciphertextWithTag.length,
      plaintext,
      0,
    );
    final finalLen = cipher.doFinal(plaintext, len);

    return DecryptedChunkResult(plaintext.sublist(0, len + finalLen), chunkIndex);
  }
}
