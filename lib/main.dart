import 'package:flutter/material.dart';

// 10.11.2025 Firebase core
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';

// 10.11.2025 auth screens
import 'view/screens/login_screen.dart';
// import 'view/screens/signup_screen.dart';  

// 10.11.2025 main app screens
// import 'view/screens/home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
  options: DefaultFirebaseOptions.currentPlatform,
);
runApp(const MyApp());
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Weather App',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blueAccent),
        useMaterial3: true,
      ),
      home: const LoginScreen(), // pagina de start
      // home: const HomeScreen(), // DEBUG: testare UI pagini
    );
  }
}
