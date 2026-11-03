import 'package:flutter/material.dart';

/// App-wide snackbar with a close control so long or blocked messages
/// can always be dismissed.
void showAppSnackBar(
  BuildContext context,
  String message, {
  Duration duration = const Duration(seconds: 4),
}) {
  if (!context.mounted) return;
  final messenger = ScaffoldMessenger.of(context);
  messenger.clearSnackBars();
  messenger.showSnackBar(
    SnackBar(
      content: Text(message),
      duration: duration,
      showCloseIcon: true,
      behavior: SnackBarBehavior.floating,
    ),
  );
}
