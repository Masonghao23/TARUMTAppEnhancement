import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../data/device_binding_exceptions.dart';
import '../data/models.dart';
import '../providers.dart';

class DeviceBindingSection extends ConsumerStatefulWidget {
  const DeviceBindingSection({super.key});

  /// Creates the mutable state for this widget.
  @override
  ConsumerState<DeviceBindingSection> createState() =>
      _DeviceBindingSectionState();
}

class _DeviceBindingSectionState extends ConsumerState<DeviceBindingSection> {
  bool _isBinding = false;

  /// Binds the current device and refreshes the displayed binding.
  Future<void> _bind({bool force = false}) async {
    final userId = ref.read(currentUserIdProvider);
    if (userId == null) return;

    setState(() => _isBinding = true);
    try {
      final identity = await ref
          .read(deviceIdentityServiceProvider)
          .getDeviceIdentity();
      await ref
          .read(profileRepositoryProvider)
          .bindDevice(userId: userId, identity: identity, force: force);

      ref.invalidate(currentDeviceProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Device bound successfully.')),
      );
    } on DeviceBindCooldownException catch (e) {
      _showMessage(
        'You already bound a device recently. Try again in '
        '${_formatDuration(e.remaining)}.',
      );
    } on DeviceAlreadyBoundException catch (_) {
      if (!mounted) return;
      final shouldForce = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Device already linked'),
          content: const Text(
            'This device is currently linked to another account. '
            'Do you want to change the binding to your account instead?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Bind to my account'),
            ),
          ],
        ),
      );
      if (shouldForce == true) {
        await _bind(force: true);
        return;
      }
    } catch (_) {
      _showMessage('Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => _isBinding = false);
    }
  }

  /// Displays a feedback message to the user.
  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  /// Formats the remaining device-binding cooldown.
  String _formatDuration(Duration duration) {
    final days = duration.inDays;
    if (days >= 1) return '$days day${days == 1 ? '' : 's'}';
    final hours = duration.inHours;
    if (hours >= 1) return '$hours hour${hours == 1 ? '' : 's'}';
    return '${duration.inMinutes} minute(s)';
  }

  /// Builds the device binding section interface.
  @override
  Widget build(BuildContext context) {
    final deviceAsync = ref.watch(currentDeviceProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        deviceAsync.when(
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: 40),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (error, _) => Text('Failed to load device info: $error'),
          data: (device) => _DeviceCard(device: device),
        ),
        const SizedBox(height: 20),
        ElevatedButton.icon(
          onPressed: _isBinding ? null : () => _bind(),
          icon: _isBinding
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.phonelink_lock_outlined),
          label: Text(_isBinding ? 'Binding...' : 'Bind this device'),
        ),
      ],
    );
  }
}

class _DeviceCard extends StatelessWidget {
  const _DeviceCard({required this.device});

  final UserDevice? device;

  /// Builds the device card interface.
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    if (device == null) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(AppTheme.radiusLg),
          border: Border.all(
            color: scheme.outlineVariant.withValues(alpha: 0.6),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(AppTheme.radiusSm),
              ),
              child: Icon(
                Icons.phonelink_erase_outlined,
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 14),
            const Expanded(child: Text('No device bound to this account yet.')),
          ],
        ),
      );
    }

    final cooldown = device!.cooldownRemaining;
    final active = cooldown <= Duration.zero;
    final statusColor = active ? scheme.tertiary : scheme.error;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                ),
                child: Icon(Icons.smartphone_outlined, color: scheme.primary),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      device!.deviceModel,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Bound on ${device!.bindDate.toLocal()}'.split('.').first,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppTheme.radiusSm),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  active
                      ? Icons.check_circle_outline
                      : Icons.lock_clock_outlined,
                  size: 16,
                  color: statusColor,
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    active
                        ? 'Ready to bind a new device'
                        : 'Re-binding available in ${cooldown.inDays} day(s)',
                    style: TextStyle(
                      color: statusColor,
                      fontWeight: FontWeight.w700,
                      fontSize: 12.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
