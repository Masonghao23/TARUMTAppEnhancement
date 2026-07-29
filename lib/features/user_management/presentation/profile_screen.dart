import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
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
        Container(
          padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 20),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                scheme.primary.withValues(alpha: 0.14),
                scheme.surfaceContainerHigh,
              ],
            ),
            borderRadius: BorderRadius.circular(AppTheme.radiusLg),
          ),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: scheme.primary, width: 2.5),
                ),
                child: CircleAvatar(
                  radius: 42,
                  backgroundColor: scheme.primaryContainer,
                  child: Text(
                    profile.name.isNotEmpty
                        ? profile.name[0].toUpperCase()
                        : '?',
                    style: TextStyle(
                      fontSize: 34,
                      fontWeight: FontWeight.bold,
                      color: scheme.onPrimaryContainer,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                profile.name.isEmpty ? '(No name set)' : profile.name,
                style: textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 4),
              Text(profile.email, style: textTheme.bodyMedium),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 6,
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
                    fontSize: 12,
                    letterSpacing: 0.4,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Text(
          'Account details',
          style: textTheme.titleMedium,
        ),
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
      ],
    );
  }
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
