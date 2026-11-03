import 'package:DriveForme/src/data/apis/trip_api.dart';
import 'package:DriveForme/src/data/constants/colour_constants.dart';
import 'package:DriveForme/src/data/constants/style_constants.dart';
import 'package:DriveForme/src/data/models/trip_model.dart';
import 'package:DriveForme/src/data/providers/active_trip_provider.dart';
import 'package:DriveForme/src/data/services/navigation_services.dart';
import 'package:DriveForme/src/interfaces/components/primaryButton.dart';
import 'package:DriveForme/src/data/services/snackbar_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class DriverRatingPage extends ConsumerStatefulWidget {
  final String tripMongoId;
  final String driverId;
  final String driverName;
  final double driverRating;
  final int driverTrips;
  final String? driverPhotoUrl;
  final String vehicleTypes;

  const DriverRatingPage({
    super.key,
    this.tripMongoId = '',
    this.driverId = '',
    this.driverName = TripModel.noNameFound,
    this.driverRating = 0,
    this.driverTrips = 0,
    this.driverPhotoUrl,
    this.vehicleTypes = '—',
  });

  @override
  ConsumerState<DriverRatingPage> createState() => _DriverRatingPageState();
}

class _DriverRatingPageState extends ConsumerState<DriverRatingPage> {
  static const _chipSelectedBorder = AppColors.selectedChipGold;
  static const _commentFieldBg = AppColors.commentFieldBackground;
  static const _smileyBlue = AppColors.linkBlue;

  static const _feedbackTags = [
    'Excellent Service',
    'Friendly Driver',
    'Well Maintained Car',
    'Clean & Comfortable',
  ];

  int _selectedRating = 5;
  final Set<String> _selectedTags = {};
  final TextEditingController _commentController = TextEditingController();
  bool _isSubmitting = false;

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _submitRating() async {
    if (widget.tripMongoId.isEmpty) {
      NavigationService().pushNamedReplacement('thank_you');
      return;
    }

    setState(() => _isSubmitting = true);

    final response = await ref.read(tripApiProvider).rateTrip(
          widget.tripMongoId,
          stars: _selectedRating,
          feedbackTags: _selectedTags.toList(),
          comment: _commentController.text,
        );

    if (!mounted) return;
    setState(() => _isSubmitting = false);

    if (!response.success) {
      showAppSnackBar(
        context,
        response.message ?? 'Failed to submit rating.',
      );
      return;
    }

    await ref.read(activeTripProvider.notifier).clear();
    if (!mounted) return;
    NavigationService().pushNamedReplacement('thank_you');
  }

