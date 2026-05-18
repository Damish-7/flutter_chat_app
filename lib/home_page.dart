import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'chat_page.dart';
import 'notification_service.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  @override
  void initState() {
    super.initState();
    // Initialize notifications after user is confirmed logged in
    NotificationService().initialize();
  }

  @override
  Widget build(BuildContext context) {
    return const ChatPage();
  }
}