import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_appauth/flutter_appauth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import 'browser_stub.dart' if (dart.library.js_interop) 'browser.dart';
import 'records.dart';

class ApiFailure implements Exception {
  const ApiFailure(this.status, this.body);
  final int status;
  final String body;

  String? get deletedAccount {
    if (status != 410) return null;
    try {
      final value = jsonDecode(body);
      return value is Map && value['account'] is String
          ? value['account'] as String
          : null;
    } on FormatException {
      return null;
    }
  }
}

class CloudApi {
  static const enabled = bool.fromEnvironment('TEACHER_CLOUD');
  static const _issuer = String.fromEnvironment('OIDC_AUTHORITY');
  static const _client = String.fromEnvironment('OIDC_CLIENT_ID');
  static const _audience = String.fromEnvironment('OIDC_AUDIENCE');
  static const _redirect = 'app.teacherai.classroom:/callback';
  static const _secrets = FlutterSecureStorage(
    mOptions: MacOsOptions(usesDataProtectionKeychain: false),
  );
  static final origin = kIsWeb
      ? Uri.base
      : Uri.parse(const String.fromEnvironment('API_ORIGIN'));
  final http.Client _http = http.Client();
  String? account;
  String generation = 'classroom';
  String? _csrf;
  String? _access;
  DateTime? _expiry;
  Future<void>? _refresh;

  Future<void> signIn() async {
    if (kIsWeb) {
      webLogin();
      return;
    }
    if (origin.scheme != 'https' ||
        !Uri.parse(_issuer).isScheme('https') ||
        _client.isEmpty ||
        _audience.isEmpty) {
      throw StateError(
        'Configure the HTTPS API and identity settings for this build.',
      );
    }
    final result = await const FlutterAppAuth().authorizeAndExchangeCode(
      AuthorizationTokenRequest(
        _client,
        _redirect,
        issuer: _issuer,
        scopes: ['openid', 'profile', 'offline_access'],
        additionalParameters: {'audience': _audience},
        promptValues: ['login'],
      ),
    );
    await _remember(result);
  }

  Future<void> _remember(TokenResponse result) async {
    _access = result.accessToken;
    _expiry = result.accessTokenExpirationDateTime;
    if (result.refreshToken != null) {
      await _secrets.write(key: 'teacher.refresh', value: result.refreshToken);
    }
  }

  Future<void> _renew() async {
    final token = await _secrets.read(key: 'teacher.refresh');
    if (token == null) throw const ApiFailure(401, '');
    try {
      await _remember(
        await const FlutterAppAuth().token(
          TokenRequest(
            _client,
            _redirect,
            issuer: _issuer,
            refreshToken: token,
          ),
        ),
      );
    } on FlutterAppAuthPlatformException catch (error) {
      if (error.platformErrorDetails.error == 'invalid_grant') {
        throw const ApiFailure(401, '');
      }
      rethrow;
    }
  }

  Future<Json> call(String path, {Json? body, bool delete = false}) async {
    if (!kIsWeb &&
        (_access == null ||
            _expiry?.isBefore(
                  DateTime.now().add(const Duration(seconds: 30)),
                ) ==
                true)) {
      await (_refresh ??= _renew().whenComplete(() => _refresh = null));
    }
    final uri = origin.resolve('/api/v1/$path');
    final headers = {
      'X-Workspace-Account': ?account,
      'X-Classroom-Generation': generation,
      if (_access != null) 'Authorization': 'Bearer $_access',
      'X-CSRF': ?_csrf,
      if (body != null) 'Content-Type': 'application/json',
    };
    final response =
        await (delete
                ? _http.delete(uri, headers: headers)
                : body == null
                ? _http.get(uri, headers: headers)
                : _http.post(uri, headers: headers, body: jsonEncode(body)))
            .timeout(const Duration(seconds: 12));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiFailure(response.statusCode, response.body);
    }
    return response.bodyBytes.isEmpty
        ? {}
        : jsonDecode(utf8.decode(response.bodyBytes)) as Json;
  }

  Future<String> identity() async {
    final session = await call('session');
    _csrf = session['csrf'] as String?;
    generation = session['generation'] as String? ?? 'classroom';
    return session['account'] as String;
  }

  Future<void> signOut() async {
    if (kIsWeb) await call('logout', body: {});
    await forgetSession();
  }

  Future<void> forgetSession() async {
    if (!kIsWeb) await _secrets.delete(key: 'teacher.refresh');
    _access = null;
    _csrf = null;
    account = null;
  }

  void dispose() => _http.close();
}
