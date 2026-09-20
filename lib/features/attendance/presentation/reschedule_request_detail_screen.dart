import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../user_management/data/models.dart';
import '../../user_management/providers.dart';
import '../data/models.dart';
import '../providers.dart';
import 'request_reschedule_screen.dart';

class RescheduleRequestDetailScreen extends ConsumerStatefulWidget {
  const RescheduleRequestDetailScreen({super.key, required this.request});

  final RescheduleRequest request;

  /// Creates the mutable state for this widget.
  @override
  ConsumerState<RescheduleRequestDetailScreen> createState() =>
      _RescheduleRequestDetailScreenState();
}

class _RescheduleRequestDetailScreenState
    extends ConsumerState<RescheduleRequestDetailScreen> {
  bool _busy = false;
  String? _error;

  static const _dayLabels = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];

  /// Formats a date for display.
  String _fmtDate(DateTime d) =>
      '${_dayLabels[d.weekday - 1]}, ${d.day}/${d.month}/${d.year}';

  /// Formats a time for display.
  String _fmtTime(WallClockTime t) {
    final period = t.hour >= 12 ? 'PM' : 'AM';
    final h12 = t.hour % 12 == 0 ? 12 : t.hour % 12;
    return '$h12:${t.minute.toString().padLeft(2, '0')} $period';
  }

  /// Submits the admin’s decision on a reschedule request.
  Future<void> _review(String decision, {String? comment}) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await ref
          .read(attendanceRepositoryProvider)
          .reviewRescheduleRequest(
            requestId: widget.request.id,
            decision: decision,
            comment: comment,
          );
      if (!mounted) return;
      if (!result.success) {
        setState(() => _error = result.reason ?? 'Could not save decision.');
        return;
      }
      Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Opens the form to edit the reschedule request.
  Future<void> _editRequest(RescheduleRequest request) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => RequestRescheduleScreen(existingRequest: request),
      ),
    );
    if (!mounted || changed != true) return;
    Navigator.of(context).pop();
  }

  /// Prompts for confirmation before rejecting the request.
  Future<void> _confirmReject() async {
    final controller = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Reject request'),
        content: TextField(
          controller: controller,
          maxLines: 3,
          decoration: const InputDecoration(
            hintText: 'Let them know why (optional)',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Reject'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      final comment = controller.text.trim();
      await _review('rejected', comment: comment.isEmpty ? null : comment);
    }
  }

  /// Builds the reschedule request detail screen interface.
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final request = widget.request;
    final profile = ref.watch(currentProfileProvider).value;
    final isAdmin = profile?.role == UserRole.admin;
    final isRequester = ref.watch(currentUserIdProvider) == request.requestedBy;
    final isPending = request.status == RescheduleRequestStatus.pending;

    return Scaffold(
      appBar: AppBar(title: const Text('Reschedule request')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (isAdmin)
                _InfoCard(label: 'Requested by', value: request.requesterName),
              _InfoCard(
                label: 'Class',
                value:
                    '${request.courseName} · ${request.sessionType.name[0].toUpperCase()}${request.sessionType.name.substring(1)}',
              ),
              _InfoCard(
                label: 'Original slot',
                value:
                    '${_fmtDate(request.originalDate)}, '
                    '${_fmtTime(request.originalStartTime)}–${_fmtTime(request.originalEndTime)}, '
                    '${request.originalRoomName}',
              ),
              _InfoCard(
                label: 'Requested change',
                value: request.exceptionType == 'cancel'
                    ? 'Cancel this occurrence'
                    : 'Move to ${_fmtDate(request.newDate!)}, '
                          '${_fmtTime(request.newStartTime!)}–${_fmtTime(request.newEndTime!)}, '
                          '${request.newRoomName ?? ''}',
              ),
              _InfoCard(label: 'Reason', value: request.reason),
              if (request.reviewComment != null &&
                  request.reviewComment!.isNotEmpty)
                _InfoCard(
                  label: 'Admin note',
                  value: request.reviewComment!,
                  valueColor: scheme.error,
                ),
              if (_error != null) ...[
                const SizedBox(height: 6),
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
              if (isAdmin && isPending) ...[
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _busy ? null : () => _review('approved'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.success(context),
                  ),
                  child: _busy
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Approve'),
                ),
                const SizedBox(height: 10),
                OutlinedButton(
                  onPressed: _busy ? null : _confirmReject,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: scheme.error,
                    side: BorderSide(color: scheme.error),
                  ),
                  child: const Text('Reject'),
                ),
              ] else if (isRequester && isPending) ...[
                const SizedBox(height: 16),
                FilledButton.tonalIcon(
                  onPressed: () => _editRequest(request),
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Edit request'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.label, required this.value, this.valueColor});

  final String label;
  final String value;
  final Color? valueColor;

  /// Builds the info card interface.
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label.toUpperCase(),
              style: Theme.of(context).textTheme.labelMedium,
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: Theme.of(
                context,
              ).textTheme.bodyLarge?.copyWith(color: valueColor),
            ),
          ],
        ),
      ),
    );
  }
}
