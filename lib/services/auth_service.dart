import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  static final GoogleSignIn _googleSignIn = GoogleSignIn.instance;
  static Future<void>? _googleInitialization;

  Stream<User?> get authStateChanges => _auth.authStateChanges();
  User? get currentUser => _auth.currentUser;

  Future<User?> signUp(String email, String password) async {
    try {
      UserCredential userCredential = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      return userCredential.user;
    } catch (e) {
      rethrow;
    }
  }

  Future<String?> signIn({required String email, required String password}) async {
    try {
      await _auth.signInWithEmailAndPassword(email: email, password: password);
      return null;
    } on FirebaseAuthException catch (e) {
      return _handleFirebaseAuthError(e);
    } catch (e) {
      return 'An unexpected error occurred: $e';
    }
  }

  Future<UserCredential> signInWithGoogle() async {
    try {
      _googleInitialization ??= _googleSignIn.initialize();
      await _googleInitialization;

      final googleUser = await _googleSignIn.authenticate();
      final googleAuth = googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        idToken: googleAuth.idToken,
      );
      return _auth.signInWithCredential(credential);
    } on FirebaseAuthException {
      rethrow;
    } on GoogleSignInException catch (e) {
      throw FirebaseAuthException(
        code: 'google-sign-in-failed',
        message: e.description ?? 'Autentificarea cu Google a eșuat.',
      );
    }
  }

  Future<void> signOut() async {
    _googleInitialization ??= _googleSignIn.initialize();
    await _googleInitialization;
    await _googleSignIn.signOut();
    await _auth.signOut();
  }

  String _handleFirebaseAuthError(FirebaseAuthException e) {
    switch (e.code) {
      case 'credential-already-in-use':
        return 'This account already exists associated with a different credential.';
      default:
        return e.message ?? 'Authentication error: ${e.code}';
    }
  }

  Future<void> updatePassword(String newPassword) async {
    try {
      await _auth.currentUser?.updatePassword(newPassword);
    } on FirebaseAuthException catch (e) {
      if (e.code == 'requires-recent-login') {
        throw 'Pentru securitate, trebuie să te reloghezi înainte de a schimba parola.';
      }
      throw 'Eroare la schimbarea parolei: ${e.message}';
    } catch (e) {
      throw 'A apărut o eroare neașteptată.';
    }
  }
}

