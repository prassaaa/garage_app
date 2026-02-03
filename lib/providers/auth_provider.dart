import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../services/auth_service.dart';

enum AuthState {
  initial,
  authenticated,
  unauthenticated,
  loading,
  error,
}

class AuthProvider extends ChangeNotifier {
  final AuthService _authService;

  AuthState _state = AuthState.initial;
  User? _user;
  String? _errorMessage;
  StreamSubscription<User?>? _authSubscription;

  AuthProvider(this._authService) {
    _init();
  }

  AuthState get state => _state;
  User? get user => _user;
  String? get errorMessage => _errorMessage;
  bool get isAuthenticated => _state == AuthState.authenticated;

  void _init() {
    _authSubscription = _authService.authStateChanges.listen((user) {
      _user = user;
      if (user != null) {
        _state = AuthState.authenticated;
      } else {
        _state = AuthState.unauthenticated;
      }
      notifyListeners();
    });
  }

  Future<bool> signIn(String email, String password) async {
    _state = AuthState.loading;
    _errorMessage = null;
    notifyListeners();

    try {
      await _authService.signIn(email, password);
      return true;
    } catch (e) {
      _state = AuthState.error;
      _errorMessage = e.toString();
      notifyListeners();
      return false;
    }
  }

  Future<void> signOut() async {
    await _authService.signOut();
  }

  void clearError() {
    _errorMessage = null;
    if (_state == AuthState.error) {
      _state = AuthState.unauthenticated;
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }
}
