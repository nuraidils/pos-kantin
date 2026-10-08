import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../core/database/app_database.dart';
import '../core/theme/app_theme.dart';
import 'app_shell.dart';

class App extends StatelessWidget {
  const App({super.key, required this.database});

  final AppDatabase database;

  @override
  Widget build(BuildContext context) {
    // Repository tiap fitur dibuat di sini pada tahap berikutnya (data source
    // memakai `database`); widget tidak pernah menyentuh database langsung.
    return RepositoryProvider<AppDatabase>.value(
      value: database,
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
        home: const AppShell(),
      ),
    );
  }
}
