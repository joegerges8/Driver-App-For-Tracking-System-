import 'package:delivery_boy_app/utils/colors.dart';
import 'package:flutter/material.dart';

// Shared widgets used by LoginScreen and SignupScreen.
// Extracted into one file so both screens stay thin and the visual language
// (colours, border radius, wave shape) stays consistent in one place.

// Draws the red wave header that fills the top portion of both auth screens.
// heightFactor is a parameter so login (0.38) and signup (0.32) can use
// different heights — signup needs less room because it has more form fields.
class AuthHeader extends StatelessWidget {
  const AuthHeader({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.heightFactor,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final double heightFactor;

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.of(context).size.height * heightFactor;
    return ClipPath(
      clipper: _WaveClipper(),
      child: Container(
        height: height,
        color: buttonMainColor,
        // SafeArea is inside the container (not outside) so the red background
        // still bleeds into the status bar area while content stays clear of it.
        child: SafeArea(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Semi-transparent circle behind the icon for depth.
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: Colors.white, size: 46),
              ),
              const SizedBox(height: 14),
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.82),
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Clips the bottom of the red header into a gentle upward-bowing wave.
// The quadraticBezierTo control point sits 32px below the container bottom,
// which creates the outward bow. Raising/lowering that value changes how
// pronounced the curve is.
class _WaveClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final path = Path();
    path.lineTo(0, size.height - 48);
    path.quadraticBezierTo(
      size.width / 2,  // control point x — horizontally centred
      size.height + 32, // control point y — below the edge creates the outward bow
      size.width,
      size.height - 48,
    );
    path.lineTo(size.width, 0);
    path.close();
    return path;
  }

  // Shape never changes after first paint, so reclipping is unnecessary.
  @override
  bool shouldReclip(CustomClipper<Path> oldClipper) => false;
}

// Styled input field used across both auth screens.
// Three border variants are defined so Flutter can transition between them:
//   border          — fallback, borderSide.none (never visible)
//   enabledBorder   — subtle grey outline when unfocused
//   focusedBorder   — red outline (buttonMainColor) when the field is active
// suffixIcon is optional — only the password fields pass one (the show/hide toggle).
class AuthInputField extends StatelessWidget {
  const AuthInputField({
    super.key,
    required this.controller,
    required this.label,
    required this.icon,
    this.keyboardType,
    this.obscureText = false,
    this.autocorrect = true,
    this.textCapitalization = TextCapitalization.none,
    this.suffixIcon,
  });

  final TextEditingController controller;
  final String label;
  final IconData icon;
  final TextInputType? keyboardType;
  final bool obscureText;
  final bool autocorrect;
  final TextCapitalization textCapitalization;
  final Widget? suffixIcon;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      obscureText: obscureText,
      autocorrect: autocorrect,
      textCapitalization: textCapitalization,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: buttonMainColor, size: 20),
        suffixIcon: suffixIcon,
        filled: true,
        fillColor: backgroundColor,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.shade200),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: buttonMainColor, width: 1.5),
        ),
        labelStyle: TextStyle(color: Colors.grey[500], fontSize: 14),
        contentPadding:
            const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
      ),
    );
  }
}

// Full-width primary action button shared across both screens.
// disabledBackgroundColor is set explicitly because Flutter's default disabled
// colour ignores the custom backgroundColor, making the button look unstyled
// when auth.isBusy is true.
class AuthButton extends StatelessWidget {
  const AuthButton({
    super.key,
    required this.label,
    required this.onPressed,
    required this.loading,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: buttonMainColor,
          foregroundColor: Colors.white,
          disabledBackgroundColor: buttonMainColor.withValues(alpha: 0.6),
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          elevation: 3,
        ),
        onPressed: loading ? null : onPressed,
        child: loading
            ? const SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : Text(
                label,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
      ),
    );
  }
}
