import 'package:cherry_toast/cherry_toast.dart';
import 'package:cherry_toast/resources/arrays.dart';
import 'package:delivery_boy_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

enum SnackbarType { success, error }

showAppSnackbar({
  required BuildContext context,
  required SnackbarType type,
  required String description,
}) {
  switch (type) {
    case SnackbarType.success:
      CherryToast.success(
        toastDuration: Duration(milliseconds: 2000),
        height: 70,
        toastPosition: Position.top,
        shadowColor: Colors.white,

        animationType: AnimationType.fromTop,
        displayCloseButton: false,
        backgroundColor: Colors.green.withAlpha(40),
        description: Text(
          description,
          style: const TextStyle(color: Colors.green),
        ),
        title: Text(
          context.l10n.toastSuccess,
          style: const TextStyle(
            color: Colors.green,
            fontWeight: FontWeight.bold,
          ),
        ),
      ).show(context);
      break;

    case SnackbarType.error:
      CherryToast.error(
        toastDuration: Duration(milliseconds: 3000),
        height: 70,
        toastPosition: Position.top,
        shadowColor: Colors.white,
        animationType: AnimationType.fromTop,
        displayCloseButton: false,
        backgroundColor: Colors.red.withAlpha(40),
        description: Text(
          description,
          style: const TextStyle(color: Colors.red),
        ),
        title: Text(
          context.l10n.toastFail,
          style: const TextStyle(
            color: Colors.red,
            fontWeight: FontWeight.bold,
          ),
        ),
      ).show(context);
      break;
  }
}

final String tenderCoconut = "https://freshindiaorganics.com/cdn/shop/files/WhatsAppImage2025-02-27at1.40.30PM.jpg?v=1740648750";
