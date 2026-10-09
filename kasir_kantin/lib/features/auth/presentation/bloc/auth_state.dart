part of 'auth_bloc.dart';

sealed class AuthState extends Equatable {
  const AuthState();

  @override
  List<Object?> get props => [];
}

/// Sesi lokal sedang diperiksa saat aplikasi dibuka.
final class AuthUnknown extends AuthState {
  const AuthUnknown();
}

/// Belum masuk. [message] terisi bila sesi berakhir, agar bisa dijelaskan.
final class AuthUnauthenticated extends AuthState {
  const AuthUnauthenticated({this.message});

  final String? message;

  @override
  List<Object?> get props => [message];
}

/// Permintaan masuk sedang diproses (cegah kirim ganda).
final class AuthInProgress extends AuthState {
  const AuthInProgress();
}

final class AuthFailure extends AuthState {
  const AuthFailure({required this.message, this.fieldErrors = const {}});

  final String message;
  final Map<String, List<String>> fieldErrors;

  @override
  List<Object?> get props => [message, fieldErrors];
}

final class AuthAuthenticated extends AuthState {
  const AuthAuthenticated(this.user);

  final AuthUser user;

  @override
  List<Object?> get props => [user];
}
