import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/services/api_service.dart';

class AuthUser {
  final int id;
  final String email;
  final String name;

  AuthUser({required this.id, required this.email, required this.name});

  factory AuthUser.fromJson(Map<String, dynamic> json) {
    return AuthUser(
      id: json['id'] as int,
      email: json['email'] as String? ?? '',
      name: json['name'] as String? ?? '',
    );
  }
}

class AuthProvider extends ChangeNotifier {
  String? _token;
  AuthUser? _currentUser;
  bool _isLoading = false;
  String? _error;
  bool _initialized = false;

  String? get token => _token;
  AuthUser? get currentUser => _currentUser;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get isAuthenticated => _token != null;
  bool get initialized => _initialized;

  Future<void> init() async {
    await ApiService.loadBaseUrl();
    final prefs = await SharedPreferences.getInstance();
    _token = prefs.getString('auth_token');
    if (_token != null) {
      try {
        final data = await ApiService.get('/api/v1/auth/me');
        _currentUser = AuthUser.fromJson(data as Map<String, dynamic>);
      } catch (_) {
        // Token expired or invalid – stay as guest
        _token = null;
        await prefs.remove('auth_token');
      }
    }
    _initialized = true;
    notifyListeners();
  }

  Future<bool> login(String email, String password) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final data = await ApiService.post(
        '/api/v1/auth/login',
        {'email': email, 'password': password},
        auth: false,
      );
      _token = data['access_token'] as String;
      _currentUser = AuthUser.fromJson(data['user'] as Map<String, dynamic>);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('auth_token', _token!);
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _error = e.toString();
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> register(String name, String email, String password) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final data = await ApiService.post(
        '/api/v1/auth/register',
        {'name': name, 'email': email, 'password': password},
        auth: false,
      );
      _token = data['access_token'] as String;
      _currentUser = AuthUser.fromJson(data['user'] as Map<String, dynamic>);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('auth_token', _token!);
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _error = e.toString();
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<void> logout() async {
    _token = null;
    _currentUser = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('auth_token');
    notifyListeners();
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }

  // Guest mode – skip auth but still use the app
  void continueAsGuest() {
    _initialized = true;
    notifyListeners();
  }
}
