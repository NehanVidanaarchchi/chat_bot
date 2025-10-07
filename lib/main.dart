
import 'package:flutter/material.dart';
import 'screens/chat_screen.dart';

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Heart Assistant',
      theme: ThemeData(colorSchemeSeed: const Color(0xFF6C63FF), useMaterial3: true),
      home: const ChatScreen(),
    );
  }
}
