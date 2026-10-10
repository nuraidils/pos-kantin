import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../core/database/app_database.dart';
import '../core/theme/app_theme.dart';
import '../features/auth/domain/auth_repository.dart';
import '../features/auth/presentation/bloc/auth_bloc.dart';
import '../features/products/domain/catalog_repository.dart';
import 'auth_gate.dart';

class App extends StatelessWidget {
  const App({
    super.key,
    required this.database,
    required this.authRepository,
    required this.catalogRepository,
    this.sessionExpired,
  });

  final AppDatabase database;
  final AuthRepository authRepository;
  final CatalogRepository catalogRepository;

  /// Event 401 dari ApiClient; AuthBloc mengakhiri sesi saat menerimanya.
  final Stream<void>? sessionExpired;

  @override
  Widget build(BuildContext context) {
    // Repository dibuat di composition root (main.dart) dan disediakan di
    // sini; widget tidak menyentuh database atau API langsung.
    return MultiRepositoryProvider(
      providers: [
        RepositoryProvider<AppDatabase>.value(value: database),
        RepositoryProvider<CatalogRepository>.value(value: catalogRepository),
      ],
      child: BlocProvider<AuthBloc>(
        create: (_) =>
            AuthBloc(repository: authRepository, sessionExpired: sessionExpired)
              ..add(const AuthStarted()),
        child: MaterialApp(
          title: 'Kasir Kantin',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light,
          locale: const Locale('id'),
          supportedLocales: const [Locale('id')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: const AuthGate(),
        ),
      ),
    );
  }
}
