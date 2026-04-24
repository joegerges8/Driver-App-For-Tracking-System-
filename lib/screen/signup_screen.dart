import 'package:delivery_boy_app/provider/auth_provider.dart';
import 'package:delivery_boy_app/route.dart';
import 'package:delivery_boy_app/screen/app_main_screen.dart';
import 'package:delivery_boy_app/utils/colors.dart';
import 'package:delivery_boy_app/widgets/auth_widgets.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

// ─── What this screen does and what changed ──────────────────────────────────
// SignupScreen registers a new driver account with four fields:
// full name, email, phone number, and password.
//
// Fields added / changed from the original design:
//   • Email was added as a required field. It is stored in the database and
//     used as the login credential (drivers now log in with email + password
//     instead of phone + password).
//   • The backend's POST /api/drivers/signup endpoint was updated in parallel
//     to accept and store the email, and a database migration
//     (ALTER TABLE drivers ADD COLUMN email VARCHAR(150) UNIQUE) was run on
//     the production Railway Postgres instance to add the column.
//
// Visual changes from the original design:
//   • The default Material AppBar was removed and replaced with AuthHeader —
//     the same red wave component used on LoginScreen — so both screens share
//     a consistent branded appearance.
//   • The header uses heightFactor 0.32 (vs login's 0.38) so it occupies less
//     vertical space, leaving sufficient room for four input fields without
//     the screen feeling cramped.
//   • All four TextFields were replaced with AuthInputField widgets (defined in
//     auth_widgets.dart): filled background, rounded borders, prefix icons, and
//     a red focus highlight matching the app theme.
//   • The password field gained a show/hide visibility toggle.
//   • A SingleChildScrollView wraps the entire body. This fixes a
//     "BOTTOM OVERFLOWED BY 53 PIXELS" crash that occurred when the soft
//     keyboard appeared and pushed the four-field layout out of bounds.
//   • The "Back to login" TextButton was replaced with an inline
//     "Already have an account? Log In" row for visual consistency with
//     the login screen's sign-up link.
//
// Validation strategy: client-side empty check and email regex run before the
// network call so the driver gets instant feedback without waiting for a round
// trip. The backend validates the same rules again as a second guard.
// ─────────────────────────────────────────────────────────────────────────────

// Signup screen — redesigned to match the login screen's visual style.
// Uses the same shared widgets from auth_widgets.dart (AuthHeader, AuthInputField,
// AuthButton) so both screens stay visually consistent.
// heightFactor 0.32 (vs login's 0.38) gives the header less height to leave
// more room for the four input fields below.
// Validation runs client-side first (empty check + email regex), then the
// backend validates again as a second guard.
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
  bool _obscurePassword = true;

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
      await context.read<AuthProvider>().signup(
            fullName: fullName,
            email: email,
            phone: phone,
            password: password,
          );
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
      // SingleChildScrollView prevents the "BOTTOM OVERFLOWED" error that
      // occurred with a plain Column when the keyboard pushed four fields up.
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Slightly shorter header than login since the form has more fields.
            AuthHeader(
              icon: Icons.person_add_outlined,
              title: 'Create Account',
              subtitle: 'Join the delivery team',
              heightFactor: 0.32,
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(28, 12, 28, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Sign Up',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Fill in your details to get started',
                    style: TextStyle(color: Colors.grey[500], fontSize: 13),
                  ),
                  const SizedBox(height: 24),
                  AuthInputField(
                    controller: _fullNameController,
                    label: 'Full Name',
                    icon: Icons.person_outline,
                    textCapitalization: TextCapitalization.words,
                  ),
                  const SizedBox(height: 14),
                  // autocorrect disabled so the keyboard doesn't mangle email addresses.
                  AuthInputField(
                    controller: _emailController,
                    label: 'Email',
                    icon: Icons.email_outlined,
                    keyboardType: TextInputType.emailAddress,
                    autocorrect: false,
                  ),
                  const SizedBox(height: 14),
                  AuthInputField(
                    controller: _phoneController,
                    label: 'Phone',
                    icon: Icons.phone_outlined,
                    keyboardType: TextInputType.phone,
                  ),
                  const SizedBox(height: 14),
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
                  const SizedBox(height: 28),
                  AuthButton(
                    label: 'Create Account',
                    loading: auth.isBusy,
                    onPressed: _submit,
                  ),
                  const SizedBox(height: 20),
                  // Inline back-to-login link.
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'Already have an account?  ',
                        style: TextStyle(color: Colors.grey[600], fontSize: 14),
                      ),
                      GestureDetector(
                        onTap: auth.isBusy ? null : () => Navigator.pop(context),
                        child: Text(
                          'Log In',
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
