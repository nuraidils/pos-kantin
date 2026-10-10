import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/error/api_exceptions.dart';
import '../../domain/auth_repository.dart';
import '../../domain/auth_user.dart';

part 'auth_event.dart';
part 'auth_state.dart';

class AuthBloc extends Bloc<AuthEvent, AuthState> {
  AuthBloc({required AuthRepository repository, Stream<void>? sessionExpired})
    : _repository = repository,
      super(const AuthUnknown()) {
    on<AuthStarted>(_onStarted);
    on<AuthLoginSubmitted>(_onLoginSubmitted);
    on<AuthLogoutRequested>(_onLogoutRequested);
    on<AuthSessionExpired>(_onSessionExpired);

    _sessionExpiredSub = sessionExpired?.listen(
      (_) => add(const AuthSessionExpired()),
    );
  }

  final AuthRepository _repository;
  StreamSubscription<void>? _sessionExpiredSub;

  Future<void> _onStarted(AuthStarted event, Emitter<AuthState> emit) async {
    try {
      final user = await _repository.restoreSession();
      emit(
        user == null ? const AuthUnauthenticated() : AuthAuthenticated(user),
      );
    } catch (_) {
      // Penyimpanan aman tidak terbaca: minta masuk ulang, jangan macet di splash.
      emit(const AuthUnauthenticated());
    }
  }

  Future<void> _onLoginSubmitted(
    AuthLoginSubmitted event,
    Emitter<AuthState> emit,
  ) async {
    if (state is AuthInProgress) return; // cegah kirim ganda
    emit(const AuthInProgress());
    try {
      final user = await _repository.login(
        email: event.email,
        password: event.password,
      );
      emit(AuthAuthenticated(user));
    } on ApiException catch (e) {
      emit(_failureFor(e));
    } catch (_) {
      emit(
        const AuthFailure(
          message: 'Terjadi kesalahan yang tidak terduga. Coba lagi.',
        ),
      );
    }
  }

  Future<void> _onLogoutRequested(
    AuthLogoutRequested event,
    Emitter<AuthState> emit,
  ) async {
    try {
      await _repository.logout();
    } catch (_) {
      // Apa pun yang terjadi, pengguna dianggap sudah keluar di aplikasi ini.
    }
    emit(const AuthUnauthenticated());
  }

  Future<void> _onSessionExpired(
    AuthSessionExpired event,
    Emitter<AuthState> emit,
  ) async {
    if (state is! AuthAuthenticated) return;
    try {
      // Token sudah tidak berlaku: cukup hapus sesi lokal, tanpa memanggil
      // API keluar. Transaksi di SQLite tidak disentuh.
      await _repository.clearSession();
    } catch (_) {}
    emit(
      const AuthUnauthenticated(
        message: 'Sesi berakhir. Silakan masuk kembali.',
      ),
    );
  }

  AuthFailure _failureFor(ApiException e) {
    return switch (e) {
      NetworkException() => const AuthFailure(
        message:
            'Tidak dapat terhubung ke internet. '
            'Masuk pertama kali membutuhkan koneksi internet.',
      ),
      UnauthorizedException() => const AuthFailure(
        message: 'Email atau kata sandi salah.',
      ),
      ForbiddenException() => AuthFailure(message: e.message),
      ValidationException(:final errors) => AuthFailure(
        message: 'Periksa kembali data yang Anda isi.',
        fieldErrors: errors,
      ),
      ServerException() => AuthFailure(message: e.message),
      _ => const AuthFailure(
        message: 'Terjadi kesalahan yang tidak terduga. Coba lagi.',
      ),
    };
  }

  @override
  Future<void> close() async {
    await _sessionExpiredSub?.cancel();
    return super.close();
  }
}
