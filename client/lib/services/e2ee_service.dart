import 'dart:convert';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// End-to-end encryption: ключи хранятся только на устройстве пользователя.
/// X25519 (ECDH) + HKDF + AES-256-GCM.
class E2EEService {
  static const _storageKeyPair = 'e2ee_keypair';
  static const _prefix = 'e2ee:';
  static const _aesKeyLen = 32;

  final FlutterSecureStorage _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  final X25519 _x25519 = X25519();
  final AesGcm _aes = AesGcm.with256bits();

  /// Возвращает публичный ключ (base64). Приватный сохраняется в secure storage.
  Future<String> ensureKeyPair() async {
    final existing = await _storage.read(key: _storageKeyPair);
    if (existing != null && existing.isNotEmpty) {
      final parts = existing.split(':');
      if (parts.length == 2) return parts[1];
    }
    final keyPair = await _x25519.newKeyPair();
    final privBytes = await keyPair.extractPrivateKeyBytes();
    final pubKey = await keyPair.extractPublicKey();
    final pubBytes = pubKey.bytes;
    final stored = '${base64Encode(privBytes)}:${base64Encode(pubBytes)}';
    await _storage.write(key: _storageKeyPair, value: stored);
    return base64Encode(pubBytes);
  }

  Future<SimpleKeyPair?> _loadKeyPair() async {
    final existing = await _storage.read(key: _storageKeyPair);
    if (existing == null || existing.isEmpty) return null;
    try {
      final parts = existing.split(':');
      if (parts.length != 2) return null;
      final privBytes = base64Decode(parts[0]);
      final pubBytes = base64Decode(parts[1]);
      return SimpleKeyPairData(
        privBytes,
        publicKey: SimplePublicKey(pubBytes, type: KeyPairType.x25519),
        type: KeyPairType.x25519,
      );
    } catch (_) {
      return null;
    }
  }

  /// Зашифровать текст для получателя (его публичный ключ в base64). Возвращает "e2ee:" + base64 или null.
  Future<String?> encrypt(String plaintext, String? recipientPublicKeyBase64) async {
    if (recipientPublicKeyBase64 == null || recipientPublicKeyBase64.isEmpty) return null;
    final keyPair = await _loadKeyPair();
    if (keyPair == null) return null;
    try {
      final theirPublic = SimplePublicKey(base64Decode(recipientPublicKeyBase64), type: KeyPairType.x25519);
      final sharedSecret = await _x25519.sharedSecretKey(keyPair: keyPair as KeyPair, remotePublicKey: theirPublic);
      final sharedBytes = Uint8List.fromList(await sharedSecret.extractBytes());
      final aesKeyBytes = await _hkdf(sharedBytes, _aesKeyLen);
      final secretKey = SecretKey(aesKeyBytes);
      final nonce = _aes.newNonce();
      final secretBox = await _aes.encrypt(
        plaintext.codeUnits,
        secretKey: secretKey,
        nonce: nonce,
      );
      final combined = Uint8List(nonce.length + secretBox.cipherText.length + secretBox.mac.bytes.length);
      combined.setRange(0, nonce.length, nonce);
      combined.setRange(nonce.length, nonce.length + secretBox.cipherText.length, secretBox.cipherText);
      combined.setRange(nonce.length + secretBox.cipherText.length, combined.length, secretBox.mac.bytes);
      return _prefix + base64Encode(combined);
    } catch (_) {
      return null;
    }
  }

  /// Расшифровать текст от отправителя (его публичный ключ в base64). Возвращает plaintext или null.
  Future<String?> decrypt(String content, String? senderPublicKeyBase64) async {
    if (senderPublicKeyBase64 == null || senderPublicKeyBase64.isEmpty) return null;
    if (!content.startsWith(_prefix)) return null;
    final keyPair = await _loadKeyPair();
    if (keyPair == null) return null;
    try {
      final theirPublic = SimplePublicKey(base64Decode(senderPublicKeyBase64), type: KeyPairType.x25519);
      final sharedSecret = await _x25519.sharedSecretKey(keyPair: keyPair as KeyPair, remotePublicKey: theirPublic);
      final sharedBytes = Uint8List.fromList(await sharedSecret.extractBytes());
      final aesKeyBytes = await _hkdf(sharedBytes, _aesKeyLen);
      final secretKey = SecretKey(aesKeyBytes);
      final raw = content.substring(_prefix.length);
      final combined = base64Decode(raw);
      const nonceLen = 12;
      const macLen = 16;
      if (combined.length < nonceLen + macLen) return null;
      final nonce = combined.sublist(0, nonceLen);
      final mac = Mac(combined.sublist(combined.length - macLen));
      final cipherText = combined.sublist(nonceLen, combined.length - macLen);
      final secretBox = SecretBox(cipherText, nonce: nonce, mac: mac);
      final decrypted = await _aes.decrypt(secretBox, secretKey: secretKey);
      return String.fromCharCodes(decrypted is Uint8List ? decrypted : Uint8List.fromList(decrypted));
    } catch (_) {
      return null;
    }
  }

