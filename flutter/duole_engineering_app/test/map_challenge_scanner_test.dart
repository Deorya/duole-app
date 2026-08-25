import 'package:duole_engineering_app/map_challenge_scanner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('six-digit fallback stays blocked until the code is complete', (
    tester,
  ) async {
    String? accepted;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              accepted = await enterMapChallengeShortCode(context);
            },
            child: const Text('输入备用码'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('输入备用码'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('map-short-code-input')),
      '48291',
    );
    await tester.pump();

    final incomplete = tester.widget<TextButton>(
      find.byKey(const Key('map-short-code-submit')),
    );
    expect(incomplete.onPressed, isNull);

    await tester.enterText(
      find.byKey(const Key('map-short-code-input')),
      '482913',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('map-short-code-submit')));
    await tester.pumpAndSettle();

    expect(accepted, '482913');
  });
}
