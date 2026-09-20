import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../attendance/presentation/course_attendance_screen.dart';
import '../../attendance/presentation/scan_screen.dart';
import '../../attendance/presentation/start_session_screen.dart';
import '../../attendance/providers.dart';
import '../../booking/booking_screen.dart';
import '../../booking/my_bookings_screen.dart';
import '../../booking/nfc_checkin_screen.dart';
import '../../campus_map/global_map_screen.dart';
import '../../notifications/presentation/broadcast_announcement_screen.dart';
import '../../parking/data/models.dart';
import '../../parking/presentation/active_session_screen.dart';
import '../../parking/presentation/book_slot_screen.dart';
import '../../parking/presentation/upcoming_reservation_screen.dart';
import '../../parking/providers.dart';
import '../../user_management/data/models.dart';
import '../../user_management/providers.dart';
import '../providers.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  /// Builds the home screen interface.
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(currentProfileProvider);
    final profile = profileAsync.value;
    final isAdmin = profile?.role == UserRole.admin;
    final isStaff = profile?.role == UserRole.staff || isAdmin;
    final hour = DateTime.now().hour;
    final greeting = hour < 12
        ? 'Good morning'
        : (hour < 18 ? 'Good afternoon' : 'Good evening');

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    greeting.toUpperCase(),
                    style: Theme.of(
                      context,
                    ).textTheme.labelMedium?.copyWith(letterSpacing: 0.6),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    profile == null
                        ? 'Welcome'
                        : (profile.name.isEmpty ? profile.email : profile.name),
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ],
              ),
            ),
            _Avatar(profile: profile),
          ],
        ),
        const SizedBox(height: 20),
        if (profile != null)
          isStaff
              ? _StaffBento(isAdmin: isAdmin, profile: profile)
              : _StudentBento(profile: profile),
      ],
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.profile});

  final Profile? profile;

  /// Builds the avatar interface.
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final initial = profile == null || profile!.name.isEmpty
        ? '?'
        : profile!.name[0].toUpperCase();
    return Container(
      width: 42,
      height: 42,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: scheme.primary,
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
      ),
      child: Text(
        initial,
        style: TextStyle(
          color: scheme.onPrimary,
          fontWeight: FontWeight.w800,
          fontSize: 16,
        ),
      ),
    );
  }
}

class _StudentBento extends ConsumerWidget {
  const _StudentBento({required this.profile});

  final Profile profile;

  /// Builds the student bento interface.
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hoursAsync = ref.watch(overallAttendanceHoursProvider(profile.id));
    final percent = hoursAsync.value?.percent;
    final slotsAsync = ref.watch(liveParkingSlotsProvider);
    final reservationsAsync = ref.watch(myParkingReservationsProvider);

    ParkingReservation? activeReservation;
    for (final r in reservationsAsync.value ?? const <ParkingReservation>[]) {
      if (r.isActiveNow) {
        activeReservation = r;
        break;
      }
    }
    final upcomingReservation =
        (reservationsAsync.value?.where((r) => r.isUpcoming).toList() ?? [])
          ..sort((a, b) => a.startTime.compareTo(b.startTime));

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _BentoTile(
                leading: _AttendanceRing(percent: percent),
                title: percent == null ? '—' : '${percent.round()}%',
                subtitle: 'Attendance',
                horizontal: true,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const CourseAttendanceScreen(),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _BentoTile(
                icon: Icons.local_parking_rounded,
                iconColor: AppTheme.success(context),
                title: slotsAsync.when(
                  data: (slots) {
                    final avail = slots
                        .where((s) => s.isReservable && !s.isOccupied)
                        .length;
                    return '$avail/${slots.length}';
                  },
                  loading: () => '—',
                  error: (_, _) => '—',
                ),
                subtitle: 'Parking free',
                onTap: () =>
                    ref.read(homeShellTabIndexProvider.notifier).state = 1,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _BentoTile(
                icon: Icons.qr_code_scanner_rounded,
                title: 'Scan',
                subtitle: 'Check in to class',
                onTap: () => Navigator.of(
                  context,
                ).push(MaterialPageRoute(builder: (_) => const ScanScreen())),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: activeReservation != null
                  ? _BentoTile(
                      icon: Icons.directions_car_filled_rounded,
                      title: activeReservation.slotNumber,
                      subtitle: 'Active session',
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => ActiveSessionScreen(
                            reservation: activeReservation!,
                          ),
                        ),
                      ),
                    )
                  : upcomingReservation.isNotEmpty
                  ? _BentoTile(
                      icon: Icons.event_available_rounded,
                      title: upcomingReservation.first.slotNumber,
                      subtitle:
                          'Reserved · ${_fmtTime(context, upcomingReservation.first.startTime)}',
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => UpcomingReservationScreen(
                            reservation: upcomingReservation.first,
                          ),
                        ),
                      ),
                    )
                  : _BentoTile(
                      icon: Icons.add_circle_outline_rounded,
                      title: 'Reserve',
                      subtitle: 'Book a parking slot',
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const BookSlotScreen(),
                        ),
                      ),
                    ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _BentoTile(
                icon: Icons.map_outlined,
                iconColor: Colors.teal,
                title: '3D Campus Map',
                subtitle: 'Navigate the campus',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const GlobalMapScreen()),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _BentoTile(
                icon: Icons.meeting_room_rounded,
                title: 'Book a room',
                subtitle: 'Discussion rooms',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const BookingScreen()),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        _BentoTile(
          icon: Icons.event_note_rounded,
          title: 'My bookings',
          subtitle: 'Check your booking status',
          horizontal: true,
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const MyBookingsScreen()),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const NfcCheckinScreen()),
            ),
            icon: const Icon(Icons.play_circle_fill, color: Colors.white),
            label: const Text(
              'Check-In Demo',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ),
      ],
    );
  }

  /// Formats a time for display.
  static String _fmtTime(BuildContext context, DateTime dt) =>
      TimeOfDay.fromDateTime(dt).format(context);
}

