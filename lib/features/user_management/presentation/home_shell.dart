import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_logo.dart';
import '../../../core/widgets/floating_nav_bar.dart';
import '../../attendance/presentation/start_session_screen.dart';
import '../../attendance/presentation/staff_sessions_screen.dart';
import '../../attendance/presentation/student_attendance_screen.dart';
import '../../auth/providers.dart';
import '../../home/presentation/home_screen.dart';
import '../../home/providers.dart' as home_providers;
import '../../notifications/presentation/notifications_screen.dart';
import '../../notifications/providers.dart';
import '../../parking/presentation/parking_dashboard_screen.dart';
import '../data/models.dart';
import '../providers.dart';
import 'create_user_screen.dart';
import 'profile_screen.dart';
import 'staff_user_search_screen.dart';

class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  static const _titles = [
    'Attendance',
    'Parking',
    'Home',
    'Profile',
    'Directory',
  ];

  @override
  Widget build(BuildContext context) {
    // Fire-and-forget: registers this device's FCM token once per
    // signed-in user. No loading/error UI needed for a background setup
    // step — a failed permission grant or token fetch just means no push
    // for this device, not a broken screen.
    ref.watch(pushNotificationSetupProvider);

    final scheme = Theme.of(context).colorScheme;
    final profileAsync = ref.watch(currentProfileProvider);
    final unreadCount = ref.watch(unreadNotificationCountProvider);
    final isAdmin = profileAsync.value?.role == UserRole.admin;
    final isStaff = profileAsync.value?.role == UserRole.staff || isAdmin;
    const attendanceIndex = 0;
    final directoryIndex = isStaff ? 4 : -1;

    final destinations = <FloatingNavItem>[
      const FloatingNavItem(
        icon: Icons.qr_code_scanner_outlined,
        selectedIcon: Icons.qr_code_scanner,
        label: 'Attendance',
      ),
      const FloatingNavItem(
        icon: Icons.local_parking_outlined,
        selectedIcon: Icons.local_parking,
        label: 'Parking',
      ),
      const FloatingNavItem(
        icon: Icons.home_outlined,
        selectedIcon: Icons.home,
        label: 'Home',
      ),
      const FloatingNavItem(
        icon: Icons.person_outline,
        selectedIcon: Icons.person,
        label: 'Profile',
      ),
      if (isStaff)
        const FloatingNavItem(
          icon: Icons.groups_outlined,
          selectedIcon: Icons.groups,
          label: 'Directory',
        ),
    ];

    final pages = <Widget>[
      isStaff ? const StaffSessionsScreen() : const StudentAttendanceScreen(),
      const ParkingDashboardScreen(),
      const HomeScreen(),
      const ProfileScreen(),
      if (isStaff) const StaffUserSearchScreen(),
    ];

    final index = ref.watch(home_providers.homeShellTabIndexProvider);
    final safeIndex = index >= pages.length ? 0 : index;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 20,
        title: Row(
          children: [
            const AppLogo(height: 26),
            const SizedBox(width: 14),
            Expanded(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(_titles[safeIndex], maxLines: 1),
              ),
            ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                IconButton(
                  tooltip: 'Notifications',
                  style: IconButton.styleFrom(
                    backgroundColor: scheme.surfaceContainerHigh,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                    ),
                  ),
                  icon: const Icon(Icons.notifications_outlined),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const NotificationsScreen(),
                    ),
                  ),
                ),
                if (unreadCount > 0)
                  Positioned(
                    right: 6,
                    top: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: scheme.error,
                        borderRadius: BorderRadius.circular(
                          AppTheme.radiusPill,
                        ),
                      ),
                      child: Text(
                        unreadCount > 9 ? '9+' : '$unreadCount',
                        style: TextStyle(
                          color: scheme.onError,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: IconButton(
              tooltip: 'Log out',
              style: IconButton.styleFrom(
                backgroundColor: scheme.surfaceContainerHigh,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                ),
              ),
              icon: const Icon(Icons.logout_rounded),
              onPressed: () => ref.read(authRepositoryProvider).signOut(),
            ),
          ),
        ],
      ),
      body: IndexedStack(index: safeIndex, children: pages),
      bottomNavigationBar: FloatingNavBar(
        selectedIndex: safeIndex,
        onDestinationSelected: (value) =>
            ref.read(home_providers.homeShellTabIndexProvider.notifier).state =
                value,
        items: destinations,
      ),
      floatingActionButton: _buildFab(
        context: context,
        safeIndex: safeIndex,
        isAdmin: isAdmin,
        isStaff: isStaff,
        directoryIndex: directoryIndex,
        attendanceIndex: attendanceIndex,
      ),
    );
  }

  Widget? _buildFab({
    required BuildContext context,
    required int safeIndex,
    required bool isAdmin,
    required bool isStaff,
    required int directoryIndex,
    required int attendanceIndex,
  }) {
    if (isAdmin && safeIndex == directoryIndex) {
      return FloatingActionButton.extended(
        onPressed: () => Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const CreateUserScreen())),
        icon: const Icon(Icons.person_add_alt_1_outlined),
        label: const Text('New account'),
      );
    }
    if (isStaff && safeIndex == attendanceIndex) {
      return FloatingActionButton.extended(
        onPressed: () => Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const StartSessionScreen())),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Start session'),
      );
    }
    return null;
  }
}
