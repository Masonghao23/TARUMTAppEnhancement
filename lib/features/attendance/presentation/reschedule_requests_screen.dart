import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../user_management/data/models.dart';
import '../../user_management/providers.dart';
import '../data/models.dart';
import '../providers.dart';
import 'reschedule_request_detail_screen.dart';

class RescheduleRequestsScreen extends ConsumerStatefulWidget {
  const RescheduleRequestsScreen({super.key});

  /// Creates the mutable state for this widget.
  @override
  ConsumerState<RescheduleRequestsScreen> createState() =>
      _RescheduleRequestsScreenState();
}

class _RescheduleRequestsScreenState
    extends ConsumerState<RescheduleRequestsScreen> {
  RescheduleRequestStatus? _filter = RescheduleRequestStatus.pending;

  /// Builds the reschedule requests screen interface.
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final profile = ref.watch(currentProfileProvider).value;
    final isAdmin = profile?.role == UserRole.admin;
    final requestsAsync = ref.watch(rescheduleRequestsProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(isAdmin ? 'Reschedule Requests' : 'My Requests'),
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async => ref.invalidate(rescheduleRequestsProvider),
          child: requestsAsync.when(
            data: (all) {
              final filtered = isAdmin && _filter != null
                  ? all.where((r) => r.status == _filter).toList()
                  : all;

              return Column(
                children: [
                  if (isAdmin)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                      child: SizedBox(
                        height: 34,
                        child: ListView(
                          scrollDirection: Axis.horizontal,
                          children: [
                            for (final status in RescheduleRequestStatus.values)
                              Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: ChoiceChip(
                                  label: Text(_statusLabel(status)),
                                  selected: _filter == status,
                                  onSelected: (_) =>
                                      setState(() => _filter = status),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  Expanded(
                    child: filtered.isEmpty
                        ? ListView(
                            padding: const EdgeInsets.fromLTRB(20, 60, 20, 20),
                            children: [
                              Icon(
                                Icons.event_repeat_outlined,
                                size: 56,
                                color: scheme.onSurfaceVariant,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                isAdmin
                                    ? 'No ${_statusLabel(_filter ?? RescheduleRequestStatus.pending).toLowerCase()} requests'
                                    : 'No reschedule requests yet',
                                textAlign: TextAlign.center,
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                            ],
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                            itemCount: filtered.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(height: 8),
                            itemBuilder: (context, index) {
                              final request = filtered[index];
                              return _RequestCard(
                                request: request,
                                showRequester: isAdmin,
                                onTap: () => Navigator.of(context)
                                    .push(
                                      MaterialPageRoute(
                                        builder: (_) =>
                                            RescheduleRequestDetailScreen(
                                              request: request,
                                            ),
                                      ),
                                    )
                                    .then(
                                      (_) => ref.invalidate(
                                        rescheduleRequestsProvider,
                                      ),
                                    ),
                              );
                            },
                          ),
                  ),
                ],
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (_, _) => Center(
              child: Text(
                'Could not load requests',
                style: TextStyle(color: scheme.error),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Returns the display label for a request status.
  static String _statusLabel(RescheduleRequestStatus status) {
    switch (status) {
      case RescheduleRequestStatus.pending:
        return 'Pending';
      case RescheduleRequestStatus.approved:
        return 'Approved';
      case RescheduleRequestStatus.rejected:
        return 'Rejected';
      case RescheduleRequestStatus.withdrawn:
        return 'Withdrawn';
    }
  }
}

class _RequestCard extends StatelessWidget {
  const _RequestCard({
    required this.request,
    required this.showRequester,
    required this.onTap,
  });

  final RescheduleRequest request;
  final bool showRequester;
  final VoidCallback onTap;

  /// Returns the display color for the selected status.
  static Color _statusColor(BuildContext context, RescheduleRequestStatus s) {
    final scheme = Theme.of(context).colorScheme;
    switch (s) {
      case RescheduleRequestStatus.pending:
        return scheme.tertiary;
      case RescheduleRequestStatus.approved:
        return AppTheme.success(context);
      case RescheduleRequestStatus.rejected:
        return scheme.error;
      case RescheduleRequestStatus.withdrawn:
        return scheme.onSurfaceVariant;
    }
  }

  /// Describes the requested timetable change.
  String _changeSummary() {
    if (request.exceptionType == 'cancel') {
      return 'Cancel ${_fmtDate(request.originalDate)}';
    }
    final newDate = request.newDate;
    final newStart = request.newStartTime;
    if (newDate == null || newStart == null) return 'Move';
    return 'Move ${_fmtDate(request.originalDate)} → ${_fmtDate(newDate)}, '
        '${_fmtTime(newStart)}';
  }

  /// Formats a date for display.
  static String _fmtDate(DateTime d) => '${d.day}/${d.month}';
  /// Formats a time for display.
  static String _fmtTime(WallClockTime t) {
    final period = t.hour >= 12 ? 'PM' : 'AM';
    final h12 = t.hour % 12 == 0 ? 12 : t.hour % 12;
    return '$h12:${t.minute.toString().padLeft(2, '0')} $period';
  }

  /// Builds the request card interface.
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = _statusColor(context, request.status);
    final label = _RescheduleRequestsScreenState._statusLabel(request.status);

    return Material(
      color: scheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(AppTheme.radiusMd),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                ),
                child: Icon(
                  request.exceptionType == 'cancel'
                      ? Icons.event_busy_rounded
                      : Icons.event_repeat_rounded,
                  color: color,
                  size: 18,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (showRequester)
                      Text(
                        request.requesterName,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    Text(
                      request.courseName,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Text(
                      _changeSummary(),
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(AppTheme.radiusPill),
                ),
                child: Text(
                  label.toUpperCase(),
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w800,
                    fontSize: 10,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
