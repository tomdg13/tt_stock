import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

const defaultBaseUrl =
    'https://dehome.ldblao.la/atm-api/v1/endpointAtmstock/api';

/// true while a user is signed in; main.dart listens to this.
final ValueNotifier<bool> loggedIn = ValueNotifier(false);

/// Debug console log of every request / response. Filter the run console with:  [API]
void apiLog(String m) {
  if (kDebugMode) debugPrint('[API] $m');
}

String apiClip(String s, [int n = 800]) => s.length <= n ? s : '${s.substring(0, n)}... (${s.length} chars)';

class ApiException implements Exception {
  final int status;
  final String message;
  ApiException(this.status, this.message);
  @override
  String toString() => message;
}

class Api {
  static String baseUrl = defaultBaseUrl;
  static String? token;
  static Map<String, dynamic>? user;

  static Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    baseUrl = p.getString('baseUrl') ?? defaultBaseUrl;
    token = p.getString('token');
    final u = p.getString('user');
    if (u != null) {
      try {
        user = Map<String, dynamic>.from(jsonDecode(u));
      } catch (_) {}
    }
    loggedIn.value = token != null;
  }

  static Future<void> saveBaseUrl(String url) async {
    baseUrl = url.trim().replaceAll(RegExp(r'/+$'), '');
    final p = await SharedPreferences.getInstance();
    await p.setString('baseUrl', baseUrl);
  }

  static Future<void> logout() async {
    token = null;
    user = null;
    final p = await SharedPreferences.getInstance();
    await p.remove('token');
    await p.remove('user');
    loggedIn.value = false;
  }

  /// UI hint only. The server enforces permissions on every route.
  static bool can(String perm) {
    final perms = user?['permissions'] ?? user?['perms'];
    if (perms is List) {
      return perms.contains(perm) || user?['role'] == 'admin';
    }
    return true;
  }

  static Future<dynamic> _send(String method, String path,
      [Object? body]) async {
    final uri = Uri.parse('$baseUrl$path');
    final headers = <String, String>{
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
    final enc = body == null ? null : jsonEncode(body);
    final sw = Stopwatch()..start();
    final hide = path.startsWith('/auth'); // never print PIN / token
    apiLog('-> $method $uri${enc == null ? '' : '\n      body: ${hide ? '<hidden>' : apiClip(enc)}'}');
    http.Response res;
    try {
      Future<http.Response> req;
      switch (method) {
        case 'POST':
          req = http.post(uri, headers: headers, body: enc);
          break;
        case 'PUT':
          req = http.put(uri, headers: headers, body: enc);
          break;
        case 'DELETE':
          req = http.delete(uri, headers: headers);
          break;
        default:
          req = http.get(uri, headers: headers);
      }
      res = await req.timeout(const Duration(seconds: 20));
    } catch (e) {
      apiLog('xx $method $uri  $e');
      throw ApiException(
          0, 'Cannot reach the server. Check your network and server URL.');
    }

    apiLog('<- ${res.statusCode} $method $path (${sw.elapsedMilliseconds} ms)\n      ${hide ? '<hidden>' : apiClip(utf8.decode(res.bodyBytes, allowMalformed: true))}');
    dynamic data;
    try {
      data = res.bodyBytes.isEmpty ? null : jsonDecode(utf8.decode(res.bodyBytes));
    } catch (_) {
      data = null;
    }

    if (res.statusCode == 401 && token != null && path != '/auth/login') {
      await logout();
      throw ApiException(401, 'Session expired. Please sign in again.');
    }
    if (res.statusCode >= 400) {
      var msg = 'Error ${res.statusCode}';
      if (data is Map && data['message'] != null) {
        final m = data['message'];
        msg = m is List ? m.join('\n') : m.toString();
      }
      throw ApiException(res.statusCode, msg);
    }
    return data;
  }

  static Future<dynamic> get(String path) => _send('GET', path);
  static Future<dynamic> post(String path, Object body) =>
      _send('POST', path, body);
  static Future<dynamic> put(String path, Object body) =>
      _send('PUT', path, body);
  static Future<dynamic> delete(String path) => _send('DELETE', path);

  static Future<void> login(String phone, String pin) async {
    final d = await _send('POST', '/auth/login', {'phone': phone, 'pin': pin});
    final t = d is Map ? (d['token'] ?? d['accessToken'] ?? d['access_token']) : null;
    if (t == null) throw ApiException(0, 'Login response has no token.');
    token = t.toString();
    user = d['user'] is Map ? Map<String, dynamic>.from(d['user']) : null;
    final p = await SharedPreferences.getInstance();
    await p.setString('token', token!);
    if (user != null) await p.setString('user', jsonEncode(user));
    loggedIn.value = true;
  }
}