  void _skipRating() {
    NavigationService().pushNamedReplacement('thank_you');
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    return Scaffold(
      backgroundColor: kScreenBg,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _RatingHeader(onBack: () => Navigator.of(context).maybePop()),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _DriverProfileCard(
                      driverName: widget.driverName,
                      driverRating: widget.driverRating,
                      driverTrips: widget.driverTrips,
                      driverPhotoUrl: widget.driverPhotoUrl,
                      vehicleTypes: widget.vehicleTypes,
                    ),
                    const SizedBox(height: 20),
                    const Divider(height: 1, color: kCardBorder),
                    const SizedBox(height: 28),
                    Text(
                      'How was your ride?',
                      textAlign: TextAlign.center,
                      style: kDriverRatingQuestionSB,
                    ),
                    const SizedBox(height: 20),
                    _RatingStars(
                      rating: _selectedRating,
                      onRatingChanged: (value) {
                        setState(() => _selectedRating = value);
                      },
                    ),
                    const SizedBox(height: 28),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      alignment: WrapAlignment.center,
                      children: _feedbackTags.map((tag) {
                        final isSelected = _selectedTags.contains(tag);
                        return _FeedbackChip(
                          label: tag,
                          isSelected: isSelected,
                          selectedBorderColor: _chipSelectedBorder,
                          onTap: () {
                            setState(() {
                              if (isSelected) {
                                _selectedTags.remove(tag);
                              } else {
                                _selectedTags.add(tag);
                              }
                            });
                          },
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 24),
                    _CommentField(
                      controller: _commentController,
                      backgroundColor: _commentFieldBg,
                      smileyColor: _smileyBlue,
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, bottomInset + 16),
              child: Column(
                children: [
                  primaryButton(
                    label: _isSubmitting ? 'Submitting...' : 'Submit Rating',
                    onPressed: _isSubmitting ? () {} : _submitRating,
                    buttonColor: kTripCtaBlue,
                    buttonHeight: 58,
                    fontSize: 18,
                  ),
                  const SizedBox(height: 10),
                  TextButton(
                    onPressed: _isSubmitting ? null : _skipRating,
                    child: Text('Skip', style: kDriverRatingChipR),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RatingHeader extends StatelessWidget {
  final VoidCallback onBack;

  const _RatingHeader({required this.onBack});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 16, 12),
      child: Row(
        children: [
          IconButton(
            onPressed: onBack,
            icon: const Icon(
              Icons.arrow_back_ios_new,
              size: 22,
              color: kTextColor,
            ),
            padding: const EdgeInsets.all(12),
            constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
          ),
          Text(
            'Rate your Driver',
            style: kDriverRatingAppBarSB,
          ),
        ],
      ),
    );
  }
}

class _DriverProfileCard extends StatelessWidget {
  final String driverName;
  final double driverRating;
  final int driverTrips;
  final String? driverPhotoUrl;
  final String vehicleTypes;

  const _DriverProfileCard({
    required this.driverName,
    required this.driverRating,
    required this.driverTrips,
    this.driverPhotoUrl,
    required this.vehicleTypes,
  });

  @override
  Widget build(BuildContext context) {
    final photoUrl = driverPhotoUrl?.trim();
    final hasPhoto = photoUrl != null && photoUrl.isNotEmpty;

    return Row(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: hasPhoto
              ? Image.network(
                  photoUrl,
                  width: 72,
                  height: 72,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => _driverPlaceholder(),
                )
              : _driverPlaceholder(),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(driverName, style: kDriverRatingNameSB),
              const SizedBox(height: 6),
              Row(
                children: [
                  Text(
                    driverRating.toStringAsFixed(1),
                    style: kDriverRatingStatR,
                  ),
                  const SizedBox(width: 4),
                  ..._buildProfileStars(driverRating),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      '• $driverTrips trips',
                      style: kDriverRatingStatMutedR,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(vehicleTypes, style: kDriverRatingVehicleR),
            ],
          ),
        ),
        const SizedBox(width: 8),
        _ActionCircle(color: kActiveGreen, icon: Icons.chat_rounded),
        const SizedBox(width: 8),
        _ActionCircle(color: kBlue, icon: Icons.phone_in_talk_rounded),
      ],
    );
  }

  Widget _driverPlaceholder() {
    return Container(
      width: 72,
      height: 72,
      color: kChipGreyBg,
      child: const Icon(Icons.person, color: kMutedText, size: 36),
    );
  }

  List<Widget> _buildProfileStars(double rating) {
    final fullStars = rating.floor();
    final hasHalf = rating - fullStars >= 0.25;

    return List.generate(5, (index) {
      IconData icon;
      if (index < fullStars) {
        icon = Icons.star_rounded;
      } else if (index == fullStars && hasHalf) {
        icon = Icons.star_half_rounded;
      } else {
        icon = Icons.star_outline_rounded;
      }
      return Icon(icon, size: 14, color: AppColors.ratingGold);
    });
  }
}

class _ActionCircle extends StatelessWidget {
  final Color color;
  final IconData icon;

  const _ActionCircle({required this.color, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color,
      shape: const CircleBorder(),
      child: InkWell(
        onTap: () {},
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: 42,
          height: 42,
          child: Icon(icon, color: kWhite, size: 20),
        ),
      ),
    );
  }
}

class _RatingStars extends StatelessWidget {
  final int rating;
  final ValueChanged<int> onRatingChanged;

  const _RatingStars({required this.rating, required this.onRatingChanged});

  static const _starActiveColor = AppColors.starGold;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(5, (index) {
        final starIndex = index + 1;
        final isFilled = starIndex <= rating;

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: InkWell(
            onTap: () => onRatingChanged(starIndex),
            borderRadius: BorderRadius.circular(8),
            child: Icon(
              isFilled ? Icons.star_rounded : Icons.star_outline_rounded,
              size: 40,
              color: isFilled ? _starActiveColor : AppColors.divider,
            ),
          ),
        );
      }),
    );
  }
}

class _FeedbackChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final Color selectedBorderColor;
  final VoidCallback onTap;

  const _FeedbackChip({
    required this.label,
    required this.isSelected,
    required this.selectedBorderColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: kWhite,
      shape: StadiumBorder(
        side: BorderSide(
          color: isSelected ? selectedBorderColor : kCardBorder,
          width: isSelected ? 1.5 : 1,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        customBorder: const StadiumBorder(),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Text(label, style: kDriverRatingChipR),
        ),
      ),
    );
  }
}

class _CommentField extends StatelessWidget {
  final TextEditingController controller;
  final Color backgroundColor;
  final Color smileyColor;

  const _CommentField({
    required this.controller,
    required this.backgroundColor,
    required this.smileyColor,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      maxLines: 1,
      style: kDriverRatingCommentR,
      decoration: InputDecoration(
        hintText: 'Leave a Comment(Optional)',
        hintStyle: kDriverRatingCommentHintR,
        filled: true,
        fillColor: backgroundColor,
        contentPadding: const EdgeInsets.fromLTRB(18, 16, 12, 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(28),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(28),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(28),
          borderSide: BorderSide.none,
        ),
        suffixIcon: Padding(
          padding: const EdgeInsets.only(right: 8),
          child: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: smileyColor,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.sentiment_satisfied_alt_rounded,
              color: kWhite,
              size: 22,
            ),
          ),
        ),
        suffixIconConstraints: const BoxConstraints(
          minWidth: 44,
          minHeight: 44,
        ),
      ),
    );
  }
}
