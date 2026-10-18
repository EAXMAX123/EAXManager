import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jm_reader/ui/widgets/mascot_actor.dart';
import 'package:jm_reader/ui/widgets/mascot_empty_state.dart';
import 'package:jm_reader/ui/widgets/mascot_navigation_bar.dart';

void main() {
  for (final role in MascotRole.values) {
    testWidgets('$role changes the prop pose and replays without scaling', (
      tester,
    ) async {
      Widget app(bool selected, {int activation = 0, bool reduced = false}) =>
          MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(disableAnimations: reduced),
              child: Center(
                child: MascotActor(
                  role: role,
                  selected: selected,
                  activation: activation,
                ),
              ),
            ),
          );
      double pose() => tester
          .widget<Opacity>(find.byKey(ValueKey('mascot-${role.name}-active')))
          .opacity;
      await tester.pumpWidget(app(false));
      expect(pose(), 0);
      await tester.pumpWidget(app(true));
      await tester.pump(const Duration(milliseconds: 230));
      expect(pose(), inExclusiveRange(0, 1));
      expect(find.byType(AnimatedScale), findsNothing);
      await tester.pumpAndSettle();
      expect(pose(), 1);
      await tester.pumpWidget(app(true, activation: 1));
      await tester.pump(const Duration(milliseconds: 200));
      expect(pose(), lessThan(1));
      await tester.pumpAndSettle();
      expect(pose(), 1);
      await tester.pumpWidget(app(false));
      await tester.pump(const Duration(milliseconds: 60));
      await tester.pumpWidget(app(true, reduced: true));
      expect(pose(), 1);
      await tester.pumpWidget(app(false, reduced: true));
      expect(pose(), 0);
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
      expect(tester.binding.transientCallbackCount, 0);
    });
  }

  testWidgets('discovery never blends two faces during transitions or replay', (
    tester,
  ) async {
    Widget app(bool selected, int activation, {bool reduced = false}) =>
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(disableAnimations: reduced),
            child: MascotActor(
              role: MascotRole.discover,
              selected: selected,
              activation: activation,
            ),
          ),
        );
    void verifySingleFace() {
      final idle = tester
          .widget<Opacity>(find.byKey(const ValueKey('mascot-discover-idle')))
          .opacity;
      final active = tester
          .widget<Opacity>(find.byKey(const ValueKey('mascot-discover-active')))
          .opacity;
      expect(idle * active, 0);
    }

    await tester.pumpWidget(app(false, 0));
    for (final selected in [true, false, true]) {
      await tester.pumpWidget(app(selected, 0));
      for (var frame = 0; frame < 20; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
        verifySingleFace();
      }
    }
    await tester.pumpWidget(app(true, 1));
    for (var frame = 0; frame < 26; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
      verifySingleFace();
    }
    await tester.pumpWidget(app(true, 2));
    await tester.pump(const Duration(milliseconds: 90));
    await tester.pumpWidget(app(false, 2));
    await tester.pump(const Duration(milliseconds: 60));
    await tester.pumpWidget(app(true, 3, reduced: true));
    verifySingleFace();
    expect(
      tester
          .widget<Opacity>(find.byKey(const ValueKey('mascot-discover-active')))
          .opacity,
      1,
    );
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('empty assistant fits short areas and keeps message', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 100,
            child: MascotEmptyState(message: '输入关键词开始搜索'),
          ),
        ),
      ),
    );
    expect(find.text('输入关键词开始搜索'), findsOneWidget);
    await tester.tap(find.byType(InkResponse));
    await tester.pumpAndSettle();
    expect(
      tester.widget<MascotActor>(find.byType(MascotActor)).selected,
      isTrue,
    );
    expect(tester.takeException(), isNull);
  });

  for (final reduced in [false, true]) {
    testWidgets('empty assistant toggles and holds pose (reduced: $reduced)', (
      tester,
    ) async {
      Widget app(String message) => MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: reduced),
          child: Scaffold(body: MascotEmptyState(message: message)),
        ),
      );
      Future<void> verifyPose(bool selected) async {
        await tester.pumpAndSettle();
        await tester.pump(const Duration(seconds: 3));
        final actor = tester.widget<MascotActor>(find.byType(MascotActor));
        expect(actor.selected, selected);
        expect(actor.activation, 0);
        expect(
          tester
              .widget<Opacity>(
                find.byKey(const ValueKey('mascot-discover-active')),
              )
              .opacity,
          selected ? 1 : 0,
        );
        expect(tester.binding.transientCallbackCount, 0);
      }

      await tester.pumpWidget(app('输入关键词开始搜索'));
      await verifyPose(false);
      await tester.tap(find.byType(InkResponse));
      await verifyPose(true);
      await tester.pumpWidget(app('换个关键词试试'));
      await verifyPose(true);
      await tester.tap(find.byType(InkResponse));
      await verifyPose(false);
      for (var tap = 0; tap < 3; tap++) {
        await tester.tap(find.byType(InkResponse));
        await tester.pump(const Duration(milliseconds: 40));
      }
      await verifyPose(true);
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('compact navigation retains a full tap target', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          bottomNavigationBar: MascotNavigationBar(
            selectedIndex: 0,
            onDestinationSelected: (_) {},
          ),
        ),
      ),
    );
    expect(tester.getSize(find.byType(MascotNavigationBar)).height, 60);
    for (final actor in tester.widgetList<MascotActor>(
      find.byType(MascotActor),
    )) {
      expect(actor.size, 34);
    }
    expect(
      tester.getSize(find.byType(InkWell).first).height,
      greaterThanOrEqualTo(48),
    );
  });

  testWidgets('render idle and active mascot contact sheet', (tester) async {
    tester.view.physicalSize = const Size(1000, 470);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final boundaryKey = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RepaintBoundary(
            key: boundaryKey,
            child: ColoredBox(
              color: const Color(0xfffaf8ff),
              child: Column(
                children: [
                  for (final selected in [false, true])
                    Row(
                      children: [
                        for (final role in MascotRole.values)
                          Column(
                            children: [
                              MascotActor(
                                role: role,
                                selected: selected,
                                size: 200,
                              ),
                              Text(
                                '${role.name} ${selected ? "active" : "idle"}',
                                style: const TextStyle(fontSize: 10),
                              ),
                            ],
                          ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    final context = tester.element(find.byType(MascotActor).first);
    await tester.runAsync(() async {
      for (final role in MascotRole.values) {
        for (final suffix in ['', '_active']) {
          await precacheImage(
            ResizeImage(
              AssetImage('assets/navigation/${role.name}$suffix.png'),
              width: 224,
            ),
            context,
          );
        }
      }
    });
    await tester.pumpAndSettle();
    final boundary =
        boundaryKey.currentContext!.findRenderObject()!
            as RenderRepaintBoundary;
    await tester.runAsync(() async {
      final image = await boundary.toImage();
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final output = File('build/mascot-poses-preview.png');
      await output.parent.create(recursive: true);
      await output.writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
    expect(tester.takeException(), isNull);
  });
}
