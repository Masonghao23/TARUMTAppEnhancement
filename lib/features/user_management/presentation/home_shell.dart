import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_logo.dart';
import '../../attendance/presentation/create_session_screen.dart';
import '../../attendance/presentation/staff_sessions_screen.dart';
import '../../attendance/presentation/student_attendance_screen.dart';
import '../../auth/providers.dart';
import '../../home/presentation/home_screen.dart';
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
  int _index = 1;

  static const _titles = ['Attendance', 'Home', 'Profile', 'Directory'];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final profileAsync = ref.watch(currentProfileProvider);
    final isAdmin = profileAsync.value?.role == UserRole.admin;
    final isStaff = profileAsync.value?.role == UserRole.staff || isAdmin;
    const attendanceIndex = 0;
    final directoryIndex = isStaff ? 3 : -1;

    final destinations = <NavigationDestination>[
      const NavigationDestination(
        icon: Icon(Icons.qr_code_scanner_outlined),
        selectedIcon: Icon(Icons.qr_code_scanner),
        label: 'Attendance',
      ),
      const NavigationDestination(
        icon: Icon(Icons.home_outlined),
        selectedIcon: Icon(Icons.home),
        label: 'Home',
      ),
      const NavigationDestination(
        icon: Icon(Icons.person_outline),
        selectedIcon: Icon(Icons.person),
        label: 'Profile',
      ),
      if (isStaff)
        const NavigationDestination(
          icon: Icon(Icons.groups_outlined),
          selectedIcon: Icon(Icons.groups),
          label: 'Directory',
        ),
    ];

    final pages = <Widget>[
      isStaff ? const StaffSessionsScreen() : const StudentAttendanceScreen(),
      const HomeScreen(),
      const ProfileScreen(),
      if (isStaff) const StaffUserSearchScreen(),
    ];

    final safeIndex = _index >= pages.length ? 0 : _index;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 20,
        title: Row(
          children: [
            const AppLogo(height: 26),
            const SizedBox(width: 14),
            Text(_titles[safeIndex]),
          ],
        ),
        actions: [
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
      bottomNavigationBar: NavigationBar(
        selectedIndex: safeIndex,
        onDestinationSelected: (value) => setState(() => _index = value),
        destinations: destinations,
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
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const CreateUserScreen()),
        ),
        icon: const Icon(Icons.person_add_alt_1_outlined),
        label: const Text('New account'),
      );
    }
    if (isStaff && safeIndex == attendanceIndex) {
      return FloatingActionButton.extended(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const CreateSessionScreen()),
        ),
        icon: const Icon(Icons.add_rounded),
        label: const Text('New session'),
      );
    }
    return null;
  }
}
