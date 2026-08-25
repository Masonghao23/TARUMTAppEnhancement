import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_logo.dart';
import '../../parking/presentation/vehicle_management_section.dart';
import '../data/models.dart';
import '../providers.dart';
import 'device_binding_section.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(currentProfileProvider);

    return profileAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) =>
          Center(child: Text('Failed to load profile: $error')),
      data: (profile) {
        if (profile == null) {
          return const Center(child: Text('No profile found.'));
        }
        return _ProfileBody(profile: profile);
      },
    );
  }
}

class _ProfileBody extends StatelessWidget {
  const _ProfileBody({required this.profile});

  final Profile profile;

  Color _roleColor(ColorScheme scheme) {
    switch (profile.role) {
      case UserRole.admin:
        return scheme.error;
      case UserRole.staff:
        return scheme.tertiary;
      case UserRole.student:
        return scheme.primary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final roleColor = _roleColor(scheme);

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
      children: [
        _IdCard(profile: profile, roleColor: roleColor),
        const SizedBox(height: 20),
        Text('Account details', style: textTheme.titleMedium),
        const SizedBox(height: 10),
        Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Column(
              children: [
                _InfoRow(
                  icon: Icons.badge_outlined,
                  label: 'Campus ID',
                  value: profile.campusId,
                ),
                const Divider(indent: 56, height: 1),
                _InfoRow(
                  icon: Icons.mail_outline,
                  label: 'Email',
                  value: profile.email,
                ),
                if (profile.rfidUid != null) ...[
                  const Divider(indent: 56, height: 1),
                  _InfoRow(
                    icon: Icons.nfc,
                    label: 'RFID UID',
                    value: profile.rfidUid!,
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        Text('Device binding', style: textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(
          'Attendance can only be marked from your bound device. '
          'Re-binding is limited to once every 7 days.',
          style: textTheme.bodyMedium,
        ),
        const SizedBox(height: 10),
        const DeviceBindingSection(),
        const SizedBox(height: 20),
        Text('Vehicles', style: textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(
          'Register a vehicle plate to reserve parking slots.',
          style: textTheme.bodyMedium,
        ),
        const SizedBox(height: 10),
        const VehicleManagementSection(),
      ],
    );
  }
}

/// The profile header styled like a physical campus ID card — accent edge,
/// small crest mark, role chip, and a decorative barcode strip. Purely
/// visual: the barcode encodes nothing and isn't scannable.
class _IdCard extends StatelessWidget {
  const _IdCard({required this.profile, required this.roleColor});

  final Profile profile;
  final Color roleColor;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return ClipRRect(
      borderRadius: BorderRadius.circular(AppTheme.radiusLg),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              scheme.surfaceContainerHigh,
              scheme.primary.withValues(alpha: 0.10),
            ],
          ),
          border: Border(left: BorderSide(color: scheme.primary, width: 6)),
        ),
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const AppLogo(height: 18),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: roleColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(AppTheme.radiusPill),
                  ),
                  child: Text(
                    profile.role.name.toUpperCase(),
                    style: TextStyle(
                      color: roleColor,
                      fontWeight: FontWeight.w800,
                      fontSize: 11,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                CircleAvatar(
                  radius: 28,
                  backgroundColor: scheme.primary,
                  child: Text(
                    profile.name.isNotEmpty
                        ? profile.name[0].toUpperCase()
                        : '?',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: scheme.onPrimary,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        profile.name.isEmpty ? '(No name set)' : profile.name,
                        style: textTheme.titleLarge,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'ID ${profile.campusId}',
                        style: textTheme.bodyMedium?.copyWith(
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            SizedBox(
              height: 22,
              child: CustomPaint(painter: _BarcodePainter(scheme.onSurface)),
            ),
          ],
        ),
      ),
    );
  }
}

class _BarcodePainter extends CustomPainter {
  _BarcodePainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color.withValues(alpha: 0.5);
    // A fixed, arbitrary pattern of bar widths/heights — decorative only.
    const weights = [
      1.0,
      0.5,
      0.8,
      0.3,
      1.0,
      0.6,
      0.4,
      1.0,
      0.3,
      0.7,
      0.5,
      1.0,
      0.4,
      0.8,
      0.3,
      1.0,
      0.6,
      0.9,
      0.3,
      1.0,
      0.5,
      0.7,
      0.4,
      1.0,
      0.3,
      0.8,
    ];
    final barWidth = size.width / (weights.length * 1.6);
    var x = 0.0;
    for (final w in weights) {
      final h = size.height * w;
      canvas.drawRect(Rect.fromLTWH(x, size.height - h, barWidth, h), paint);
      x += barWidth * 1.6;
    }
  }

  @override
  bool shouldRepaint(covariant _BarcodePainter oldDelegate) =>
      oldDelegate.color != color;
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppTheme.radiusSm),
            ),
            child: Icon(icon, size: 18, color: scheme.primary),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: Theme.of(context).textTheme.labelMedium),
                const SizedBox(height: 2),
                Text(
                  value.isEmpty ? '-' : value,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
