import 'package:flutter/widgets.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'app/app.dart';
import 'core/database/app_database.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('id_ID');

  // Buka (dan buat bila perlu) database lokal sebelum UI tampil, agar
  // kegagalan skema muncul di awal, bukan saat kasir sedang checkout.
  final database = await AppDatabase.open();

  runApp(App(database: database));
}
