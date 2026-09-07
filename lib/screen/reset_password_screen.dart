import 'package:delivery_boy_app/l10n/app_localizations.dart';
import 'package:delivery_boy_app/provider/auth_provider.dart';
import 'package:delivery_boy_app/utils/colors.dart';
import 'package:delivery_boy_app/widgets/auth_widgets.dart';
import 'package:delivery_boy_app/widgets/language_toggle.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

// Forgot password, reached from the login screen.
//
// A driver with no session proves the account is theirs by giving the email
// and the phone number they signed up with, and picks a new password in the
// same step. Nothing else about the account changes: the backend overwrites
// the stored password hash and leaves the driver's name, phone, orders and
// history exactly as they were.
//
// The phone is compared by its digits on the backend, so '+961 70 218 542',
// '70218542' and '03 719 871' are all the same number — the driver does not
// have to remember which way they wrote it at signup.
//
// Same visual language as the login and signup screens: the shared AuthHeader,
// AuthInputField and AuthButton from auth_widgets.dart.
class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({super.key, this.initialEmail = ''});

  /// Whatever the driver had already typed into the login screen's email
  /// field, so they do not type it twice.
  final String initialEmail;

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  late final TextEditingController _emailController =
      TextEditingController(text: widget.initialEmail);
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _obscurePassword = true;
  bool _loading = false;

  @override
  void dispose() {
    _emailController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final l10n = context.l10n;
    final email = _emailController.text.trim();
    final phone = _phoneController.text.trim();
    final password = _passwordController.text;
    final confirm = _confirmController.text;

    // The same client-side checks as signup, so a typo is caught before the
    // round trip and before it counts against the backend's attempt limit.
    if (email.isEmpty || phone.isEmpty || password.isEmpty || confirm.isEmpty) {
      _showError(l10n.allFieldsRequired);
      return;
    }
    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email)) {
      _showError(l10n.enterValidEmail);
      return;
    }
    if (password.length < 6) {
      _showError(l10n.atLeastSixCharacters);
      return;
    }
    if (password != confirm) {
      _showError(l10n.passwordsDoNotMatch);
      return;
    }

    // Read before the await: this screen is popped on success, and the
    // snackbar has to be shown on the login screen underneath it.
    final doneMessage = l10n.passwordResetDone;

    setState(() => _loading = true);
    try {
      await context.read<AuthProvider>().resetForgottenPassword(
            email: email,
            phone: phone,
            newPassword: password,
          );
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(doneMessage)),
      );
    } catch (e) {
      if (!mounted) return;
      _showError(e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message.replaceFirst('Exception: ', ''))),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Scaffold(
      backgroundColor: Colors.white,
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                AuthHeader(
                  icon: Icons.lock_reset,
                  title: l10n.resetPassword,
                  subtitle: l10n.driverPortal,
                  heightFactor: 0.32,
                ),
                Positioned(
                  top: 0,
                  right: 0,
                  left: 0,
                  child: SafeArea(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.arrow_back, color: Colors.white),
                          tooltip: l10n.backToLogin,
                          onPressed: _loading ? null : () => Navigator.pop(context),
                        ),
                        const Padding(
                          padding: EdgeInsets.only(top: 4, right: 8, left: 8),
                          child: LanguageSwitchButton(),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(28, 12, 28, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.resetPassword,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    l10n.resetPasswordHint,
                    style: TextStyle(
                      color: Colors.grey[600],
                      fontSize: 13,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 24),
                  AuthInputField(
                    controller: _emailController,
                    label: l10n.email,
                    icon: Icons.email_outlined,
                    keyboardType: TextInputType.emailAddress,
                    autocorrect: false,
                  ),
                  const SizedBox(height: 14),
                  AuthInputField(
                    controller: _phoneController,
                    label: l10n.phone,
                    icon: Icons.phone_outlined,
                    keyboardType: TextInputType.phone,
                  ),
                  const SizedBox(height: 14),
                  AuthInputField(
                    controller: _passwordController,
                    label: l10n.newPassword,
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
                  const SizedBox(height: 14),
                  AuthInputField(
                    controller: _confirmController,
                    label: l10n.confirmNewPassword,
                    icon: Icons.lock_outline,
                    obscureText: _obscurePassword,
                  ),
                  const SizedBox(height: 28),
                  AuthButton(
                    label: l10n.resetPasswordButton,
                    loading: _loading,
                    onPressed: _submit,
                  ),
                  const SizedBox(height: 20),
                  Center(
                    child: GestureDetector(
                      onTap: _loading ? null : () => Navigator.pop(context),
                      child: Text(
                        l10n.backToLogin,
                        style: TextStyle(
                          color: buttonMainColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ),
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
