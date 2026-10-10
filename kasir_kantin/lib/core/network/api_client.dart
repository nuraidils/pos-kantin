import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../error/api_exceptions.dart';

/// Klien HTTP tipis untuk API Laravel. Hanya dipanggil dari remote data source,
/// tidak pernah dari widget atau BLoC (AGENTS.md §4.3).
class ApiClient {
  ApiClient({
    required this.baseUrl,
    required this.tokenProvider,
    http.Client? httpClient,
    this.timeout = const Duration(seconds: 15),
  }) : _http = httpClient ?? http.Client();

  final String baseUrl;
  final Future<String?> Function() tokenProvider;
  final Duration timeout;
  final http.Client _http;
  final _unauthorizedController = StreamController<void>.broadcast();

  /// Memancarkan event setiap kali server menjawab 401 pada permintaan yang
  /// berlaku untuk sesi aktif (token kedaluwarsa/dicabut). AuthBloc
  /// mendengarkan ini untuk mengakhiri sesi. Login/logout memakai
  /// `reportUnauthorized: false` karena 401 di sana bukan "sesi berakhir".
  Stream<void> get unauthorized => _unauthorizedController.stream;

  Future<Map<String, dynamic>> get(
    String path, {
    Map<String, String>? query,
    bool reportUnauthorized = true,
  }) {
    return _send(
      'GET',
      path,
      query: query,
      reportUnauthorized: reportUnauthorized,
    );
  }

  Future<Map<String, dynamic>> post(
    String path, {
    Map<String, dynamic>? body,
    bool reportUnauthorized = true,
  }) {
    return _send(
      'POST',
      path,
      body: body,
      reportUnauthorized: reportUnauthorized,
    );
  }

  void close() {
    _unauthorizedController.close();
    _http.close();
  }

  Future<Map<String, dynamic>> _send(
    String method,
    String path, {
    Map<String, String>? query,
    Map<String, dynamic>? body,
    required bool reportUnauthorized,
  }) async {
    final uri = Uri.parse('$baseUrl$path').replace(queryParameters: query);
    final token = await tokenProvider();

    final request = http.Request(method, uri)
      ..headers['Accept'] = 'application/json'
      ..headers[HttpHeaders.contentTypeHeader] = 'application/json';
    if (token != null) request.headers['Authorization'] = 'Bearer $token';
    if (body != null) request.body = jsonEncode(body);

    final http.Response response;
    try {
      final streamed = await _http.send(request).timeout(timeout);
      response = await http.Response.fromStream(streamed).timeout(timeout);
    } on TimeoutException {
      throw const NetworkException(
        'Koneksi terlalu lama. Periksa internet Anda.',
      );
    } on SocketException {
      throw const NetworkException();
    } on http.ClientException {
      throw const NetworkException();
    }

    return _handle(response, reportUnauthorized: reportUnauthorized);
  }

  Map<String, dynamic> _handle(
    http.Response response, {
    required bool reportUnauthorized,
  }) {
    final status = response.statusCode;
    final json = _decode(response.body);
    final serverMessage = json['message'] as String?;

    if (status >= 200 && status < 300) return json;

    switch (status) {
      case 401:
        if (reportUnauthorized && !_unauthorizedController.isClosed) {
          _unauthorizedController.add(null);
        }
        throw UnauthorizedException(
          serverMessage ?? 'Sesi berakhir. Silakan masuk kembali.',
        );
      case 403:
        throw ForbiddenException(
          serverMessage ?? 'Akun ini tidak memiliki akses.',
        );
      case 409:
        throw ConflictException(
          serverMessage ?? 'Data tidak dapat diterapkan.',
          body: json,
        );
      case 422:
        throw ValidationException(
          serverMessage ?? 'Data tidak valid.',
          errors: _parseErrors(json['errors']),
        );
      default:
        if (status >= 500) throw const ServerException();
        throw UnexpectedApiException(
          serverMessage ?? 'Terjadi kesalahan yang tidak terduga.',
        );
    }
  }

  Map<String, dynamic> _decode(String body) {
    if (body.isEmpty) return const {};
    try {
      final decoded = jsonDecode(body);
      return decoded is Map<String, dynamic> ? decoded : const {};
    } on FormatException {
      return const {};
    }
  }

  Map<String, List<String>> _parseErrors(Object? raw) {
    if (raw is! Map) return const {};
    return raw.map(
      (key, value) => MapEntry(
        key.toString(),
        value is List ? value.map((e) => e.toString()).toList() : <String>[],
      ),
    );
  }
}
