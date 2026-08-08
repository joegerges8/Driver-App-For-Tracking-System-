import 'package:delivery_boy_app/l10n/app_localizations.dart';
import 'package:delivery_boy_app/provider/auth_provider.dart';
import 'package:delivery_boy_app/provider/delivery_provider.dart';
import 'package:delivery_boy_app/screen/login_screen.dart';
import 'package:delivery_boy_app/utils/colors.dart';
import 'package:delivery_boy_app/widgets/language_toggle.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

// Profile tab — replaces the old Center(child: Text("Profile")) placeholder.
// Layout (top to bottom):
//   _AvatarCard      — driver initials, name, phone from AuthProvider
//   _StatsCard       — total delivery count from DeliveryProvider.orders
//   _SectionCard     — Language toggle (English/العربية) and Change Password
//   Logout button    — confirmation dialog then AuthProvider.logout()
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  @override
  void initState() {
    super.initState();
    // microtask defers the call until after the first build so context is safe to use.
    Future.microtask(_refresh);
  }

  // Kicks off a background profile fetch; safe to call multiple times (AuthProvider guards it).
  void _refresh() {
    final auth = context.read<AuthProvider>();
    if (auth.token != null && auth.token!.isNotEmpty) {
      auth.refreshProfile();
    }
  }

  Future<void> _confirmLogout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.l10n.logOut),
        content: Text(ctx.l10n.logOutConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(ctx.l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              ctx.l10n.logOut,
              style: TextStyle(color: buttonMainColor),
            ),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await context.read<AuthProvider>().logout();
      if (!mounted) return;
      // Bug fix: logout was silently broken because AppMainScreen was pushed
      // with pushReplacement, which removed AuthGate from the navigator stack.
      // AuthGate rebuilding to LoginScreen had no visible effect since it was
      // no longer the active route. pushAndRemoveUntil clears the entire stack
      // and lands on a fresh LoginScreen so the driver is fully signed out.
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (route) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final auth = context.watch<AuthProvider>();
    final delivery = context.watch<DeliveryProvider>();
    final driver = auth.driver;

    // Try both field names since the backend uses full_name but older responses may differ.
    final fullName = (driver?['full_name'] ?? driver?['name'] ?? 'Driver') as String;
    final email = (driver?['email'] ?? '') as String;
    final phone = (driver?['phone'] ?? '—') as String;
    final initials = fullName.trim().isNotEmpty ? fullName.trim()[0].toUpperCase() : 'D';
    final totalOrders = delivery.completedOrders.length;

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        title: Text(l10n.profileTitle),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: RefreshIndicator(
        onRefresh: () async => _refresh(),
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
          children: [
            _AvatarCard(
              initials: initials,
              fullName: fullName,
              email: email,
              phone: phone,
              loading: auth.isRefreshingProfile,
            ),
            const SizedBox(height: 16),
            _StatsCard(totalOrders: totalOrders),
            const SizedBox(height: 16),
            _SectionCard(
              children: [
                // Language switch — flipping it rebuilds the whole app in the
                // chosen language and persists the choice for next launch.
                // A plain Row rather than a ListTile: the segmented toggle is
                // wide, and Expanded on the label lets it give way on narrow
                // screens instead of overflowing the trailing slot.
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
                  child: Row(
                    children: [
                      const Icon(Icons.language),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Text(
                          l10n.language,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const LanguageToggle(),
                    ],
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.lock_outline),
                  title: Text(l10n.changePassword),
                  trailing: const Icon(Icons.chevron_right, size: 18),
                  onTap: () => _showChangePasswordSheet(context),
                ),
              ],
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: buttonMainColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: _confirmLogout,
                child: Text(l10n.logOut, style: const TextStyle(fontSize: 16)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showChangePasswordSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => const _ChangePasswordSheet(),
    );
  }
}

// Top card: red circle with the driver's initial letter, name below, phone below that.
// Shows a spinner in place of the name while AuthProvider is fetching fresh data.
class _AvatarCard extends StatelessWidget {
  const _AvatarCard({
    required this.initials,
    required this.fullName,
    required this.email,
    required this.phone,
    required this.loading,
  });

  final String initials;
  final String fullName;
  final String email;
  final String phone;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
        child: Column(
          children: [
            CircleAvatar(
              radius: 42,
              backgroundColor: buttonMainColor,
              child: Text(
                initials,
                style: const TextStyle(
                  fontSize: 34,
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(height: 14),
            loading
                ? const SizedBox(
                    height: 24,
                    width: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(
                    fullName,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
            const SizedBox(height: 4),
            Text(
              phone,
              style: TextStyle(color: Colors.grey[600], fontSize: 14),
            ),
            // email is nullable in the DB (older drivers won't have one),
            // so only render it when the value is actually present.
            if (email.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                email,
                style: TextStyle(color: Colors.grey[500], fontSize: 13),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// Reads the already-loaded orders list from DeliveryProvider (no extra API call needed).
class _StatsCard extends StatelessWidget {
  const _StatsCard({required this.totalOrders});
  final int totalOrders;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _StatItem(
              label: context.l10n.totalDeliveries,
              value: '$totalOrders',
            ),
          ],
        ),
      ),
    );
  }
}

class _StatItem extends StatelessWidget {
  const _StatItem({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        Text(label, style: TextStyle(color: Colors.grey[600], fontSize: 13)),
      ],
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Column(children: children),
    );
  }
}

// Bottom sheet with three password fields (current, new, confirm).
// Slides up above the keyboard because padding includes viewInsets.bottom.
// The actual API call is stubbed — wire up _submit() once the backend
// exposes POST /api/drivers/me/password.
class _ChangePasswordSheet extends StatefulWidget {
  const _ChangePasswordSheet();

  @override
  State<_ChangePasswordSheet> createState() => _ChangePasswordSheetState();
}

class _ChangePasswordSheetState extends State<_ChangePasswordSheet> {
  final _formKey = GlobalKey<FormState>();
  final _currentCtrl = TextEditingController();
  final _newCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _currentCtrl.dispose();
    _newCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  // Fixed to actually call the backend instead of faking a success.
  // Previously this method had a TODO stub: it waited 800 ms, showed a success
  // snackbar, and closed the sheet — without ever sending the new password to the
  // server, so the password in the database was never changed and the driver would
  // get "Invalid credentials" the next time they tried to log in with the new password.
  //
  // Now it calls AuthProvider.changePassword(), which POSTs to the backend endpoint
  // POST /api/drivers/me/password. On success the sheet closes and a snackbar
  // confirms the update. On failure (e.g. wrong current password) the error message
  // returned by the backend is displayed in red inside the sheet instead of crashing.
  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    // Read the translation before the await: the sheet is popped below, so this
    // context is gone by the time the snackbar text is needed.
    final successMessage = context.l10n.passwordUpdated;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await context.read<AuthProvider>().changePassword(
        currentPassword: _currentCtrl.text,
        newPassword: _newCtrl.text,
      );
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(successMessage)),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 20, 16, 20 + bottom),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.changePassword,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            _PasswordField(
              controller: _currentCtrl,
              label: l10n.currentPassword,
              validator: (v) =>
                  (v == null || v.isEmpty) ? l10n.fieldRequired : null,
            ),
            const SizedBox(height: 12),
            _PasswordField(
              controller: _newCtrl,
              label: l10n.newPassword,
              validator: (v) {
                if (v == null || v.isEmpty) return l10n.fieldRequired;
                if (v.length < 6) return l10n.atLeastSixCharacters;
                return null;
              },
            ),
            const SizedBox(height: 12),
            _PasswordField(
              controller: _confirmCtrl,
              label: l10n.confirmNewPassword,
              validator: (v) =>
                  v != _newCtrl.text ? l10n.passwordsDoNotMatch : null,
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: const TextStyle(color: Colors.red)),
            ],
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: buttonMainColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                onPressed: _loading ? null : _submit,
                child: _loading
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(l10n.updatePassword),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Reusable password input with a show/hide toggle icon on the right.
class _PasswordField extends StatefulWidget {
  const _PasswordField({
    required this.controller,
    required this.label,
    required this.validator,
  });

  final TextEditingController controller;
  final String label;
  final String? Function(String?) validator;

  @override
  State<_PasswordField> createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<_PasswordField> {
  bool _obscure = true;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: widget.controller,
      obscureText: _obscure,
      validator: widget.validator,
      decoration: InputDecoration(
        labelText: widget.label,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        suffixIcon: IconButton(
          icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility),
          onPressed: () => setState(() => _obscure = !_obscure),
        ),
      ),
    );
  }
}
