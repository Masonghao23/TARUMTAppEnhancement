import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Which HomeShell tab is selected. Lives here (not as local State in
/// HomeShell) so a tile inside any tab — e.g. the Home screen's "Parking
/// free" bento tile — can switch tabs the same way tapping the bottom nav
/// does, instead of pushing a second instance of that tab's screen on top
/// with no nav bar. Default (2) is the Home tab — HomeShell's pages list
/// is [Attendance(0), Parking(1), Home(2), Profile(3), Directory(4)].
final homeShellTabIndexProvider = StateProvider<int>((ref) => 2);
