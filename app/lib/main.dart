import 'package:flutter/material.dart';
import 'api.dart';
import 'theme.dart';
import 'screens/start.dart';
import 'screens/home.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Session.instance.load();
  runApp(const FlockrApp());
}

class FlockrApp extends StatelessWidget {
  const FlockrApp({super.key});

  @override
  Widget build(BuildContext context) {
    final s = Session.instance;
    return MaterialApp(
      title: 'Flockr',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      home: s.token != null && s.tripId != null ? const HomeScreen() : const StartScreen(),
    );
  }
}
