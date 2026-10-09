import 'auth_user.dart';

abstract interface class AuthRepository {
  /// Memulihkan sesi dari penyimpanan lokal TANPA jaringan.
  /// Mengembalikan null bila tidak ada sesi yang utuh.
  Future<AuthUser?> restoreSession();

  /// Masuk lewat server. Melempar [ApiException] bila gagal.
  Future<AuthUser> login({required String email, required String password});

  /// Keluar: mencabut token di server bila bisa, lalu SELALU menghapus sesi
  /// lokal. Tidak menghapus database lokal.
  Future<void> logout();

  /// Menghapus sesi lokal saja (mis. token sudah kedaluwarsa di server).
  Future<void> clearSession();
}
