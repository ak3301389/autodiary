import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../services/auth_service.dart';

class AuthProvider extends ChangeNotifier {
  final AuthService _auth = AuthService();
  User? _user;
  bool _loading = false;

  User? get user => _user;
  bool get loading => _loading;
  bool get isSignedIn => _user != null;

  AuthProvider() {
    _user = _auth.currentUser;
    _auth.authStateChanges.listen((user) {
      _user = user;
      notifyListeners();
    });
  }

  Future<bool> signInWithGoogle() async {
    _loading = true;
    notifyListeners();
    try {
      final user = await _auth.signInWithGoogle();
      _user = user;
      return user != null;
    } catch (e) {
      debugPrint('Ошибка входа: $e');
      return false;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> signOut() async {
    await _auth.signOut();
    _user = null;
    notifyListeners();
  }
}
