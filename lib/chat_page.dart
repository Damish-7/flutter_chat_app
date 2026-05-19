import 'package:flutter/material.dart';
import 'users_page.dart';
import 'notification_service.dart';
import 'presence_service.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  @override
  void initState() {
    super.initState();
    NotificationService().initialize();
    PresenceService.setOnline();
  }

  @override
  Widget build(BuildContext context) {
    return const UsersPage();
  }
}