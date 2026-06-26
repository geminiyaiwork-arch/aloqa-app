// ALOQA — basic smoke test: the app boots to the splash screen.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aloqa/main.dart';

void main() {
  testWidgets('ALOQA boots and shows brand on splash',
      (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: AloqaApp()));
    await tester.pump();

    // Splash renders the ALOQA wordmark.
    expect(find.text('ALOQA'), findsWidgets);
  });
}
