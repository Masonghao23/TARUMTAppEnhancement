import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../core/theme/app_theme.dart';
import '../data/models.dart';
import '../data/qr_token.dart';
import '../providers.dart';
import 'manage_attendance_screen.dart';

class LiveSessionScreen extends ConsumerStatefulWidget {
  const LiveSessionScreen({super.key, required this.session});

  final ClassSession session;

  /// Creates the mutable state for this widget.
  @override
  ConsumerState<LiveSessionScreen> createState() => _LiveSessionScreenState();
}

class _LiveSessionScreenState extends ConsumerState<LiveSessionScreen> {
  Timer? _tickTimer;
  bool _ending = false;
  String? _seed;
  String? _seedError;
  final Map<String, String> _names = {};

  /// Initializes state and starts this component’s setup.
  @override
  void initState() {
    super.initState();
    _loadSeed();
    _tickTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  /// Releases resources and subscriptions owned by this component.
  @override
  void dispose() {
    _tickTimer?.cancel();
    super.dispose();
  }

  /// Loads the session seed used to generate attendance QR codes.
  Future<void> _loadSeed() async {
    try {
      final seed = await ref
          .read(attendanceRepositoryProvider)
          .fetchSessionSeed(widget.session.id);
      if (mounted) setState(() => _seed = seed);
    } catch (_) {
      if (mounted) setState(() => _seedError = 'Could not load the QR code.');
    }
  }

  /// Loads student names for the live attendance list.
  Future<void> _resolveNames(List<AttendanceRecord> records) async {
    final missing = records
        .map((r) => r.studentId)
        .where((id) => !_names.containsKey(id))
        .toSet()
        .toList();
    if (missing.isEmpty) return;
    final resolved = await ref
        .read(attendanceRepositoryProvider)
        .fetchNamesByIds(missing);
    if (mounted) setState(() => _names.addAll(resolved));
  }

  /// Ends the current class session and refreshes its data.
  Future<void> _endSession() async {
    setState(() => _ending = true);
    try {
      await ref
          .read(attendanceRepositoryProvider)
          .endSession(widget.session.id);
      ref.invalidate(mySessionsProvider(widget.session.lecturerId));
      ref.invalidate(activeSessionsProvider(widget.session.lecturerId));
      final start = widget.session.startTime;
      ref.invalidate(
        lecturerScheduleForDateProvider(
          DateTime(start.year, start.month, start.day),
        ),
      );
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (mounted) setState(() => _ending = false);
    }
  }

  /// Formats a time for display.
  String _formatTime(DateTime dt) {
    final local = dt.toLocal();
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  /// Builds the live session screen interface.
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final session = widget.session;
    final rosterAsync = ref.watch(rosterProvider(session.id));

    rosterAsync.whenData(_resolveNames);

    final window = currentWindowIndex(session.qrIntervalSeconds);
    final secondsIntoWindow =
        (DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000) %
        session.qrIntervalSeconds;
    final remaining = session.qrIntervalSeconds - secondsIntoWindow;
    final qrData = _seed == null
        ? null
        : ScannedSessionToken(
            sessionId: session.id,
            token: computeQrToken(seed: _seed!, windowIndex: window),
          ).encode();

    return Scaffold(
      appBar: AppBar(
        title: Text(session.courseName ?? 'Class session'),
        actions: [
          IconButton(
            tooltip: 'Manage attendance',
            icon: const Icon(Icons.checklist_rounded),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => ManageAttendanceScreen(
                  sessionId: session.id,
                  courseName: session.courseName,
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: TextButton(
              onPressed: _ending ? null : _endSession,
              child: _ending
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('End session'),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(AppTheme.radiusLg),
                ),
                child: Column(
                  children: [
                    if (session.roomName != null) ...[
                      Text(
                        session.roomName!,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 12),
                    ],
                    ClipRRect(
                      borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                      child: Container(
                        width: 252,
                        height: 252,
                        color: Colors.white,
                        padding: const EdgeInsets.all(16),
                        child: qrData != null
                            ? QrImageView(
                                data: qrData,
                                size: 220,
                                version: QrVersions.auto,
                              )
                            : Center(
                                child: _seedError != null
                                    ? Text(
                                        _seedError!,
                                        style: TextStyle(color: scheme.error),
                                      )
                                    : const CircularProgressIndicator(),
                              ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.refresh_rounded,
                          size: 16,
                          color: scheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Refreshes in ${remaining}s',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Text(
                    'Checked in',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const Spacer(),
                  rosterAsync.maybeWhen(
                    data: (records) => _CountBadge(count: records.length),
                    orElse: () => const SizedBox.shrink(),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: rosterAsync.when(
                data: (records) {
                  if (records.isEmpty) {
                    return Center(
                      child: Text(
                        'No check-ins yet',
                        style: TextStyle(color: scheme.onSurfaceVariant),
                      ),
                    );
                  }
                  return ListView.separated(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                    itemCount: records.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final record = records[index];
                      final name = _names[record.studentId] ?? 'Loading…';
                      return Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: scheme.surfaceContainerHigh,
                          borderRadius: BorderRadius.circular(
                            AppTheme.radiusMd,
                          ),
                        ),
                        child: Row(
                          children: [
                            CircleAvatar(
                              backgroundColor: scheme.tertiaryContainer,
                              child: Icon(
                                Icons.check_rounded,
                                color: scheme.onTertiaryContainer,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    name,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.titleMedium,
                                  ),
                                  Text(
                                    _formatTime(record.scanTimestamp),
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodyMedium,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  );
                },
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (_, _) => Center(
                  child: Text(
                    'Could not load check-ins',
                    style: TextStyle(color: scheme.error),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.count});

  final int count;

  /// Builds the count badge interface.
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(AppTheme.radiusPill),
      ),
      child: Text(
        '$count',
        style: TextStyle(
          color: scheme.onPrimaryContainer,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
