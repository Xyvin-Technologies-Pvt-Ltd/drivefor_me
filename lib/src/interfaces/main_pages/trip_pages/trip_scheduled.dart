import 'package:DriveForme/src/data/constants/colour_constants.dart';
import 'package:DriveForme/src/data/constants/style_constants.dart';
import 'package:DriveForme/src/data/services/navigation_services.dart';
import 'package:DriveForme/src/interfaces/components/primaryButton.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

class TripScheduledPage extends ConsumerWidget {
  final DateTime scheduledAt;
  final Map<String, dynamic> bookingArgs;

  const TripScheduledPage({
    super.key,
    required this.scheduledAt,
    this.bookingArgs = const {},
  });

  static final _scheduledDateTimeFormat = DateFormat('d MMMM • hh:mm a');

  void _goHome() {
    NavigationService().pushNamedAndRemoveUntil('navbar');
  }

  void _viewBooking() {
    NavigationService().pushNamed(
      'scheduled_trip_details',
      arguments: {
        ...bookingArgs,
        'scheduledAt': scheduledAt,
      },
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheduledLabel = _scheduledDateTimeFormat.format(
      scheduledAt.toLocal(),
    );

    return Scaffold(
      backgroundColor: kScreenBg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            children: [
              const Spacer(flex: 2),
              Image.asset(
                'assets/pngs/trip_scheduled.png',
                height: 300,
                fit: BoxFit.contain,
              ),
              const SizedBox(height: 32),
              RichText(
                textAlign: TextAlign.center,
                text: TextSpan(
                  style: kBookingConfirmedTitleSB,
                  children: [
                    const TextSpan(text: 'Your Ride is '),
                    TextSpan(text: 'Scheduled!', style: kTripScheduledAccentSB),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'Your booking has been confirmed for',
                textAlign: TextAlign.center,
                style: kTripScheduledBodyR,
              ),
              const SizedBox(height: 8),
              Text(
                scheduledLabel,
                textAlign: TextAlign.center,
                style: kTripScheduledDateB,
              ),
              const SizedBox(height: 14),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text(
                  "We'll notify you when a driver accepts. Trip details stay here until the scheduled pickup time.",
                  textAlign: TextAlign.center,
                  style: kTripScheduledBodyR,
                ),
              ),
              const Spacer(flex: 3),
              primaryButton(
                label: 'View Booking',
                onPressed: _viewBooking,
                buttonHeight: 56,
                fontSize: 16,
                buttonColor: kTripCtaBlue,
              ),
              const SizedBox(height: 14),
              TextButton(
                onPressed: _goHome,
                style: TextButton.styleFrom(
                  foregroundColor: kTripCtaBlue,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                child: Text('Back to Home', style: kTripScheduledLinkSB),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}
