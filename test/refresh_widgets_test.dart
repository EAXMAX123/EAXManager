import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jm_reader/ui/widgets/retained_tabs.dart';
import 'package:jm_reader/ui/widgets/reading_strip.dart';

class ProbePage extends StatefulWidget {
  const ProbePage({super.key, required this.name, required this.onInit});
  final String name;
  final VoidCallback onInit;

  @override
  State<ProbePage> createState() => _ProbePageState();
}

class _ProbePageState extends State<ProbePage> {
  int taps = 0;

  @override
  void initState() {
    super.initState();
    widget.onInit();
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Text(
        '${widget.name}:$taps:${PageActivity.of(context)}:${TickerMode.valuesOf(context).enabled}',
      ),
      TextButton(
        onPressed: () => setState(() => taps++),
        child: Text(widget.name),
      ),
    ],
  );
}

void main() {
  for (final reducedMotion in [false, true]) {
    testWidgets(
      'tabs retain state, build lazily and suspend hidden tickers ($reducedMotion)',
      (tester) async {
        var firstInits = 0;
        var secondInits = 0;
        Widget app(int index) => MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(disableAnimations: reducedMotion),
            child: Scaffold(
              body: RetainedTabs(
                index: index,
                builders: [
                  (_) => ProbePage(name: 'first', onInit: () => firstInits++),
                  (_) => ProbePage(name: 'second', onInit: () => secondInits++),
                ],
              ),
            ),
          ),
        );
        await tester.pumpWidget(app(0));
        expect(firstInits, 1);
        expect(secondInits, 0);
        await tester.tap(find.text('first'));
        await tester.pumpWidget(app(1));
        await tester.pumpAndSettle();
        expect(find.text('second:0:true:true'), findsOneWidget);
        expect(
          find.text('first:1:false:false', skipOffstage: false),
          findsOneWidget,
        );
        await tester.pumpWidget(app(0));
        await tester.pumpAndSettle();
        expect(find.text('first:1:true:true'), findsOneWidget);
        expect(firstInits, 1);
        expect(secondInits, 1);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'reading strip restores deep page lazily and allows both directions',
    (tester) async {
      final controller = ScrollController();
      final built = <int>{};
      final keys = List.generate(100, (_) => GlobalKey());
      Widget app(int initial) => MaterialApp(
        home: Scaffold(
          body: ReadingStrip(
            controller: controller,
            initialIndex: initial,
            itemCount: 100,
            itemBuilder: (context, index) {
              built.add(index);
              return SizedBox(
                key: keys[index],
                height: 450 + index.toDouble(),
                child: Text('page-$index'),
              );
            },
          ),
        ),
      );
      await tester.pumpWidget(app(80));
      expect(tester.getTopLeft(find.text('page-80')).dy, 0);
      expect(built.length, lessThan(12));
      controller.jumpTo(-400);
      await tester.pumpAndSettle();
      expect(find.text('page-79'), findsOneWidget);
      controller.jumpTo(600);
      await tester.pumpAndSettle();
      expect(find.text('page-81'), findsOneWidget);
      await tester.pumpWidget(app(0));
      controller.jumpTo(0);
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(find.text('page-0')).dy, 0);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
  );
}
