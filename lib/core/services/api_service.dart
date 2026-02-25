import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class ApiService {
  static String _baseUrl = 'http://localhost:8000';

  static String get baseUrl => _baseUrl;

  static Future<void> loadBaseUrl() async {
    final prefs = await SharedPreferences.getInstance();
    _baseUrl = prefs.getString('backend_url') ?? 'http://localhost:8000';
  }

  static Future<void> setBaseUrl(String url) async {
    _baseUrl = url;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('backend_url', url);
  }

  static Future<String?> _getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('auth_token');
  }

  static Future<Map<String, String>> _headers({bool auth = true}) async {
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };
    if (auth) {
      final token = await _getToken();
      if (token != null) {
        headers['Authorization'] = 'Bearer $token';
      }
    }
    return headers;
  }

  static Future<dynamic> get(String path) async {
    final uri = Uri.parse('$_baseUrl$path');
    final response = await http
        .get(uri, headers: await _headers())
        .timeout(const Duration(seconds: 15));
    return _handleResponse(response);
  }

  static Future<dynamic> post(String path, Map<String, dynamic> body,
      {bool auth = true}) async {
    final uri = Uri.parse('$_baseUrl$path');
    final response = await http
        .post(uri,
            headers: await _headers(auth: auth),
            body: jsonEncode(body))
        .timeout(const Duration(seconds: 15));
    return _handleResponse(response);
  }

  static Future<dynamic> put(String path, Map<String, dynamic> body) async {
    final uri = Uri.parse('$_baseUrl$path');
    final response = await http
        .put(uri,
            headers: await _headers(),
            body: jsonEncode(body))
        .timeout(const Duration(seconds: 15));
    return _handleResponse(response);
  }

  static Future<dynamic> delete(String path) async {
    final uri = Uri.parse('$_baseUrl$path');
    final response = await http
        .delete(uri, headers: await _headers())
        .timeout(const Duration(seconds: 15));
    return _handleResponse(response);
  }

  static dynamic _handleResponse(http.Response response) {
    if (response.statusCode >= 200 && response.statusCode < 300) {
      if (response.body.isEmpty) return null;
      return jsonDecode(response.body);
    } else {
      String message = 'Request failed (${response.statusCode})';
      try {
        final body = jsonDecode(response.body);
        message = body['detail'] ?? body['message'] ?? message;
      } catch (_) {}
      throw ApiException(response.statusCode, message);
    }
  }
}

class ApiException implements Exception {
  final int statusCode;
  final String message;
  const ApiException(this.statusCode, this.message);

  @override
  String toString() => message;
}
