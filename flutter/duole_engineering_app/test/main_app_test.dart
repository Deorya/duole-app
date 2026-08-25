import 'package:duole_engineering_app/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows a redacted setup error when build configuration is absent',
      (tester) async {
    await tester.pumpWidget(
      const DuoleEngineeringApp.configurationFailure(
        'engineering_token_required',
      ),
    );

    expect(find.text('工程配置不可用'), findsOneWidget);
    expect(find.text('engineering_token_required'), findsOneWidget);
    expect(find.textContaining('token='), findsNothing);
  });
}
