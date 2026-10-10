import 'package:flutter/material.dart';

/// Token warna — sumber: DESIGN.md §4–5. Ubah di sini saja bila palet dashboard
/// final berbeda; jangan menulis hex langsung di widget.
abstract final class AppColors {
  // Brand
  static const primary = Color(0xFF0F4540); // Deep teal: navigasi, judul kuat
  static const secondary = Color(
    0xFF287B72,
  ); // Teal: aksi utama, kontrol terpilih
  static const accent = Color(
    0xFFF47C48,
  ); // Coral: peringatan, penekanan sekunder
  static const primarySoft = Color(0xFFE3F0EE); // Latar kontrol terpilih

  // Permukaan
  static const background = Color(0xFFF7F8F5);
  static const surface = Color(0xFFFFFFFF);
  static const border = Color(0xFFE3E7E2);

  // Teks (bukan hitam murni)
  static const textPrimary = Color(0xFF1B2422);
  static const textSecondary = Color(0xFF5F6B68);

  // Semantik
  static const success = Color(0xFF2F855A); // tersinkron, sehat
  static const warning = accent; // stok menipis, perlu perhatian
  static const danger = Color(0xFFD64545); // gagal, destruktif
  static const info = Color(0xFF2B6CB0);
  static const offline = Color(
    0xFF6B7471,
  ); // netral & tenang, bukan merah (DESIGN.md §33)

  // Latar lembut untuk banner pesan (selalu disertai ikon + teks, bukan warna saja).
  static const dangerSoft = Color(0xFFFDECEC);
  static const infoSoft = Color(0xFFE8F1FA);
}
