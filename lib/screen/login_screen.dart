import 'package:delivery_boy_app/provider/auth_provider.dart';
import 'package:delivery_boy_app/route.dart';
import 'package:delivery_boy_app/screen/app_main_screen.dart';
import 'package:delivery_boy_app/screen/signup_screen.dart';
import 'package:delivery_boy_app/utils/colors.dart';
import 'package:delivery_boy_app/widgets/auth_widgets.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

// Login screen — redesigned with a red wave header and styled input fields.
// The AppBar is removed so the full-bleed AuthHeader acts as the visual title.
// All three shared widgets (AuthHeader, AuthInputField, AuthButton) come from
// auth_widgets.dart so the design stays in sync with SignupScreen.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    if (email.isEmpty || password.isEmpty) {
      _showError('Email and password are required');
      return;
    }

    try {
      await context.read<AuthProvider>().login(email: email, password: password);
      if (!mounted) return;
      NavigationHelper.pushReplacement(context, const AppMainScreen());
    } catch (e) {
      if (!mounted) return;
      _showError(e.toString());
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message.replaceFirst('Exception: ', ''))),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    return Scaffold(
      backgroundColor: Colors.white,
      // No AppBar — AuthHeader replaces it with the red wave section.
      // SingleChildScrollView prevents overflow when the keyboard appears.
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AuthHeader(
              icon: Icons.local_shipping_outlined,
              title: 'Driver Portal',
              subtitle: 'Welcome back',
              heightFactor: 0.38,
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(28, 12, 28, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Sign In',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Enter your credentials to continue',
                    style: TextStyle(color: Colors.grey[500], fontSize: 13),
                  ),
                  const SizedBox(height: 28),
                  AuthInputField(
                    controller: _emailController,
                    label: 'Email',
                    icon: Icons.email_outlined,
                    keyboardType: TextInputType.emailAddress,
                    autocorrect: false,
                  ),
                  const SizedBox(height: 16),
                  // Password field with show/hide toggle.
                  AuthInputField(
                    controller: _passwordController,
                    label: 'Password',
                    icon: Icons.lock_outline,
                    obscureText: _obscurePassword,
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePassword
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                        color: Colors.grey,
                        size: 20,
                      ),
                      onPressed: () =>
                          setState(() => _obscurePassword = !_obscurePassword),
                    ),
                  ),
                  const SizedBox(height: 32),
                  AuthButton(
                    label: 'Log In',
                    loading: auth.isBusy,
                    onPressed: _submit,
                  ),
                  const SizedBox(height: 20),
                  // Inline sign-up link instead of a separate TextButton row.
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        "Don't have an account?  ",
                        style: TextStyle(color: Colors.grey[600], fontSize: 14),
                      ),
                      GestureDetector(
                        onTap: auth.isBusy
                            ? null
                            : () => NavigationHelper.push(
                                context, const SignupScreen()),
                        child: Text(
                          'Sign Up',
                          style: TextStyle(
                            color: buttonMainColor,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
