import 'package:flutter/material.dart';
import 'chat_page.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    // Go straight to chat — AuthGate already confirmed user is logged in
    return const ChatPage();
  }
}