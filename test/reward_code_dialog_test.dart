import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jm_reader/ui/widgets/reward_code_dialog.dart';

Future<void> _showDialog(
  WidgetTester tester, {
  required Brightness brightness,
  Size size = const Size(390, 844),
  double textScale = 1,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(brightness: brightness),
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
        child: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => const RewardCodeDialog(),
                ),
                child: const Text('开'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('开'));
  await tester.pumpAndSettle();
}

void main() {
  for (final brightness in Brightness.values) {
    testWidgets('弹窗能开能关（$brightness）', (tester) async {
      await _showDialog(tester, brightness: brightness);
      expect(find.byType(RewardCodeDialog), findsOneWidget);
      expect(find.text(RewardCodeDialog.title), findsOneWidget);
      expect(find.byTooltip('关闭'), findsOneWidget);

      await tester.tap(find.byTooltip('关闭'));
      await tester.pumpAndSettle();
      expect(find.byType(RewardCodeDialog), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('小屏 + 大字号也不溢出', (tester) async {
    await _showDialog(
      tester,
      brightness: Brightness.dark,
      size: const Size(320, 560),
      textScale: 1.6,
    );
    expect(find.byType(RewardCodeDialog), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
