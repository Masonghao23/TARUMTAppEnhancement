import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Which HomeShell tab is selected. Lives here (not as local State in
/// HomeShell) so a tile inside any tab — e.g. the Home screen's "Parking
/// free" bento tile — can switch tabs the same way tapping the bottom nav
/// does, instead of pushing a second instance of that tab's screen on top
/// with no nav bar. Default (1) is the Home tab, matching HomeShell's
/// original initial index.
final homeShellTabIndexProvider = StateProvider<int>((ref) => 1);
