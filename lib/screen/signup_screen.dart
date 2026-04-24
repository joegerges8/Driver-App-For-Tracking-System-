import 'package:delivery_boy_app/provider/auth_provider.dart';
import 'package:delivery_boy_app/route.dart';
import 'package:delivery_boy_app/screen/app_main_screen.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

// Signup screen — collects full name, email, phone, and password.
// Email was added to the form alongside phone so the backend can store and
// display it on the driver's profile. Validation runs client-side first
// (empty check + regex) and the backend validates again as a second guard.
class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _fullNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();

  @override
  void dispose() {
    _fullNameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final fullName = _fullNameController.text.trim();
    final email = _emailController.text.trim();
    final phone = _phoneController.text.trim();
    final password = _passwordController.text;

    if (fullName.isEmpty || email.isEmpty || phone.isEmpty || password.isEmpty) {
      _showError('All fields are required');
      return;
    }

    // Catches obvious typos before the network call so the user gets instant feedback.
    // The backend runs the same check as a second guard.
    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email)) {
      _showError('Enter a valid email address');
      return;
    }

    try {
      await context
          .read<AuthProvider>()
          .signup(fullName: fullName, email: email, phone: phone, password: password);
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
      appBar: AppBar(title: const Text('Driver Signup')),
      // SingleChildScrollView replaces the plain Padding that was here before.
      // When the keyboard appears it pushes the layout up, causing a
      // "BOTTOM OVERFLOWED BY 53 PIXELS" error with four fields. Scrollable
      // body lets the form slide up without clipping.
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: _fullNameController,
              decoration: const InputDecoration(labelText: 'Full name'),
              textCapitalization: TextCapitalization.words,
            ),
            const SizedBox(height: 12),
            // autocorrect: false prevents the keyboard from mangling email addresses.
            TextField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              autocorrect: false,
              decoration: const InputDecoration(labelText: 'Email'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _phoneController,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'Phone'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _passwordController,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Password'),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: auth.isBusy ? null : _submit,
                child: auth.isBusy
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Sign up'),
              ),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: auth.isBusy ? null : () => Navigator.pop(context),
              child: const Text('Back to login'),
            ),
          ],
        ),
      ),
    );
  }
}
