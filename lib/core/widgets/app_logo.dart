import 'package:flutter/material.dart';

class AppLogo extends StatelessWidget {
  const AppLogo({super.key, this.height = 32, this.card = false});

  final double height;
  final bool card;

  /// Builds the app logo interface.
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final image = Image.asset(
      'assets/images/tarumt_logo.png',
      height: height,
      fit: BoxFit.contain,
      errorBuilder: (context, error, stackTrace) =>
          Icon(Icons.school_rounded, size: height, color: scheme.primary),
    );

    if (!card) return image;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: height * 0.5,
        vertical: height * 0.32,
      ),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: scheme.shadow.withValues(alpha: 0.08),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: image,
    );
  }
}
