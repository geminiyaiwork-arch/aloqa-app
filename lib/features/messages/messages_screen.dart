/// ALOQA — Xabarlar (placeholder — tez kunda).
library;

import 'package:flutter/material.dart';

import 'package:aloqa/core/theme/app_theme.dart';
import 'package:aloqa/core/widgets/app_shell.dart';
import 'package:aloqa/core/widgets/aloqa_card.dart';

class MessagesScreen extends StatelessWidget {
  const MessagesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AloqaAppShell(
      currentPath: '/messages',
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 8),
            AloqaCard(
              padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
              child: Column(
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: AppColors.brand50,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Icon(Icons.forum_outlined,
                        size: 32, color: AppColors.brand600),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Xabarlar',
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: AppColors.slate900),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Shaxsiy va guruh xabarlari tez kunda qo\'shiladi.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 14, color: AppColors.slate500),
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
