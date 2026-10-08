/// URL dasar API Laravel. Diatur saat build/run, bukan di-hard-code:
///   flutter run --dart-define=API_BASE_URL=http://192.168.1.10:8000/api
/// Default 10.0.2.2 = localhost mesin host dari emulator Android.
abstract final class ApiConstants {
  static const baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:8000/api',
  );
}
