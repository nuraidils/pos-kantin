import 'dart:async';
import 'dart:convert';

import '../../../core/error/api_exceptions.dart';
import '../../../core/storage/session_storage.dart';
import '../domain/auth_repository.dart';
import '../domain/auth_user.dart';
import 'auth_remote_data_source.dart';

class AuthRepositoryImpl implements AuthRepository {
  AuthRepositoryImpl({
    required AuthRemoteDataSource remote,
    required SessionStorage storage,
    this.logoutTimeout = const Duration(seconds: 3),
  })  : _remote = remote,
        _storage = storage;

  /// Server menghapus token lama dengan nama perangkat yang sama saat login
  /// ulang, jadi dua HP dengan akun yang sama akan saling mengeluarkan.
  /// Cukup untuk MVP satu perangkat per kasir.
  static const _deviceName = 'kasir-mobile';

  final AuthRemoteDataSource _remote;
  final SessionStorage _storage;
  final Duration logoutTimeout;

  @override
  Future<AuthUser?> restoreSession() async {
    final token = await _storage.readToken();
    final rawUser = await _storage.readUser();

    if (token == null || rawUser == null) {
      // Sesi setengah jadi (mis. aplikasi mati saat menyimpan): bersihkan.
      if (token != null || rawUser != null) await _storage.clear();
      return null;
    }

    final user = _parseUser(rawUser);
    if (user == null) await _storage.clear();
    return user;
  }

  @override
  Future<AuthUser> login({required String email, required String password}) async {
    final result = await _remote.login(
      email: email.trim(),
      password: password,
      deviceName: _deviceName,
    );
    await _storage.saveSession(
      token: result.token,
      user: jsonEncode(result.user.toJson()),
    );
    return result.user;
  }

  @override
  Future<void> logout() async {
    // Pencabutan token di server bersifat best-effort: saat offline, kasir
    // tetap harus bisa keluar. Token yang gagal dicabut tetap hilang dari
    // perangkat ini.
    try {
      await _remote.logout().timeout(logoutTimeout);
    } on ApiException {
      // diabaikan: sesi lokal tetap dihapus di bawah
    } on TimeoutException {
      // diabaikan
    }
    await _storage.clear();
  }

  @override
  Future<void> clearSession() => _storage.clear();

  AuthUser? _parseUser(String raw) {
    try {
      return AuthUser.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    }
  }
}
