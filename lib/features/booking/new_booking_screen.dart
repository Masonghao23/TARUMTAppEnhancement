import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'models.dart';
import 'providers.dart';

// 30-minute interval time slots from 08:00 AM to 09:00 PM, same list
// tarumt_app's booking_screen.dart used.
const _timeSlots = [
  '08:00 AM', '08:30 AM', '09:00 AM', '09:30 AM',
  '10:00 AM', '10:30 AM', '11:00 AM', '11:30 AM',
  '12:00 PM', '12:30 PM', '01:00 PM', '01:30 PM',
  '02:00 PM', '02:30 PM', '03:00 PM', '03:30 PM',
  '04:00 PM', '04:30 PM', '05:00 PM', '05:30 PM',
  '06:00 PM', '06:30 PM', '07:00 PM', '07:30 PM',
  '08:00 PM', '08:30 PM', '09:00 PM',
];

/// Ported from tarumt_app's NewBookingScreen — same fields, same layout,
/// same colors. Two departures from the original, both deliberate:
///   - the signed-in user books instead of the hardcoded demo student
///     ('24WMR07987') — enforced server-side via auth.uid() in
///     create_booking, invisible on this screen either way.
///   - "Number of Pax" is now actually saved (the original captured it on
///     screen but its _submitBooking() never sent it to Supabase — a bug
///     in the old app). "Venue Type" stays on screen exactly as before but
///     still isn't sent anywhere, matching the original exactly, since
///     it duplicates a fixed property of the facility already chosen.
class NewBookingScreen extends ConsumerStatefulWidget {
  const NewBookingScreen({super.key, required this.facility});

  final BookableFacility facility;

  @override
  ConsumerState<NewBookingScreen> createState() => _NewBookingScreenState();
}

class _NewBookingScreenState extends ConsumerState<NewBookingScreen> {
  static const _primaryBlue = Color(0xFF1C2CA0);

  late DateTime selectedDate;
  bool _isLoading = false;

  String? selectedStartTime = '08:00 AM';
  String? selectedEndTime = '09:00 AM';
  String selectedVenueType = 'Discussion Room (1 PC)';
  final _paxController = TextEditingController(text: '1');

  @override
  void initState() {
    super.initState();
    final today = DateTime.now();
    selectedDate = today.weekday == DateTime.sunday
        ? today.add(const Duration(days: 1))
        : today;
  }

  @override
  void dispose() {
    _paxController.dispose();
    super.dispose();
  }

  Future<void> _selectDate(BuildContext context) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: selectedDate,
      firstDate: now,
      lastDate: now.add(const Duration(days: 90)),
      selectableDayPredicate: (date) => date.weekday != DateTime.sunday,
    );
    if (picked != null && picked != selectedDate) {
      setState(() => selectedDate = picked);
    }
  }

  Future<void> _submitBooking() async {
    setState(() => _isLoading = true);
    try {
      final result = await ref
          .read(bookingRepositoryProvider)
          .createBooking(
            facilityId: widget.facility.id,
            bookingDate: selectedDate,
            startTime: selectedStartTime!,
            endTime: selectedEndTime!,
            pax: int.tryParse(_paxController.text.trim()),
          );

      if (!mounted) return;
      if (!result.success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result.reason ?? 'Booking failed.'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      ref.invalidate(myBookingsProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Booking confirmed!'),
          backgroundColor: Colors.green,
        ),
      );
      Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: _primaryBlue,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'New Booking',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
            fontSize: 18,
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildLabel('Facility'),
            const SizedBox(height: 8),
            Text(
              widget.facility.roomName,
              style: const TextStyle(fontSize: 16, color: Colors.black87),
            ),
            const SizedBox(height: 24),

            _buildLabel('Date'),
            const SizedBox(height: 8),
            InkWell(
              onTap: () => _selectDate(context),
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '${selectedDate.day.toString().padLeft(2, '0')}/${selectedDate.month.toString().padLeft(2, '0')}/${selectedDate.year}',
                      style: TextStyle(fontSize: 16, color: Colors.grey.shade800),
                    ),
                    const Icon(
                      Icons.calendar_today_outlined,
                      color: _primaryBlue,
                      size: 20,
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),

            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildLabel('Start Time'),
                      const SizedBox(height: 8),
                      _buildTimeDropdown(
                        value: selectedStartTime,
                        items: _timeSlots,
                        onChanged: (newValue) {
                          setState(() => selectedStartTime = newValue);
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildLabel('End Time'),
                      const SizedBox(height: 8),
                      _buildTimeDropdown(
                        value: selectedEndTime,
                        items: _timeSlots,
                        onChanged: (newValue) {
                          setState(() => selectedEndTime = newValue);
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 24),

            _buildLabel('Venue Type'),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: Colors.grey.shade300)),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  isExpanded: true,
                  value: selectedVenueType,
                  icon: Icon(Icons.arrow_drop_down, color: Colors.grey.shade600),
                  items: <String>[
                    'Discussion Room (1 PC)',
                    'Discussion Room (2 PCs)',
                  ].map((value) {
                    return DropdownMenuItem(
                      value: value,
                      child: Text(value, style: TextStyle(color: Colors.grey.shade800)),
                    );
                  }).toList(),
                  onChanged: (newValue) {
                    setState(() => selectedVenueType = newValue!);
                  },
                ),
              ),
            ),

            const SizedBox(height: 24),

            _buildLabel('Number of Pax'),
            const SizedBox(height: 8),
            TextFormField(
              controller: _paxController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
                enabledBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                focusedBorder: const UnderlineInputBorder(
                  borderSide: BorderSide(color: _primaryBlue),
                ),
              ),
            ),

            const SizedBox(height: 40),

            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _submitBooking,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _primaryBlue,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  elevation: 0,
                ),
                child: _isLoading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : const Text(
                        'Submit',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildTimeDropdown({
    required String? value,
    required List<String> items,
    required ValueChanged<String?> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(8),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          isExpanded: true,
          value: value,
          icon: Icon(Icons.access_time_rounded, color: Colors.grey.shade600, size: 18),
          items: items.map((time) {
            return DropdownMenuItem(
              value: time,
              child: Text(time, style: TextStyle(fontSize: 14, color: Colors.grey.shade800)),
            );
          }).toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }

  Widget _buildLabel(String text) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: Colors.black87,
      ),
    );
  }
}
