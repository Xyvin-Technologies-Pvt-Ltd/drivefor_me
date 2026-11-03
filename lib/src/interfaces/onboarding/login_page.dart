import 'dart:async';
import 'dart:developer';

import 'package:DriveForme/src/data/apis/auth_api.dart';
import 'package:DriveForme/src/data/constants/colour_constants.dart';
import 'package:DriveForme/src/data/constants/style_constants.dart';
import 'package:DriveForme/src/data/models/api_response.dart';
import 'package:DriveForme/src/data/providers/loading_provider.dart';
import 'package:DriveForme/src/data/services/navigation_services.dart';
import 'package:DriveForme/src/data/services/notification_token_service.dart';
import 'package:DriveForme/src/data/services/secure_storage_service.dart';
import 'package:DriveForme/src/data/utils/auth_navigation.dart';
import 'package:DriveForme/src/interfaces/animations/index.dart' as anim;
import 'package:DriveForme/src/interfaces/components/primaryButton.dart';
import 'package:DriveForme/src/data/services/snackbar_service.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:pin_code_fields/pin_code_fields.dart'
    show PinCodeTextField, PinTheme, PinCodeFieldShape, AnimationType
// ignore: library_prefixes
;
import 'package:pin_code_fields/pin_code_fields.dart';

final countryCodeProvider = StateProvider<String?>((ref) => '91');

class PhoneNumberScreen extends ConsumerStatefulWidget {
  const PhoneNumberScreen({super.key});

  @override
  ConsumerState<PhoneNumberScreen> createState() => _PhoneNumberScreenState();
}

class _PhoneNumberScreenState extends ConsumerState<PhoneNumberScreen> {
  late TextEditingController _mobileController;
  late FocusNode _phoneFocusNode;
  bool _showPhoneError = false;

  @override
  void initState() {
    super.initState();
    _mobileController = TextEditingController();
    _phoneFocusNode = FocusNode();
  }