  bool isEncrypted(String content) => content.startsWith(_prefix);

  /// Зашифровать байты (файл, голос, видео) для получателя. Формат: "E2EE" + nonce + ciphertext + tag.
  Future<Uint8List?> encryptBytes(Uint8List plaintext, String? recipientPublicKeyBase64) async {
    if (recipientPublicKeyBase64 == null || recipientPublicKeyBase64.isEmpty) return null;
    final keyPair = await _loadKeyPair();
    if (keyPair == null) return null;
    try {
      final theirPublic = SimplePublicKey(base64Decode(recipientPublicKeyBase64), type: KeyPairType.x25519);
      final sharedSecret = await _x25519.sharedSecretKey(keyPair: keyPair as KeyPair, remotePublicKey: theirPublic);
      final sharedBytes = Uint8List.fromList(await sharedSecret.extractBytes());
      final aesKeyBytes = await _hkdfBytes(sharedBytes, _aesKeyLen);
      final secretKey = SecretKey(aesKeyBytes);
      final nonce = _aes.newNonce();
      final secretBox = await _aes.encrypt(plaintext, secretKey: secretKey, nonce: nonce);
      const magic = [0x45, 0x32, 0x45, 0x45]; // "E2EE"
      return Uint8List.fromList([
        ...magic,
        ...nonce,
        ...secretBox.cipherText,
        ...secretBox.mac.bytes,
      ]);
    } catch (_) {
      return null;
    }
  }

  /// Расшифровать байты вложения. otherPublicKey: для своих сообщений — publicKey получателя, для входящих — отправителя.
  Future<Uint8List?> decryptBytes(Uint8List ciphertext, String? otherPublicKeyBase64) async {
    if (otherPublicKeyBase64 == null || otherPublicKeyBase64.isEmpty) return null;
    if (ciphertext.length < 4 + 12 + 16) return null;
    const magic = [0x45, 0x32, 0x45, 0x45];
    if (ciphertext[0] != magic[0] || ciphertext[1] != magic[1] || ciphertext[2] != magic[2] || ciphertext[3] != magic[3]) {
      return null;
    }
    final keyPair = await _loadKeyPair();
    if (keyPair == null) return null;
    try {
      final theirPublic = SimplePublicKey(base64Decode(otherPublicKeyBase64), type: KeyPairType.x25519);
      final sharedSecret = await _x25519.sharedSecretKey(keyPair: keyPair as KeyPair, remotePublicKey: theirPublic);
      final sharedBytes = Uint8List.fromList(await sharedSecret.extractBytes());
      final aesKeyBytes = await _hkdfBytes(sharedBytes, _aesKeyLen);
      final secretKey = SecretKey(aesKeyBytes);
      const nonceLen = 12;
      const macLen = 16;
      final nonce = ciphertext.sublist(4, 4 + nonceLen);
      final mac = Mac(ciphertext.sublist(ciphertext.length - macLen));
      final enc = ciphertext.sublist(4 + nonceLen, ciphertext.length - macLen);
      final secretBox = SecretBox(enc, nonce: nonce, mac: mac);
      final dec = await _aes.decrypt(secretBox, secretKey: secretKey);
      return Uint8List.fromList(dec);
    } catch (_) {
      return null;
    }
  }

  static Future<Uint8List> _hkdf(Uint8List ikm, int length) async {
    final h = Hkdf(hmac: Hmac.sha256(), outputLength: length);
    final out = await h.deriveKey(
      secretKey: SecretKey(ikm),
      nonce: Uint8List(0),
      info: Uint8List.fromList('e2ee-message-v1'.codeUnits),
    );
    return Uint8List.fromList(await out.extractBytes());
  }

  static Future<Uint8List> _hkdfBytes(Uint8List ikm, int length) async {
    final h = Hkdf(hmac: Hmac.sha256(), outputLength: length);
    final out = await h.deriveKey(
      secretKey: SecretKey(ikm),
      nonce: Uint8List(0),
      info: Uint8List.fromList('e2ee-file-v1'.codeUnits),
    );
    return Uint8List.fromList(await out.extractBytes());
  }
}
