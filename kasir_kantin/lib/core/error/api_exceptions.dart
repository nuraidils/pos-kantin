/// Galat API dipisah menurut penanganannya (AGENTS.md §17).
sealed class ApiException implements Exception {
  const ApiException(this.message);

  final String message;

  /// Aman dicoba ulang nanti tanpa mengubah data lokal.
  bool get isRetryable => this is NetworkException || this is ServerException;

  @override
  String toString() => '$runtimeType: $message';
}

/// Tanpa internet, timeout, DNS gagal. Biasanya bisa dicoba ulang.
final class NetworkException extends ApiException {
  const NetworkException([
    super.message = 'Tidak dapat terhubung ke internet.',
  ]);
}

/// 401 — token kedaluwarsa/tidak valid. Perlu masuk ulang.
final class UnauthorizedException extends ApiException {
  const UnauthorizedException([
    super.message = 'Sesi berakhir. Silakan masuk kembali.',
  ]);
}

/// 403 — akun tidak berhak.
final class ForbiddenException extends ApiException {
  const ForbiddenException([
    super.message = 'Akun ini tidak memiliki akses.',
  ]);
}

/// 422 — permintaan tidak valid. Jangan dicoba ulang terus-menerus.
final class ValidationException extends ApiException {
  const ValidationException(super.message, {this.errors = const {}});

  final Map<String, List<String>> errors;
}

/// 409 — konflik bisnis, mis. stok server tidak mencukupi.
final class ConflictException extends ApiException {
  const ConflictException(super.message, {this.body = const {}});

  final Map<String, dynamic> body;
}

/// 5xx — gangguan server. Simpan lokal, coba lagi nanti.
final class ServerException extends ApiException {
  const ServerException([
    super.message = 'Terjadi masalah pada server. Coba lagi beberapa saat.',
  ]);
}

/// Respons lain yang tidak diharapkan.
final class UnexpectedApiException extends ApiException {
  const UnexpectedApiException([
    super.message = 'Terjadi kesalahan yang tidak terduga.',
  ]);
}