  @override
  void dispose() {
    _mobileController.dispose();
    _phoneFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final isLoading = ref.watch(loadingProvider);

    return Scaffold(
      backgroundColor: kWhite,
      body: SafeArea(
        child: Padding(
          padding: EdgeInsetsGeometry.symmetric(horizontal: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(height: MediaQuery.of(context).size.height * 0.1),
              anim.AnimatedWidgetWrapper(
                animationType: anim.AnimationType.fadeSlideInFromLeft,
                duration: anim.AnimationDuration.normal,
                child: Text('Verify Your Number', style: kHeadTitleR),
              ),
              SizedBox(height: 20),

              Expanded(
                child: SingleChildScrollView(
                  child: Padding(
                    padding: EdgeInsets.only(bottom: bottomInset),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        anim.AnimatedWidgetWrapper(
                          animationType:
                              anim.AnimationType.fadeSlideInFromBottom,
                          duration: anim.AnimationDuration.normal,
                          delayMilliseconds: 200,
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Fixed dial code — read-only underline field matching baseline
                              IgnorePointer(
                                child: SizedBox(
                                  width: 56,
                                  child: TextFormField(
                                    initialValue: '+ 91',
                                    textAlign: TextAlign.center,
                                    style: kLoginPhoneFieldR.copyWith(
                                      color: kTextColor,
                                    ),
                                    decoration: const InputDecoration(
                                      isDense: true,
                                      filled: false,
                                      fillColor: Colors.transparent,
                                      contentPadding: EdgeInsets.zero,
                                      border: UnderlineInputBorder(
                                        borderSide: BorderSide(
                                          color: kPrimaryColor,
                                          width: 1.5,
                                        ),
                                      ),
                                      enabledBorder: UnderlineInputBorder(
                                        borderSide: BorderSide(
                                          color: kPrimaryColor,
                                          width: 1.5,
                                        ),
                                      ),
                                      focusedBorder: UnderlineInputBorder(
                                        borderSide: BorderSide(
                                          color: kPrimaryColor,
                                          width: 1.5,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: TextFormField(
                                  controller: _mobileController,
                                  focusNode: _phoneFocusNode,
                                  keyboardType: TextInputType.phone,
                                  inputFormatters: [
                                    FilteringTextInputFormatter.digitsOnly,
                                    LengthLimitingTextInputFormatter(10),
                                  ],
                                  autovalidateMode:
                                      AutovalidateMode.onUserInteraction,
                                  validator: (value) {
                                    if (!_showPhoneError) {
                                      return null;
                                    }
                                    final number = value?.trim() ?? '';
                                    if (number.isEmpty) {
                                      return 'Mobile number is required';
                                    }
                                    if (!RegExp(r'^[0-9]+$').hasMatch(number)) {
                                      return 'Mobile number must contain only digits';
                                    }
                                    if (number.length != 10) {
                                      return 'Mobile number must be exactly 10 digits';
                                    }
                                    return null;
                                  },
                                  style: kLoginPhoneFieldR,
                                  cursorColor: kPrimaryColor,
                                  onChanged: (_) => setState(() {}),
                                  decoration: InputDecoration(
                                    isDense: true,
                                    filled: false,
                                    fillColor: Colors.transparent,
                                    contentPadding: EdgeInsets.zero,
                                    hintText: 'Mobile Number',
                                    hintStyle: kLoginPhoneFieldR,
                                    enabledBorder: const UnderlineInputBorder(
                                      borderSide: BorderSide(
                                        color: Color(0xFF9E9E9E),
                                      ),
                                    ),
                                    focusedBorder: const UnderlineInputBorder(
                                      borderSide: BorderSide(
                                        color: kPrimaryColor,
                                        width: 1.5,
                                      ),
                                    ),
                                    errorBorder: const UnderlineInputBorder(
                                      borderSide: BorderSide(color: kRed),
                                    ),
                                    focusedErrorBorder:
                                        const UnderlineInputBorder(
                                          borderSide: BorderSide(
                                            color: kRed,
                                            width: 1.5,
                                          ),
                                        ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  child: anim.AnimatedWidgetWrapper(
                    animationType: anim.AnimationType.fadeScaleUp,
                    duration: anim.AnimationDuration.normal,
                    delayMilliseconds: 400,
                    child: Column(
                      children: [
                        SizedBox(
                          height: 55,
                          width: double.infinity,
                          child: primaryButton(
                            label: 'Get OTP',
                            onPressed:
                                (isLoading ||
                                    _mobileController.text.trim().length != 10)
                                ? null
                                : _requestOtp,
                            isLoading: isLoading,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _requestOtp() async {
    setState(() => _showPhoneError = true);

    final digits = _mobileController.text.trim();
    if (digits.isEmpty || !RegExp(r'^[0-9]+$').hasMatch(digits)) {
      _showMessage('Please enter a valid mobile number');
      return;
    }

    if (digits.length != 10) {
      _showMessage('Mobile number must be exactly 10 digits');
      return;
    }

    final countryCode = ref.read(countryCodeProvider) ?? '91';
    final phoneNumber = '+$countryCode$digits';

    ref.read(loadingProvider.notifier).startLoading();

    try {
      log(
        'Calling requestOtp API for: $phoneNumber',
        name: 'PhoneNumberScreen',
      );
      final response = await ref.read(authApiProvider).requestOtp(phoneNumber);
      if (!mounted) return;

      log(
        'requestOtp API Response: success=${response.success}, statusCode=${response.statusCode}, message=${response.message}, data=${response.data}',
        name: 'PhoneNumberScreen',
      );

      if (!response.success) {
        _showMessage(response.message ?? 'Failed to send OTP');
        return;
      }

      final data = nestedData(response.data);
      final otpCode = data?['otpCode'] as String?;
      if (otpCode != null) {
        log('Dev OTP: $otpCode', name: 'PhoneNumberScreen');
      }

      final countryCode = ref.read(countryCodeProvider) ?? '91';

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => OTPScreen(
            fullPhone: digits,
            countryCode: '+$countryCode',
            phoneNumber: phoneNumber,
          ),
        ),
      );
    } catch (e, stackTrace) {
      log(
        'Unexpected error in requestOtp: $e',
        error: e,
        stackTrace: stackTrace,
        name: 'PhoneNumberScreen',
      );
      _showMessage('An error occurred. Please try again.');
    } finally {
      ref.read(loadingProvider.notifier).stopLoading();
    }
  }

  void _showMessage(String message) {
    showAppSnackBar(context, message);
  }
}

class OTPScreen extends ConsumerStatefulWidget {
  final String fullPhone;
  final String countryCode;
  final String phoneNumber;

  const OTPScreen({
    required this.fullPhone,
    required this.countryCode,
    required this.phoneNumber,
    super.key,
  });

  @override
  ConsumerState<OTPScreen> createState() => _OTPScreenState();
}

class _OTPScreenState extends ConsumerState<OTPScreen> {
  Timer? _timer;
  int _start = 59;
  bool _isButtonDisabled = true;

  late TextEditingController _otpController;

  @override
  void initState() {
    super.initState();
    _otpController = TextEditingController();
    startTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    // _otpController.dispose();
    super.dispose();
  }

  void startTimer() {
    _isButtonDisabled = true;
    _start = 60;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_start == 0) {
        setState(() {
          _isButtonDisabled = false;
        });
        timer.cancel();
      } else {
        setState(() {
          _start--;
        });
      }
    });
  }

  String _maskedPhone() {
    final phone = widget.fullPhone;
    if (phone.length <= 3) return '${widget.countryCode}$phone';
    final visible = phone.substring(phone.length - 3);
    final masked = 'X' * (phone.length - 3);
    return '${widget.countryCode}$masked$visible';
  }

  // void resendCode() {
  //   final connectivityStatus = ref.read(connectivityProvider);
  //   if (connectivityStatus == NetworkStatus.offline) {
  //     SnackbarService().showSnackBar(context, 'noInternet'.tr());
  //     return;
  //   }

  //   startTimer();
  //   _resendOtp();
  // }

  // Future<void> _resendOtp() async {
  //   try {
  //     final secureStorage = ref.read(secureStorageServiceProvider);
  //     String? fcmToken;
  //     final existingFcmToken = await secureStorage.getFcmToken();
  //     if (existingFcmToken == null || existingFcmToken.isEmpty) {
  //       await getFcmToken(context, ref);
  //       fcmToken = await secureStorage.getFcmToken();
  //     } else {
  //       fcmToken = existingFcmToken;
  //     }

  //     final authLoginApi = ref.read(authLoginApiProvider);
  //     final response = await authLoginApi.Login(
  //       widget.fullPhone,
  //       fcmToken ?? '',
  //     );

  //     if (response.success) {
  //       SnackbarService().showSnackBar(context, 'otpResentSuccess'.tr());
  //       log('OTP resent successfully', name: 'OTPScreen');
  //     } else {
  //       SnackbarService().showSnackBar(
  //         context,
  //         response.message ?? 'failedToResendOtp'.tr(),
  //       );
  //       log('Error resending OTP: ${response.message}', name: 'OTPScreen');
  //     }
  //   } catch (e) {
  //     SnackbarService().showSnackBar(context, 'Error: $e');
  //     log('Error resending OTP: $e', name: 'OTPScreen');
  //   }
  // }

  @override
  Widget build(BuildContext context) {
    final isLoading = ref.watch(loadingProvider);

    return Scaffold(
      resizeToAvoidBottomInset: true,
      backgroundColor: kWhite,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Scrollable content ──────────────────────────────────────
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(height: MediaQuery.of(context).size.height * 0.1),

                    // Title
                    anim.AnimatedWidgetWrapper(
                      animationType: anim.AnimationType.fadeSlideInFromLeft,
                      duration: anim.AnimationDuration.normal,
                      child: Text('Enter OTP', style: kHeadTitleR),
                    ),
                    const SizedBox(height: 12),

                    // Subtitle — masked phone highlighted in blue
                    anim.AnimatedWidgetWrapper(
                      animationType: anim.AnimationType.fadeSlideInFromLeft,
                      duration: anim.AnimationDuration.normal,
                      delayMilliseconds: 100,
                      child: RichText(
                        text: TextSpan(
                          style: kLoginSubtitleR,
                          children: [
                            const TextSpan(
                              text: 'We have sent a 6 digit OTP to ',
                            ),
                            TextSpan(
                              text: _maskedPhone(),
                              style: kLoginSubtitleAccentSB,
                            ),
                            const TextSpan(
                              text: ' number and you can use to login',
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 40),

                    // 6-digit OTP — field width scales to screen so 6 cells fit
                    anim.AnimatedWidgetWrapper(
                      animationType: anim.AnimationType.fadeSlideInFromBottom,
                      duration: anim.AnimationDuration.normal,
                      delayMilliseconds: 200,
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          const otpLength = 6;
                          const fieldGap = 12.0;
                          final fieldWidth =
                              ((constraints.maxWidth -
                                          fieldGap * (otpLength - 1)) /
                                      otpLength)
                                  .clamp(44.0, 56.0);
                          final fontSize = fieldWidth >= 52 ? 34.0 : 28.0;

                          return PinCodeTextField(
                            appContext: context,
                            length: otpLength,
                            obscureText: false,
                            keyboardType: TextInputType.number,
                            animationType: AnimationType.scale,
                            textStyle: kStyle(
                              kMedium,
                              fontSize,
                              color: kTextColor,
                            ),
                            pinTheme: PinTheme(
                              shape: PinCodeFieldShape.underline,
                              fieldHeight: 56,
                              fieldWidth: fieldWidth,
                              selectedColor: kPrimaryColor,
                              activeColor: kPrimaryColor,
                              inactiveColor: kBorder,
                              activeFillColor: Colors.transparent,
                              selectedFillColor: Colors.transparent,
                              inactiveFillColor: Colors.transparent,
                              borderWidth: 1.5,
                            ),
                            animationDuration: const Duration(
                              milliseconds: 300,
                            ),
                            backgroundColor: Colors.transparent,
                            enableActiveFill: true,
                            controller: _otpController,
                            onChanged: (value) {},
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 28),

                    // "Didn't get SMS?" + countdown / resend
                    anim.AnimatedWidgetWrapper(
                      animationType: anim.AnimationType.fadeSlideInFromLeft,
                      duration: anim.AnimationDuration.normal,
                      delayMilliseconds: 300,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          SizedBox(
                            width: double.infinity,
                            child: Text(
                              "Didi'nt get SMS?",
                              textAlign: TextAlign.center,
                              style: kLoginResendPromptM,
                            ),
                          ),
                          const SizedBox(height: 6),
                          if (_isButtonDisabled)
                            RichText(
                              text: TextSpan(
                                style: kLoginResendPromptM,
                                children: [
                                  const TextSpan(text: 'Get a new OTP in '),
                                  TextSpan(
                                    text:
                                        '00:${_start.toString().padLeft(2, '0')}',
                                    style: kLoginResendTimerSB,
                                  ),
                                ],
                              ),
                            )
                          else
                            GestureDetector(
                              onTap: _resendOtp,
                              child: Text(
                                'Resend OTP',
                                style: kLoginResendActionSB,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // ── Verify OTP button pinned to bottom ───────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
              child: anim.AnimatedWidgetWrapper(
                animationType: anim.AnimationType.fadeScaleUp,
                duration: anim.AnimationDuration.normal,
                delayMilliseconds: 400,
                child: primaryButton(
                  label: 'Verify OTP',
                  buttonHeight: MediaQuery.of(context).size.height * 0.065,
                  fontSize: 16,
                  onPressed: isLoading ? null : _verifyOtp,
                  isLoading: isLoading,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _resendOtp() async {
    startTimer();
    ref.read(loadingProvider.notifier).startLoading();

    try {
      log(
        'Calling requestOtp (resend) API for: ${widget.phoneNumber}',
        name: 'OTPScreen',
      );
      final response = await ref
          .read(authApiProvider)
          .requestOtp(widget.phoneNumber);
      if (!mounted) return;

      log(
        'requestOtp (resend) API Response: success=${response.success}, statusCode=${response.statusCode}, message=${response.message}, data=${response.data}',
        name: 'OTPScreen',
      );

      if (!response.success) {
        _showMessage(response.message ?? 'Failed to resend OTP');
        return;
      }

      final otpCode = nestedData(response.data)?['otpCode'] as String?;
      if (otpCode != null) {
        log('Dev OTP: $otpCode', name: 'OTPScreen');
      }

      _showMessage('OTP sent again');
    } catch (e, stackTrace) {
      log(
        'Unexpected error in resendOtp: $e',
        error: e,
        stackTrace: stackTrace,
        name: 'OTPScreen',
      );
      _showMessage('Failed to resend OTP. Please try again.');
    } finally {
      ref.read(loadingProvider.notifier).stopLoading();
    }
  }

  Future<void> _verifyOtp() async {
    final otp = _otpController.text.trim();
    if (otp.length != 6) {
      _showMessage('Please enter the 6-digit OTP');
      return;
    }

    ref.read(loadingProvider.notifier).startLoading();

    try {
      log(
        'Calling verifyOtp API for phone: ${widget.phoneNumber}, otp: $otp',
        name: 'OTPScreen',
      );
      final response = await ref
          .read(authApiProvider)
          .verifyOtp(phoneNumber: widget.phoneNumber, otp: otp);
      if (!mounted) return;

      log(
        'verifyOtp API Response: success=${response.success}, statusCode=${response.statusCode}, message=${response.message}, data=${response.data}',
        name: 'OTPScreen',
      );

      if (!response.success) {
        _showMessage(response.message ?? 'Invalid OTP');
        return;
      }

      final data = nestedData(response.data);
      final userId = data?['userId']?.toString();
      final token = data?['token'] as String?;
      final onboardingStatus = data?['onboardingStatus'] as String?;

      if (userId == null || userId.isEmpty) {
        _showMessage('Invalid response from server');
        return;
      }

      if (token == null || token.isEmpty) {
        _showMessage('Invalid response from server');
        return;
      }

      final storage = ref.read(secureStorageServiceProvider);
      await storage.saveUserId(userId);
      await storage.saveAuthToken(token);
      await storage.savePhoneNumber(widget.phoneNumber);
      await storage.saveOnboardingStatus(onboardingStatus ?? 'profile_pending');

      await ref
          .read(notificationTokenServiceProvider)
          .registerTokenIfAvailable();

      final route = routeForOnboardingStatus(
        onboardingStatus ?? 'profile_pending',
      );
      NavigationService().pushNamedAndRemoveUntil(route);
    } catch (e, stackTrace) {
      log(
        'Unexpected error in verifyOtp: $e',
        error: e,
        stackTrace: stackTrace,
        name: 'OTPScreen',
      );
      _showMessage('An error occurred during verification. Please try again.');
    } finally {
      ref.read(loadingProvider.notifier).stopLoading();
    }
  }

  void _showMessage(String message) {
    showAppSnackBar(context, message);
  }
}
