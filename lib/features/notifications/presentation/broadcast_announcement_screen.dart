import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../providers.dart';

/// Use case 4.2.4 "Broadcast Announcement" (Table 4.12) — staff/admin
/// compose a title, message and target group, and every matching profile
/// gets it as a real push + in-app notification (send_broadcast_announcement
/// routes through notify_user() per recipient, always-allowed — see
/// notification_schema.sql). There's no opt-out toggle for this category by
/// design, matching the report.
class BroadcastAnnouncementScreen extends ConsumerStatefulWidget {
  const BroadcastAnnouncementScreen({super.key});

  @override
  ConsumerState<BroadcastAnnouncementScreen> createState() =>
      _BroadcastAnnouncementScreenState();
}

class _BroadcastAnnouncementScreenState
    extends ConsumerState<BroadcastAnnouncementScreen> {
  final _titleController = TextEditingController();
  final _messageController = TextEditingController();
  String _target = 'students';
  bool _sending = false;
  String? _error;

  static const _targets = [
    ('students', 'Students', Icons.school_outlined),
    ('staff', 'Staff & admin', Icons.badge_outlined),
    ('all', 'Everyone', Icons.public_outlined),
  ];

  @override
  void dispose() {
    _titleController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final title = _titleController.text.trim();
    final message = _messageController.text.trim();
    if (title.isEmpty || message.isEmpty) {
      setState(() => _error = 'Title and message are required.');
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Send announcement?'),
        content: Text(
          'This will push a notification to every ${_targetLabel(_target).toLowerCase()} '
          'account right now. This can\'t be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Send'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final result = await ref
          .read(notificationRepositoryProvider)
          .sendBroadcastAnnouncement(
            title: title,
            message: message,
            target: _target,
          );
      if (!mounted) return;
      if (!result.success) {
        setState(() => _error = result.reason ?? 'Could not send.');
        return;
      }
      final count = result.recipientCount ?? 0;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Announcement sent to $count ${count == 1 ? 'person' : 'people'}.',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  String _targetLabel(String value) =>
      _targets.firstWhere((t) => t.$1 == value).$2;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Send Announcement')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Send to', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Row(
                children: [
                  for (final t in _targets) ...[
                    Expanded(
                      child: _TargetChip(
                        icon: t.$3,
                        label: t.$2,
                        selected: _target == t.$1,
                        enabled: !_sending,
                        onTap: () => setState(() => _target = t.$1),
                      ),
                    ),
                    if (t != _targets.last) const SizedBox(width: 8),
                  ],
                ],
              ),
              const SizedBox(height: 20),
              Text('Title', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              TextField(
                controller: _titleController,
                enabled: !_sending,
                maxLength: 80,
                decoration: const InputDecoration(
                  hintText: 'e.g. Campus closed tomorrow',
                ),
              ),
              const SizedBox(height: 12),
              Text('Message', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              TextField(
                controller: _messageController,
                enabled: !_sending,
                maxLines: 4,
                maxLength: 300,
                decoration: const InputDecoration(
                  hintText: 'Details everyone needs to know…',
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: scheme.errorContainer,
                    borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                  ),
                  child: Text(
                    _error!,
                    style: TextStyle(color: scheme.onErrorContainer),
                  ),
                ),
              ],
              const SizedBox(height: 28),
              ElevatedButton(
                onPressed: _sending ? null : _send,
                child: _sending
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Send announcement'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TargetChip extends StatelessWidget {
  const _TargetChip({
    required this.icon,
    required this.label,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: selected ? scheme.primaryContainer : scheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(AppTheme.radiusMd),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        onTap: enabled ? onTap : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          child: Column(
            children: [
              Icon(
                icon,
                color: selected ? scheme.onPrimaryContainer : scheme.primary,
                size: 22,
              ),
              const SizedBox(height: 6),
              Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: selected
                      ? scheme.onPrimaryContainer
                      : scheme.onSurface,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
