import 'package:flutter/material.dart';

import '../../core/theme/theme_extensions.dart';
import 'sign_in_screen.dart';
import 'sign_up_screen.dart';

Future<void> showAuthPromptSheet(
  BuildContext context, {
  required String title,
  required String body,
}) {
  final navigator = Navigator.of(context);

  return showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    builder: (sheetContext) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: sheetContext.text.titleLarge?.copyWith(fontSize: 24)),
            const SizedBox(height: 10),
            Text(body, style: sheetContext.text.bodyLarge),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.of(sheetContext).pop();
                  navigator.push(
                    MaterialPageRoute<void>(builder: (_) => const SignUpScreen()),
                  );
                },
                child: const Text('Create account'),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () {
                  Navigator.of(sheetContext).pop();
                  navigator.push(
                    MaterialPageRoute<void>(builder: (_) => const SignInScreen()),
                  );
                },
                child: const Text('Sign in'),
              ),
            ),
            const SizedBox(height: 6),
            TextButton(
              onPressed: () => Navigator.of(sheetContext).pop(),
              style: TextButton.styleFrom(foregroundColor: sheetContext.palette.slate),
              child: const Text('Keep browsing as guest'),
            ),
          ],
        ),
      );
    },
  );
}
