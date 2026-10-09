import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Token Sanctum dan profil pengguna disimpan di penyimpanan aman platform,
/// bukan di SQLite dan bukan di SharedPreferences (AGENTS.md §26).
/// Profil disimpan agar aplikasi bisa dibuka OFFLINE tanpa menunggu server.
class SessionStorage {
  SessionStorage([FlutterSecureStorage? storage])
      : _storage = storage ?? const FlutterSecureStorage();

  static const _tokenKey = 'auth_token';
  static const _userKey = 'auth_user';

  final FlutterSecureStorage _storage;

  Future<String?> readToken() => _storage.read(key: _tokenKey);

  /// Profil pengguna sebagai JSON string.
  Future<String?> readUser() => _storage.read(key: _userKey);

  Future<void> saveSession({required String token, required String user}) async {
    await _storage.write(key: _tokenKey, value: token);
    await _storage.write(key: _userKey, value: user);
  }

  /// Hanya menghapus sesi. Database lokal (transaksi) TIDAK disentuh
  /// (AGENTS.md Rule 6).
  Future<void> clear() async {
    await _storage.delete(key: _tokenKey);
    await _storage.delete(key: _userKey);
  }
}
