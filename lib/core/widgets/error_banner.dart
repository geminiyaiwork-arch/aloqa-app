/// ALOQA — inline error banner (calm, animated).
library;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class InlineErrorBanner extends StatelessWidget {
  const InlineErrorBanner({super.key, this.message});

  final String? message;

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      child: message == null
          ? const SizedBox(width: double.infinity)
          : Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.danger.withOpacity(0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.danger.withOpacity(0.25)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error_outline, size: 18, color: AppColors.danger),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(message!,
                        style: const TextStyle(fontSize: 13, color: AppColors.danger)),
                  ),
                ],
              ),
            ),
    );
  }
}
