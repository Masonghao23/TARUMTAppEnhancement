import 'dart:io' show Platform;

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'core/config/supabase_config.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await _tryInitializeFirebase();
  await Supabase.initialize(
    url: SupabaseConfig.url,
    publishableKey: SupabaseConfig.anonKey,
  );

  runApp(const ProviderScope(child: TarumtApp()));
}

/// Firebase is only wired up for FCM (Notification module, not built yet)
/// and only has config for Android so far. Push notifications degrade
/// gracefully if this fails, so a missing/failing config on other
/// platforms shouldn't block the rest of the app.
Future<void> _tryInitializeFirebase() async {
  final hasConfig = !kIsWeb && (Platform.isAndroid || Platform.isIOS);
  if (!hasConfig) return;

  try {
    await Firebase.initializeApp();
  } catch (error) {
    debugPrint('Firebase initialization skipped: $error');
  }
}
