import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jm_reader/ui/widgets/reward_code_dialog.dart';
import 'package:jm_reader/ui/widgets/sponsor_chip.dart';

/// 胶囊上会出现的所有句子，和 SponsorChip 里的五种神态一一对应
const _labels = <String>['求赞助！', '给点吧～', '不准按！', '老板大气！', '谢谢你♪'];

const _channel = MethodChannel('jm_reader/platform');

/// 当前显示的是哪一句（泵完帧之后只会剩一个）
String _currentLabel(WidgetTester tester) {
  final texts = tester
      .widgetList<Text>(find.byType(Text))
      .where((t) => _labels.contains(t.data))
      .toList();
  expect(texts, hasLength(1));
  return texts.single.data!;
}

Future<void> _pumpChip(WidgetTester tester, {bool reducedMotion = false}) {
  return tester.pumpWidget(
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: reducedMotion),
        child: const Scaffold(body: Center(child: SponsorChip())),
      ),
    ),
  );
}

/// 点一下胶囊。点出赞赏码弹窗就顺手关掉，好继续往下点。
Future<void> _tapChip(WidgetTester tester) async {
  await tester.tap(find.byType(SponsorChip));
  await tester.pumpAndSettle();
  if (find.byType(RewardCodeDialog).evaluate().isNotEmpty) {
    await tester.tap(find.byTooltip('关闭'));
    await tester.pumpAndSettle();
  }
}

/// 拦住原生通道：记录调了哪些方法，一律回 true
List<String> _mockChannel() {
  final calls = <String>[];
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(_channel, (call) async {
    calls.add(call.method);
    return true;
  });
  addTearDown(() => messenger.setMockMethodCallHandler(_channel, null));
  return calls;
}

void main() {
  testWidgets('默认显示求赞助，点一下换成别的句子', (tester) async {
    _mockChannel();
    await _pumpChip(tester);
    expect(_currentLabel(tester), '求赞助！');

    await _tapChip(tester);
    final after = _currentLabel(tester);
    expect(_labels, contains(after));
    expect(after, isNot('求赞助！'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('连续点击不会连着两次同一个样子', (tester) async {
    _mockChannel();
    await _pumpChip(tester);
    var previous = _currentLabel(tester);
    for (var turn = 0; turn < 30; turn++) {
      await _tapChip(tester);
      final current = _currentLabel(tester);
      expect(current, isNot(previous));
      previous = current;
      expect(tester.takeException(), isNull);
    }
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('狂点也不会留下动画异常', (tester) async {
    _mockChannel();
    await _pumpChip(tester);
    for (var turn = 0; turn < 40; turn++) {
      // 弹出赞赏码之后它会挡住胶囊，先关掉再接着点
      if (find.byType(RewardCodeDialog).evaluate().isNotEmpty) {
        await tester.tap(find.byTooltip('关闭'));
        await tester.pumpAndSettle();
      }
      await tester.tap(find.byType(SponsorChip));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await tester.pumpAndSettle();
    expect(tester.binding.transientCallbackCount, 0);
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });

  testWidgets('系统关掉动画时不出错', (tester) async {
    _mockChannel();
    await _pumpChip(tester, reducedMotion: true);
    expect(_currentLabel(tester), '求赞助！');
    await _tapChip(tester);
    expect(_labels, contains(_currentLabel(tester)));
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('可点击、可读屏', (tester) async {
    _mockChannel();
    final semantics = tester.ensureSemantics();
    await _pumpChip(tester);
    final finder = find.bySemanticsLabel('求赞助！，点一下换个样子');
    expect(finder, findsOneWidget);
    expect(
      tester.getSemantics(finder),
      matchesSemantics(
        label: '求赞助！，点一下换个样子',
        isButton: true,
        hasTapAction: true,
      ),
    );
    semantics.dispose();
  });

  testWidgets('按两下弹出赞赏码，点 ✕ 能关掉', (tester) async {
    _mockChannel();
    await _pumpChip(tester);

    await _tapChip(tester);
    expect(find.byType(RewardCodeDialog), findsNothing);

    await tester.tap(find.byType(SponsorChip));
    await tester.pumpAndSettle();
    expect(find.byType(RewardCodeDialog), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (w) =>
            w is Image &&
            w.image is AssetImage &&
            (w.image as AssetImage).assetName == RewardCodeDialog.assetPath,
      ),
      findsOneWidget,
    );

    await tester.tap(find.byTooltip('关闭'));
    await tester.pumpAndSettle();
    expect(find.byType(RewardCodeDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('关掉赞赏码后接着按三下，第五下放彩蛋', (tester) async {
    final calls = _mockChannel();
    await _pumpChip(tester);

    await _tapChip(tester); // 第 1 下
    await _tapChip(tester); // 第 2 下：弹出赞赏码，顺手关掉
    await _tapChip(tester); // 第 3 下
    await _tapChip(tester); // 第 4 下
    expect(calls, isEmpty);

    await _tapChip(tester); // 第 5 下
    expect(calls, ['playEasterEggVideo']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('放完彩蛋重新数，再按两下照样弹赞赏码', (tester) async {
    _mockChannel();
    await _pumpChip(tester);

    for (var turn = 0; turn < SponsorChip.tapForEgg; turn++) {
      await _tapChip(tester);
    }
    expect(find.byType(RewardCodeDialog), findsNothing);

    await _tapChip(tester);
    expect(find.byType(RewardCodeDialog), findsNothing);
    await tester.tap(find.byType(SponsorChip));
    await tester.pumpAndSettle();
    expect(find.byType(RewardCodeDialog), findsOneWidget);
  });

  testWidgets('手机以外的环境放不出来也不会崩', (tester) async {
    await _pumpChip(tester);
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(_channel, (call) async {
      if (call.method == 'playEasterEggVideo') {
        throw MissingPluginException('没有原生实现');
      }
      return true;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(_channel, null));

    for (var turn = 0; turn < SponsorChip.tapForEgg; turn++) {
      await _tapChip(tester);
    }
    await tester.pumpAndSettle();
    expect(find.text('彩蛋要在手机上看哦'), findsOneWidget);
    // 让 SnackBar 自己收掉，别留下没跑完的定时器
    await tester.pump(const Duration(seconds: 3));
    expect(tester.takeException(), isNull);
  });

  for (final brightness in Brightness.values) {
    testWidgets('窄屏 + 大字号放得下（$brightness）', (tester) async {
      _mockChannel();
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(brightness: brightness),
          home: const MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(1.6)),
            child: Scaffold(body: Center(child: SponsorChip())),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
}
