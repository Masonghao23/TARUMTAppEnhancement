import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'new_booking_screen.dart';
import 'providers.dart';

class BookingScreen extends ConsumerWidget {
  const BookingScreen({super.key});

  static const _primaryBlue = Color(0xFF1C2CA0);
  static const _backgroundColor = Color(0xFFF7F8FC);
  static const _textDark = Color(0xFF1A233B);

  /// Builds the booking screen interface.
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: _backgroundColor,
        appBar: AppBar(
          backgroundColor: _primaryBlue,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () => Navigator.pop(context),
          ),
          title: const Text(
            'Facility Bookings',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 18,
            ),
          ),
          centerTitle: true,
          bottom: const PreferredSize(
            preferredSize: Size.fromHeight(48.0),
            child: Align(
              alignment: Alignment.center,
              child: TabBar(
                indicatorColor: Colors.white,
                indicatorWeight: 3.0,
                indicatorSize: TabBarIndicatorSize.tab,
                labelColor: Colors.white,
                unselectedLabelColor: Colors.white70,
                labelStyle: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                tabs: [
                  Tab(text: 'Facility'),
                  Tab(text: 'Booking Guideline'),
                ],
              ),
            ),
          ),
        ),
        body: TabBarView(
          children: [
            _FacilityListTab(ref: ref),
            const _GuidelinesTab(),
          ],
        ),
      ),
    );
  }
}

class _FacilityListTab extends ConsumerWidget {
  const _FacilityListTab({required this.ref});

  final WidgetRef ref;

  /// Builds the facility list tab interface.
  @override
  Widget build(BuildContext context, WidgetRef _) {
    final facilitiesAsync = ref.watch(bookableFacilitiesProvider);

    return facilitiesAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(
        child: Text(
          'Error loading facilities: $error',
          style: const TextStyle(color: Colors.red),
          textAlign: TextAlign.center,
        ),
      ),
      data: (facilities) {
        final bookable = facilities
            .where((f) => f.isAvailable && f.capacity != null)
            .toList();

        if (bookable.isEmpty) {
          return const Center(
            child: Text(
              'No facilities found.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, color: Colors.grey),
            ),
          );
        }

        return SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Facility',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: BookingScreen._textDark,
                ),
              ),
              const SizedBox(height: 16),
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: bookable.length,
                itemBuilder: (context, index) {
                  final facility = bookable[index];
                  return Container(
                    margin: const EdgeInsets.only(bottom: 12.0),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(18.0),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.03),
                          blurRadius: 8,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 20.0,
                        vertical: 6.0,
                      ),
                      title: Text(
                        facility.roomName,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: Colors.grey.shade800,
                        ),
                      ),
                      trailing: const Icon(
                        Icons.add_circle_outline_rounded,
                        color: BookingScreen._primaryBlue,
                        size: 24,
                      ),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => NewBookingScreen(
                            facility: facility,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }
}

class _GuidelinesTab extends StatelessWidget {
  const _GuidelinesTab();

  static const _guidelines = [
    'Minimum 1 person. Do not hog the discussion room if it is not in use.',
    'Room can be booked 1 day in advance.',
    'Maximum 2 hours per booking; extension is subject to room availability.',
    'Room will be assigned based on the number of users.',
    "Cancellation can be done under 'Booking Details Page'.",
    'A Group Representative is required to make the booking.',
    'Student must CHECK-IN / CHECK-OUT at the Internet Lab Counter. Present your student ID card for registration.',
    'Room booked will be forfeited after 10 minutes if no-show. The system will block booking for all group members for the rest of the day.',
    'Do not add, move, or remove furniture inside the discussion room.',
  ];

  /// Builds the guidelines tab interface.
  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: true,
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 24.0),
        child: Container(
          padding: const EdgeInsets.all(20.0),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18.0),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.03),
                blurRadius: 8,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Booking Guidelines',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: BookingScreen._textDark,
                ),
              ),
              const SizedBox(height: 16),
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _guidelines.length,
                separatorBuilder: (context, index) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${index + 1}. ',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: BookingScreen._primaryBlue,
                        ),
                      ),
                      Expanded(
                        child: Text(
                          _guidelines[index],
                          style: TextStyle(
                            fontSize: 14,
                            height: 1.4,
                            color: Colors.grey.shade800,
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 24),
              const Divider(),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12.0),
                decoration: BoxDecoration(
                  color: Colors.amber.shade50,
                  borderRadius: BorderRadius.circular(10.0),
                  border: Border.all(color: Colors.amber.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.info_outline, size: 18, color: Colors.amber.shade900),
                        const SizedBox(width: 8),
                        Text(
                          'Important Notes',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            color: Colors.amber.shade900,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '• Discussion rooms are strictly to be used for academic purposes only.\n'
                      '• Projecting from movie projectors is prohibited due to copyright issues.',
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.4,
                        color: Colors.amber.shade900,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }
}
