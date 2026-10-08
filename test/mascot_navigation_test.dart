import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jm_reader/ui/widgets/mascot_navigation_bar.dart';

void main() {
  testWidgets('mascot navigation reports taps and selected semantics', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    var selected = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          bottomNavigationBar: MascotNavigationBar(
            selectedIndex: selected,
            onDestinationSelected: (value) => selected = value,
          ),
        ),
      ),
    );
    expect(find.bySemanticsLabel('发现'), findsOneWidget);
    expect(
      tester.getSemantics(find.bySemanticsLabel('发现')),
      matchesSemantics(
        label: '发现',
        isButton: true,
        hasSelectedState: true,
        isSelected: true,
        hasTapAction: true,
      ),
    );
    await tester.tap(find.bySemanticsLabel('书架'));
    expect(selected, 1);
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });

  for (final brightness in Brightness.values) {
    testWidgets('rapid taps, compact layout and large text ($brightness)', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var selected = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(brightness: brightness),
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: StatefulBuilder(
              builder: (context, setState) => Scaffold(
                bottomNavigationBar: MascotNavigationBar(
                  selectedIndex: selected,
                  onDestinationSelected: (value) =>
                      setState(() => selected = value),
                ),
              ),
            ),
          ),
        ),
      );
      for (var turn = 0; turn < 25; turn++) {
        final index = turn % 5;
        await tester.tap(find.byType(InkWell).at(index));
        await tester.pump(const Duration(milliseconds: 20));
        expect(selected, index);
        expect(tester.takeException(), isNull);
      }
      await tester.pumpAndSettle();
      expect(tester.binding.transientCallbackCount, 0);
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('reduced motion settles without animation exceptions', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: Scaffold(
            bottomNavigationBar: MascotNavigationBar(
              selectedIndex: 2,
              onDestinationSelected: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('下载'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
