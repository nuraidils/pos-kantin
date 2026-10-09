import '../../../core/error/api_exceptions.dart';
import '../../../core/network/api_client.dart';
import '../domain/auth_user.dart';

typedef LoginResult = ({String token, AuthUser user});

class AuthRemoteDataSource {
  AuthRemoteDataSource(this._client);

  final ApiClient _client;

  Future<LoginResult> login({
    required String email,
    required String password,
    required String deviceName,
  }) async {
    // 401 di sini = kredensial salah, bukan sesi berakhir -> tidak dilaporkan.
    final json = await _client.post(
      '/auth/login',
      body: {'email': email, 'password': password, 'device_name': deviceName},
      reportUnauthorized: false,
    );

    try {
      final data = json['data'] as Map<String, dynamic>;
      return (
        token: data['token'] as String,
        user: AuthUser.fromJson(data['user'] as Map<String, dynamic>),
      );
    } on TypeError {
      throw const UnexpectedApiException('Respons server tidak sesuai harapan.');
    }
  }

  Future<void> logout() async {
    await _client.post('/auth/logout', reportUnauthorized: false);
  }
}
