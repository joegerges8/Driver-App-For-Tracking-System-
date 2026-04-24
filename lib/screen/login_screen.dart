import 'package:delivery_boy_app/provider/auth_provider.dart';
import 'package:delivery_boy_app/route.dart';
import 'package:delivery_boy_app/screen/app_main_screen.dart';
import 'package:delivery_boy_app/screen/signup_screen.dart';
import 'package:delivery_boy_app/utils/colors.dart';
import 'package:delivery_boy_app/widgets/auth_widgets.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

// ─── What this screen does and what changed ──────────────────────────────────
// LoginScreen authenticates a driver using their email address and password.
// Login was previously phone-based; it was changed to email so the credentials
// are consistent with the signup form, which collects email as a required field.
//
// Visual changes from the original design:
//   • The default Material AppBar was removed. The AuthHeader widget (defined in
//     auth_widgets.dart) replaces it with a full-bleed red wave section that
//     fills the top 38% of the screen, giving the screen a strong branded look
//     that matches the app's red colour scheme.
//   • Plain TextFields were replaced with AuthInputField widgets: filled grey
//     background, rounded corners, a coloured prefix icon, and a red focus
//     border — consistent with the rest of the redesigned auth flow.
//   • The password field gained a show/hide visibility toggle so drivers can
//     verify what they typed before submitting.
//   • The "Create an account" TextButton at the bottom was replaced with an
//     inline "Don't have an account? Sign Up" row, which is a common pattern
//     in modern mobile auth screens and is less visually heavy than a button.
//   • A SingleChildScrollView wraps the body so the form scrolls correctly
//     when the soft keyboard appears on smaller devices.
//
// Logic is unchanged: _submit() reads from AuthProvider, which calls
// POST /api/drivers/login and stores the JWT in SharedPreferences.
// ─────────────────────────────────────────────────────────────────────────────

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
