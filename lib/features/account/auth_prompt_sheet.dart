import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/theme/theme_extensions.dart';
import 'sign_in_screen.dart';
import 'sign_up_screen.dart';

Future<bool> showAuthPromptSheet(
  BuildContext context, {
  required String title,
  required String body,
}) {
  final completer = Completer<bool>();
  final navigator = Navigator.of(context);
  var launchedAuthRoute = false;

  showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    builder: (sheetContext) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: sheetContext.text.titleLarge?.copyWith(fontSize: 24),
            ),
            const SizedBox(height: 10),
            Text(body, style: sheetContext.text.bodyLarge),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () async {
                  launchedAuthRoute = true;
                  Navigator.of(sheetContext).pop();
                  final created = await navigator.push<bool>(
                    MaterialPageRoute<bool>(
                      builder: (_) => const SignUpScreen(),
                    ),
                  );
                  if (!completer.isCompleted) {
                    completer.complete(created == true);
                  }
                },
                child: const Text('Create account'),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () async {
                  launchedAuthRoute = true;
                  Navigator.of(sheetContext).pop();
                  final signedIn = await navigator.push<bool>(
                    MaterialPageRoute<bool>(
                      builder: (_) => const SignInScreen(),
                    ),
                  );
                  if (!completer.isCompleted) {
                    completer.complete(signedIn == true);
                  }
                },
                child: const Text('I already have an account'),
              ),
            ),
            const SizedBox(height: 6),
            TextButton(
              onPressed: () => Navigator.of(sheetContext).pop(),
              style: TextButton.styleFrom(
                foregroundColor: sheetContext.palette.slate,
              ),
              child: const Text('Not now'),
            ),
          ],
        ),
      );
    },
  ).whenComplete(() {
    if (!completer.isCompleted && !launchedAuthRoute) {
      completer.complete(false);
    }
  });

  return completer.future;
}
