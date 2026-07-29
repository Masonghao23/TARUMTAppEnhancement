import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../data/admin_repository.dart';
import '../providers.dart';

class CreateUserScreen extends ConsumerStatefulWidget {
  const CreateUserScreen({super.key});

  @override
  ConsumerState<CreateUserScreen> createState() => _CreateUserScreenState();
}

class _CreateUserScreenState extends ConsumerState<CreateUserScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _campusIdController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  String _role = 'student';
  bool _isSubmitting = false;

  @override
  void dispose() {
    _nameController.dispose();
    _campusIdController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSubmitting = true);
    try {
      await ref
          .read(adminRepositoryProvider)
          .createUser(
            email: _emailController.text.trim(),
            password: _passwordController.text,
            name: _nameController.text.trim(),
            campusId: _campusIdController.text.trim(),
            role: _role,
          );

      ref.invalidate(userSearchProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${_nameController.text.trim()} account created.'),
        ),
      );
      Navigator.of(context).pop(true);
    } on AdminCreateUserException catch (e) {
      _showError(e.message);
    } catch (_) {
      _showError('Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  int get _campusIdLength => _role == 'student' ? 7 : 4;

  String get _campusIdExample => _role == 'student' ? '2408009' : '1234';

  String? _validateCampusId(String? value) {
    final trimmed = value?.trim() ?? '';
    final pattern = RegExp('^[0-9]{$_campusIdLength}\$');
    if (!pattern.hasMatch(trimmed)) {
      return _role == 'student'
          ? 'Student ID must be 7 digits: 2-digit enrolment year + 5-digit index (e.g. $_campusIdExample)'
          : 'Staff ID must be a 4-digit number (e.g. $_campusIdExample)';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Create account')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _SectionLabel('Role'),
                const SizedBox(height: 10),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(
                      value: 'student',
                      label: Text('Student'),
                      icon: Icon(Icons.school_outlined),
                    ),
                    ButtonSegment(
                      value: 'staff',
                      label: Text('Staff'),
                      icon: Icon(Icons.badge_outlined),
                    ),
                  ],
                  selected: {_role},
                  onSelectionChanged: (value) {
                    setState(() => _role = value.first);
                    _formKey.currentState?.validate();
                  },
                  style: SegmentedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(AppTheme.radiusLg),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _SectionLabel('Personal details'),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _nameController,
                        decoration: const InputDecoration(
                          labelText: 'Full name',
                          prefixIcon: Icon(Icons.person_outline),
                        ),
                        validator: (value) => (value == null || value.trim().isEmpty)
                            ? 'Required'
                            : null,
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _campusIdController,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(_campusIdLength),
                        ],
                        autovalidateMode: AutovalidateMode.onUserInteraction,
                        decoration: InputDecoration(
                          labelText: _role == 'student' ? 'Student ID' : 'Staff ID',
                          prefixIcon: const Icon(Icons.badge_outlined),
                          helperText: _role == 'student'
                              ? 'Year enrolled + index, e.g. $_campusIdExample'
                              : '4-digit staff number, e.g. $_campusIdExample',
                        ),
                        validator: _validateCampusId,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(AppTheme.radiusLg),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _SectionLabel('Account credentials'),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        decoration: const InputDecoration(
                          labelText: 'Email',
                          prefixIcon: Icon(Icons.mail_outline),
                        ),
                        validator: (value) {
                          if (value == null || !value.contains('@')) {
                            return 'Enter a valid email address';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _passwordController,
                        decoration: const InputDecoration(
                          labelText: 'Temporary password',
                          prefixIcon: Icon(Icons.key_outlined),
                          helperText:
                              'At least 8 characters. Share this with the user securely.',
                        ),
                        validator: (value) {
                          if (value == null || value.length < 8) {
                            return 'Minimum 8 characters';
                          }
                          return null;
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 28),
                ElevatedButton(
                  onPressed: _isSubmitting ? null : _submit,
                  child: _isSubmitting
                      ? SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: scheme.onPrimary,
                          ),
                        )
                      : const Text('Create account'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: Theme.of(context).textTheme.labelMedium,
    );
  }
}
