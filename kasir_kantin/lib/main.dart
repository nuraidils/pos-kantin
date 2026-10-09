import 'package:flutter/widgets.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'app/app.dart';
import 'core/constants/api_constants.dart';
import 'core/database/app_database.dart';
import 'core/network/api_client.dart';
import 'core/storage/session_storage.dart';
import 'features/auth/data/auth_remote_data_source.dart';
import 'features/auth/data/auth_repository_impl.dart';

/// Composition root: semua dependensi dirangkai di sini, satu kali.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('id_ID');

  // Buka (dan buat bila perlu) database lokal sebelum UI tampil, agar
  // kegagalan skema muncul di awal, bukan saat kasir sedang checkout.
  final database = await AppDatabase.open();

  final sessionStorage = SessionStorage();
  final apiClient = ApiClient(
    baseUrl: ApiConstants.baseUrl,
    tokenProvider: sessionStorage.readToken,
  );
  final authRepository = AuthRepositoryImpl(
    remote: AuthRemoteDataSource(apiClient),
    storage: sessionStorage,
  );

  runApp(
    App(
      database: database,
      authRepository: authRepository,
      sessionExpired: apiClient.unauthorized,
    ),
  );
}
