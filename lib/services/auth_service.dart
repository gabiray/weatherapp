import 'package:firebase_auth/firebase_auth.dart';
// import 'package:google_sign_in/google_sign_in.dart'; // <--- 1. Import Nou

class AuthService {
  // Instanța FirebaseAuth
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // --- GOOGLE SIGN-IN ---
  // final GoogleSignIn _googleSignIn = GoogleSignIn(); // <--- 2. Instanță GoogleSignIn

  // Flux de autentificare
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

  // --- METODA NOUĂ PENTRU GOOGLE ---
  /*
  Future<User?> signInWithGoogle() async {
    try {
      // A. Deschide fereastra de login Google
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      
      // Dacă utilizatorul a dat "Cancel" la fereastră
      if (googleUser == null) return null;

      // B. Obține token-urile de autentificare de la Google
      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;

      // C. Creează o credențială pentru Firebase
      final AuthCredential credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      // D. Autentifică-te în Firebase cu acea credențială
      final UserCredential userCredential = await _auth.signInWithCredential(credential);
      
      return userCredential.user;
    } catch (e) {
      print("Eroare la Google Sign In: $e");
      return null;
    }
  }
  */

  Future<void> signOut() async {
    // await _googleSignIn.signOut(); // <--- Important: Deconectează și Google
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

