import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/user_model.dart';
import '../services/firebase_service.dart';

class AuthRepository {
  AuthRepository({
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
  })  : _auth = auth ?? FirebaseService.auth,
        _firestore = firestore ?? FirebaseService.firestore;

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;

  Stream<User?> authStateChanges() => _auth.authStateChanges();

  User? get currentFirebaseUser => _auth.currentUser;

  Future<UserModel?> loadCurrentUser() async {
    final firebaseUser = _auth.currentUser;
    if (firebaseUser == null) {
      return null;
    }
    return _readOrCreateUser(firebaseUser);
  }

  Future<UserModel> signUp({
    required String name,
    required String email,
    required String password,
  }) async {
    final normalizedEmail = email.trim().toLowerCase();
    final credential = await _auth.createUserWithEmailAndPassword(
      email: normalizedEmail,
      password: password,
    );
    final user = credential.user;
    if (user == null) {
      throw const AuthException(
        'Account was created but no user session was found.',
      );
    }

    await user.updateDisplayName(name.trim());
    final model = UserModel(
      uid: user.uid,
      name: name.trim(),
      email: normalizedEmail,
      createdAt: DateTime.now(),
    );
    await _users.doc(user.uid).set(model.toMap());
    return model;
  }

  Future<UserModel> signIn({
    required String email,
    required String password,
  }) async {
    final credential = await _auth.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
    final user = credential.user;
    if (user == null) {
      throw const AuthException('Signed in, but no user session was found.');
    }
    return _readOrCreateUser(user);
  }

  Future<void> signOut() {
    return _auth.signOut();
  }

  CollectionReference<Map<String, dynamic>> get _users {
    return _firestore.collection('users');
  }

  Future<UserModel> _readOrCreateUser(User firebaseUser) async {
    final doc = await _users.doc(firebaseUser.uid).get();
    if (doc.exists && doc.data() != null) {
      return UserModel.fromMap(doc.data()!);
    }

    final fallback = UserModel(
      uid: firebaseUser.uid,
      name: firebaseUser.displayName?.trim().isNotEmpty == true
          ? firebaseUser.displayName!.trim()
          : firebaseUser.email?.split('@').first ?? 'Student',
      email: firebaseUser.email?.trim().toLowerCase() ?? '',
      createdAt: DateTime.now(),
    );
    await _users.doc(firebaseUser.uid).set(fallback.toMap());
    return fallback;
  }
}

class AuthException implements Exception {
  const AuthException(this.message);

  final String message;

  @override
  String toString() => message;
}
