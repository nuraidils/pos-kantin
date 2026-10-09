/// Validasi form masuk. Server tetap memvalidasi ulang (AGENTS.md §26).
String? validateEmail(String? value) {
  final email = value?.trim() ?? '';
  if (email.isEmpty) return 'Email wajib diisi.';
  if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email)) {
    return 'Format email tidak valid.';
  }
  return null;
}

/// Kata sandi tidak di-trim: spasi bisa menjadi bagian dari kata sandi.
String? validatePassword(String? value) {
  if (value == null || value.isEmpty) return 'Kata sandi wajib diisi.';
  return null;
}
