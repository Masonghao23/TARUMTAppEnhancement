import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../user_management/providers.dart';
import '../data/models.dart';
import '../providers.dart';
import 'live_session_screen.dart';

class CreateSessionScreen extends ConsumerStatefulWidget {
  const CreateSessionScreen({super.key});

  @override
  ConsumerState<CreateSessionScreen> createState() =>
      _CreateSessionScreenState();
}

class _CreateSessionScreenState extends ConsumerState<CreateSessionScreen> {
  Course? _course;
  Facility? _facility;
  bool _submitting = false;
  String? _error;

  Future<void> _submit() async {
    if (_course == null || _facility == null) {
      setState(() => _error = 'Choose a course and a room to continue.');
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      final lecturerId = ref.read(currentUserIdProvider);
      final session = await ref
          .read(attendanceRepositoryProvider)
          .createSession(
            lecturerId: lecturerId!,
            courseId: _course!.id,
            roomId: _facility!.id,
          );
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => LiveSessionScreen(session: session)),
      );
    } catch (_) {
      setState(() => _error = 'Could not start the session. Try again.');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final coursesAsync = ref.watch(coursesProvider);
    final facilitiesAsync = ref.watch(facilitiesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('New class session')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Start a live session',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 6),
              Text(
                'Students check in by scanning a QR code that only works '
                'near this room, on their bound device.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 28),
              Text('Course', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              coursesAsync.when(
                data: (courses) => _Picker<Course>(
                  items: courses,
                  value: _course,
                  labelOf: (c) => c.label,
                  hint: 'Select course',
                  onChanged: (value) => setState(() => _course = value),
                ),
                loading: () => const LinearProgressIndicator(),
                error: (_, _) => Text(
                  'Could not load courses',
                  style: TextStyle(color: scheme.error),
                ),
              ),
              const SizedBox(height: 20),
              Text('Room', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              facilitiesAsync.when(
                data: (facilities) => _Picker<Facility>(
                  items: facilities,
                  value: _facility,
                  labelOf: (f) => f.label,
                  hint: 'Select room',
                  onChanged: (value) => setState(() => _facility = value),
                ),
                loading: () => const LinearProgressIndicator(),
                error: (_, _) => Text(
                  'Could not load rooms',
                  style: TextStyle(color: scheme.error),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 20),
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
                onPressed: _submitting ? null : _submit,
                child: _submitting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Start session'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Picker<T> extends StatelessWidget {
  const _Picker({
    required this.items,
    required this.value,
    required this.labelOf,
    required this.hint,
    required this.onChanged,
  });

  final List<T> items;
  final T? value;
  final String Function(T) labelOf;
  final String hint;
  final ValueChanged<T?> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          isExpanded: true,
          value: value,
          hint: Text(hint),
          items: items
              .map(
                (item) => DropdownMenuItem<T>(
                  value: item,
                  child: Text(labelOf(item)),
                ),
              )
              .toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }
}
