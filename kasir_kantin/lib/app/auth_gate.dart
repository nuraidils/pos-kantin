import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../features/auth/presentation/bloc/auth_bloc.dart';
import '../features/auth/presentation/pages/login_page.dart';
import 'app_shell.dart';

/// Memilih layar berdasarkan status sesi. Hanya membaca state; semua logika
/// ada di AuthBloc.
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AuthBloc, AuthState>(
      builder: (context, state) => switch (state) {
        AuthUnknown() => const _LoadingPage(),
        AuthAuthenticated() => const AppShell(),
        AuthUnauthenticated() || AuthInProgress() || AuthFailure() => const LoginPage(),
      },
    );
  }
}

class _LoadingPage extends StatelessWidget {
  const _LoadingPage();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    );
  }
}
