part of 'auth_bloc.dart';

sealed class AuthEvent extends Equatable {
  const AuthEvent();

  @override
  List<Object?> get props => [];
}

/// Aplikasi dibuka: pulihkan sesi lokal (tanpa jaringan).
final class AuthStarted extends AuthEvent {
  const AuthStarted();
}

final class AuthLoginSubmitted extends AuthEvent {
  const AuthLoginSubmitted({required this.email, required this.password});

  final String email;
  final String password;

  @override
  List<Object?> get props => [email, password];
}

final class AuthLogoutRequested extends AuthEvent {
  const AuthLogoutRequested();
}

/// Server menjawab 401 pada sesi aktif.
final class AuthSessionExpired extends AuthEvent {
  const AuthSessionExpired();
}
