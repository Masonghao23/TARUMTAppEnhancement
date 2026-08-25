import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

/// A labelled dropdown used across the timetable-management forms —
/// [value] is only shown as selected if it's actually present in [items]
/// (async-loaded lists start empty, so a stale selection from a previous
/// build never renders as chosen).
class DropdownPickerField<T> extends StatelessWidget {
  const DropdownPickerField({
    super.key,
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
    return DropdownButtonFormField<T>(
      initialValue: items.contains(value) ? value : null,
      decoration: InputDecoration(hintText: hint),
      items: items
          .map(
            (item) => DropdownMenuItem(
              value: item,
              child: Text(labelOf(item), overflow: TextOverflow.ellipsis),
            ),
          )
          .toList(),
      onChanged: onChanged,
    );
  }
}

/// A tappable field that opens [showTimePicker] and displays the chosen
/// time, styled to match the dropdown fields around it.
class TimePickerField extends StatelessWidget {
  const TimePickerField({
    super.key,
    required this.label,
    required this.time,
    required this.onTap,
  });

  final String label;
  final TimeOfDay time;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppTheme.radiusMd),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label, style: Theme.of(context).textTheme.labelMedium),
            const SizedBox(height: 2),
            Text(
              time.format(context),
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ],
        ),
      ),
    );
  }
}
