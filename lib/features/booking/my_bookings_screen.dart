import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'models.dart';
import 'providers.dart';

class MyBookingsScreen extends ConsumerWidget {
  const MyBookingsScreen({super.key});

  static const _primaryBlue = Color(0xFF1C2CA0);
  static const _backgroundColor = Color(0xFFF7F8FC);
  static const _textDark = Color(0xFF1A233B);

  /// Parses a booking time label into a comparable time value.
  static DateTime _parseTimeString(String timeStr, DateTime referenceDate) {
    try {
      final parts = timeStr.trim().split(' ');
      final timeParts = parts[0].split(':');
      var hour = int.parse(timeParts[0]);
      final minute = int.parse(timeParts[1]);
      final period = parts.length > 1 ? parts[1].toUpperCase() : 'AM';
      if (period == 'PM' && hour < 12) hour += 12;
      if (period == 'AM' && hour == 12) hour = 0;
      return DateTime(
        referenceDate.year,
        referenceDate.month,
        referenceDate.day,
        hour,
        minute,
      );
    } catch (_) {
      return DateTime(
        referenceDate.year,
        referenceDate.month,
        referenceDate.day,
        23,
        59,
      );
    }
  }

  /// Formats a date for display.
  static String _fmtDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  /// Builds the my bookings screen interface.
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bookingsAsync = ref.watch(myBookingsProvider);

    return Scaffold(
      backgroundColor: _backgroundColor,
      appBar: AppBar(
        backgroundColor: _primaryBlue,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'My Bookings',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
            fontSize: 18,
          ),
        ),
      ),
      body: bookingsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Text(
            'Error loading bookings: $error',
            style: const TextStyle(color: Colors.red),
            textAlign: TextAlign.center,
          ),
        ),
        data: (bookings) {
          if (bookings.isEmpty) {
            return const Center(
              child: Text('No bookings found.', style: TextStyle(fontSize: 16, color: Colors.grey)),
            );
          }

          final now = DateTime.now();
          final todayStr =
              '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

          final active = <Booking>[];
          final past = <Booking>[];
          for (final b in bookings) {
            if (b.status == 'CANCELLED' || b.status == 'CHECKED OUT' || b.status == 'NO SHOW') {
              past.add(b);
              continue;
            }
            final dateStr =
                '${b.bookingDate.year}-${b.bookingDate.month.toString().padLeft(2, '0')}-${b.bookingDate.day.toString().padLeft(2, '0')}';
            final cmp = dateStr.compareTo(todayStr);
            if (cmp > 0) {
              active.add(b);
            } else if (cmp < 0) {
              past.add(b);
            } else {
              final parsedEndTime = _parseTimeString(b.endTime, now);
              (now.isBefore(parsedEndTime) ? active : past).add(b);
            }
          }

          return SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(20.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildSectionTitle('Active'),
                const SizedBox(height: 12),
                if (active.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8.0),
                    child: Text('No active bookings.', style: TextStyle(color: Colors.grey)),
                  )
                else
                  ...active.map((b) => _buildBookingCardFromDb(b)),
                const SizedBox(height: 40),
                _buildSectionTitle('Past Bookings'),
                const SizedBox(height: 12),
                if (past.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8.0),
                    child: Text('No past bookings.', style: TextStyle(color: Colors.grey)),
                  )
                else
                  ...past.map((b) => _buildBookingCardFromDb(b, isPast: true)),
              ],
            ),
          );
        },
      ),
    );
  }

  /// Builds a booking card from a stored booking.
  Widget _buildBookingCardFromDb(Booking booking, {bool isPast = false}) {
    final roomName = booking.roomName;
    final location = booking.buildingName ?? 'TAR UMT Campus';
    final date = _fmtDate(booking.bookingDate);
    final timeStr = '${booking.startTime} - ${booking.endTime}';

    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: _buildBookingCard(
        roomName: roomName,
        location: location,
        date: date,
        time: timeStr,
        status: booking.status,
        isPast: isPast,
      ),
    );
  }

  /// Builds a heading for a booking section.
  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: _textDark),
    );
  }

  /// Builds a card displaying booking details.
  Widget _buildBookingCard({
    required String roomName,
    required String location,
    required String date,
    required String time,
    String? status,
    required bool isPast,
  }) {
    Color badgeBgColor = Colors.greenAccent.shade100.withValues(alpha: 0.4);
    Color badgeTextColor = Colors.green;

    if (status == 'CHECKED IN') {
      badgeBgColor = Colors.blue.shade100;
      badgeTextColor = _primaryBlue;
    } else if (status == 'CANCELLED' || status == 'NO SHOW') {
      badgeBgColor = Colors.red.shade100;
      badgeTextColor = Colors.red;
    } else if (status == 'CHECKED OUT') {
      badgeBgColor = Colors.grey.shade300;
      badgeTextColor = Colors.grey.shade800;
    }

    return Container(
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16.0),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            roomName,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: isPast ? Colors.grey.shade700 : _textDark,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 5,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildIconText(
                      icon: Icons.location_on_outlined,
                      iconColor: Colors.redAccent,
                      text: location,
                    ),
                    if (status != null) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: badgeBgColor,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          status,
                          style: TextStyle(
                            color: badgeTextColor,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Expanded(
                flex: 4,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildIconText(
                      icon: Icons.calendar_today_outlined,
                      iconColor: Colors.indigoAccent.shade200,
                      text: date,
                    ),
                    const SizedBox(height: 8),
                    _buildIconText(
                      icon: Icons.access_time,
                      iconColor: Colors.grey.shade500,
                      text: time,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Builds an icon and text row for booking details.
  Widget _buildIconText({required IconData icon, required Color iconColor, required String text}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 14, color: iconColor),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            style: TextStyle(fontSize: 11, color: Colors.grey.shade600, height: 1.2),
          ),
        ),
      ],
    );
  }
}
