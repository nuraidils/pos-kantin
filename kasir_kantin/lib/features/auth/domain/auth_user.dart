import 'package:equatable/equatable.dart';

/// Pengguna yang sedang masuk. `role` hanya untuk tampilan: otorisasi
/// sebenarnya selalu diputuskan server (AGENTS.md §8).
class AuthUser extends Equatable {
  const AuthUser({
    required this.id,
    required this.name,
    required this.email,
    required this.role,
  });

  factory AuthUser.fromJson(Map<String, dynamic> json) {
    return AuthUser(
      id: json['id'] as int,
      name: json['name'] as String,
      email: json['email'] as String,
      role: json['role'] as String,
    );
  }

  final int id;
  final String name;
  final String email;
  final String role;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'email': email,
    'role': role,
  };

  @override
  List<Object?> get props => [id, name, email, role];
}
