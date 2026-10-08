import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Token Sanctum disimpan di penyimpanan aman platform, bukan di SQLite
/// dan bukan di SharedPreferences (AGENTS.md §26).
class SessionStorage {
  SessionStorage([FlutterSecureStorage? storage])
      : _storage = storage ?? const FlutterSecureStorage();

  static const _tokenKey = 'auth_token';

  final FlutterSecureStorage _storage;

  Future<String?> readToken() => _storage.read(key: _tokenKey);

  Future<void> saveToken(String token) => _storage.write(key: _tokenKey, value: token);

  Future<void> clear() => _storage.delete(key: _tokenKey);
}