class _StaffBento extends ConsumerWidget {
  const _StaffBento({required this.isAdmin, required this.profile});

  final bool isAdmin;
  final Profile profile;

  /// Builds the staff bento interface.
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessionsAsync = ref.watch(mySessionsProvider(profile.id));
    final slotsAsync = ref.watch(liveParkingSlotsProvider);

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _BentoTile(
                icon: Icons.qr_code_scanner_rounded,
                title: sessionsAsync.when(
                  data: (sessions) => '${sessions.length}',
                  loading: () => '—',
                  error: (_, _) => '—',
                ),
                subtitle: 'Sessions run',
                onTap: () =>
                    ref.read(homeShellTabIndexProvider.notifier).state = 0,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _BentoTile(
                icon: Icons.local_parking_rounded,
                iconColor: AppTheme.success(context),
                title: slotsAsync.when(
                  data: (slots) {
                    final avail = slots
                        .where((s) => s.isReservable && !s.isOccupied)
                        .length;
                    return '$avail/${slots.length}';
                  },
                  loading: () => '—',
                  error: (_, _) => '—',
                ),
                subtitle: 'Parking free',
                onTap: () =>
                    ref.read(homeShellTabIndexProvider.notifier).state = 1,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _BentoTile(
                icon: Icons.add_circle_outline_rounded,
                title: 'New session',
                subtitle: 'Start attendance',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const StartSessionScreen()),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: isAdmin
                  ? _BentoTile(
                      icon: Icons.groups_rounded,
                      title: 'Directory',
                      subtitle: 'Manage accounts',
                      onTap: () =>
                          ref.read(homeShellTabIndexProvider.notifier).state =
                              4,
                    )
                  : _BentoTile(
                      icon: Icons.person_outline_rounded,
                      title: 'Profile',
                      subtitle: 'Your account',
                      onTap: () =>
                          ref.read(homeShellTabIndexProvider.notifier).state =
                              3,
                    ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        _BentoTile(
          icon: Icons.campaign_outlined,
          title: 'Send Announcement',
          subtitle: 'Broadcast a push notice to students or staff',
          horizontal: true,
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => const BroadcastAnnouncementScreen(),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _BentoTile(
                icon: Icons.map_outlined,
                iconColor: Colors.teal,
                title: '3D Campus Map',
                subtitle: 'Navigate the campus',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const GlobalMapScreen()),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _BentoTile(
                icon: Icons.meeting_room_rounded,
                title: 'Book a room',
                subtitle: 'Discussion rooms',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const BookingScreen()),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        _BentoTile(
          icon: Icons.event_note_rounded,
          title: 'My bookings',
          subtitle: 'Check your booking status',
          horizontal: true,
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const MyBookingsScreen()),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const NfcCheckinScreen()),
            ),
            icon: const Icon(Icons.play_circle_fill, color: Colors.white),
            label: const Text(
              'Check-In Demo',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ),
      ],
    );
  }
}

class _AttendanceRing extends StatelessWidget {
  const _AttendanceRing({required this.percent});

  final double? percent;

  /// Builds the attendance ring interface.
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: 40,
      height: 40,
      child: CircularProgressIndicator(
        value: percent == null ? null : (percent! / 100).clamp(0, 1),
        strokeWidth: 5,
        backgroundColor: scheme.surfaceContainerHighest,
      ),
    );
  }
}

class _BentoTile extends StatelessWidget {
  const _BentoTile({
    this.icon,
    this.iconColor,
    this.leading,
    required this.title,
    required this.subtitle,
    this.horizontal = false,
    required this.onTap,
  }) : assert(icon != null || leading != null);

  final IconData? icon;
  final Color? iconColor;
  final Widget? leading;
  final String title;
  final String subtitle;
  final bool horizontal;
  final VoidCallback onTap;

  /// Builds the bento tile interface.
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final leadingWidget =
        leading ?? Icon(icon, color: iconColor ?? scheme.primary, size: 26);
    final textColumn = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          style: textTheme.titleLarge?.copyWith(
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        const SizedBox(height: 1),
        Text(subtitle, style: textTheme.labelMedium),
      ],
    );

    return Material(
      color: scheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(AppTheme.radiusLg),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 92),
          padding: const EdgeInsets.all(14),
          child: horizontal
              ? Row(
                  children: [
                    leadingWidget,
                    const SizedBox(width: 12),
                    Expanded(child: textColumn),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    leadingWidget,
                    const SizedBox(height: 8),
                    textColumn,
                  ],
                ),
        ),
      ),
    );
  }
}
