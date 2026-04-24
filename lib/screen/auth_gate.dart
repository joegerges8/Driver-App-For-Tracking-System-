import 'package:delivery_boy_app/provider/auth_provider.dart';
import 'package:delivery_boy_app/screen/app_main_screen.dart';
import 'package:delivery_boy_app/screen/login_screen.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

// Added in this change:
// Startup screen that decides whether to show auth screens or the main app.
// - If token exists => AppMainScreen
// - Else => LoginScreen
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() => context.read<AuthProvider>().initialize());
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AuthProvider>(
      builder: (context, auth, child) {
        if (!auth.initialized) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (auth.isAuthenticated) {
          return const AppMainScreen();
        }

        return const LoginScreen();
      },
    );
  }
}
