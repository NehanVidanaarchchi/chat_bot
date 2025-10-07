import 'package:flutter/material.dart';
import 'screens/chat_screen.dart';

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Heart Assistant',
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF6C63FF),
        useMaterial3: true,
      ),
      home: const HomePage(),
      debugShowCheckedModeBanner: false,
    );
  }
}

/// Simple homepage with floating chatbot button
class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Heart Assistant')),
      body: Stack(
        children: [
          // Your main content
          const Center(
            child: Text(
              'Welcome to Heart Assistant 💙\nPress the chat button to begin.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 18, height: 1.5),
            ),
          ),

          // Floating chat button (bottom-right)
          const ChatbotLauncherButton(),
        ],
      ),
    );
  }
}
