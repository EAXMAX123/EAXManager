import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jm_reader/data/settings_store.dart';
import 'package:jm_reader/source/comic_source.dart';
import 'package:jm_reader/source/source_registry.dart';
import 'package:jm_reader/state/app_services.dart';
import 'package:jm_reader/ui/pages/home_page.dart';
import 'package:jm_reader/ui/theme.dart';
import 'package:jm_reader/ui/widgets/album_tile.dart';

class PendingRequest {
  PendingRequest(this.query, this.page, this.mode);
  final String query;
  final int page;
  final SearchMode mode;
  final response = Completer<ComicSearchPage>();

  void complete(String title, {int count = 1, int total = 1}) {
    response.complete(
      ComicSearchPage(
        items: List.generate(
          count,
          (index) => ComicItem(
            sid: SourceId('jm', '$title-$index'),
            title: '$title-$index',
            author: '示例作者',
          ),
        ),
        page: page,
        total: total,
      ),
    );
  }
}

class FakeSource implements ComicSource {
  final searches = <PendingRequest>[];
  final ranks = <PendingRequest>[];
  bool failReady = false;

  @override
  String get key => 'jm';
  @override
  String get name => 'JM';
  @override
  List<RankOption> get rankTimes => const [
    RankOption('day', '今日'),
    RankOption('week', '本周'),
  ];
  @override
  List<RankOption> rankCategories(String time) => [];
  @override
  Future<bool> ready() async {
    if (failReady) throw const SourceException('ready failed');
    return true;
  }

  @override
  Future<ComicSearchPage> search(
    String keyword, {
    SearchMode mode = SearchMode.site,
    int page = 1,
  }) {
    final request = PendingRequest(keyword, page, mode);
    searches.add(request);
    return request.response.future;
  }

  @override
  Future<ComicSearchPage> rank({
    required String time,
    String category = '',
    int page = 1,
  }) {
    final request = PendingRequest(time, page, SearchMode.site);
    ranks.add(request);
    return request.response.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late FakeSource source;
  setUp(() {
    source = FakeSource();
    AppServices.I.sources = SourceRegistry()..register(source);
    AppServices.I.settings.value = const AppSettings();
  });

  Future<void> showHome(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(brightness: Brightness.light, seed: 0xFFE91E63),
        home: const Scaffold(body: HomePage()),
      ),
    );
  }

  Future<void> search(WidgetTester tester, String query) async {
    await tester.enterText(find.byType(TextField).first, query);
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump();
  }

  testWidgets('new search wins even when an older response finishes later', (
    tester,
  ) async {
    await showHome(tester);
    await search(tester, 'old');
    await search(tester, 'new');
    source.searches[1].complete('new-result');
    await tester.pumpAndSettle();
    source.searches[0].complete('old-result');
    await tester.pumpAndSettle();
    expect(find.text('new-result-0'), findsOneWidget);
    expect(find.text('old-result-0'), findsNothing);
  });

  testWidgets(
    'swiping to ranking initializes once without losing search results',
    (tester) async {
      await showHome(tester);
      await search(tester, 'search');
      source.searches.single.complete('search-result');
      await tester.pumpAndSettle();
      await tester.dragFrom(const Offset(700, 450), const Offset(-650, 0));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 500));
      expect(tester.widget<TabBar>(find.byType(TabBar)).controller!.index, 1);
      expect(source.ranks, hasLength(1));
      source.ranks.single.complete('rank-result');
      await tester.pumpAndSettle();
      expect(find.text('rank-result-0'), findsOneWidget);
      await tester.tap(find.text('搜索'));
      await tester.pumpAndSettle();
      expect(find.text('search-result-0'), findsOneWidget);
      expect(find.text('rank-result-0'), findsNothing);
      await tester.tap(find.text('排行'));
      await tester.pumpAndSettle();
      expect(source.ranks, hasLength(1));
    },
  );

  testWidgets('fast ranking filter change ignores old response', (
    tester,
  ) async {
    await showHome(tester);
    await tester.tap(find.text('排行'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.text('本周'));
    await tester.pump();
    expect(source.ranks, hasLength(2));
    source.ranks.last.complete('week');
    await tester.pumpAndSettle();
    source.ranks.first.complete('day');
    await tester.pumpAndSettle();
    expect(find.text('week-0'), findsOneWidget);
    expect(find.text('day-0'), findsNothing);
  });

  testWidgets('editing draft and mode does not mix paginated search results', (
    tester,
  ) async {
    await showHome(tester);
    await search(tester, 'original');
    source.searches.single.complete('original', count: 12, total: 30);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'draft');
    await tester.tap(find.text('作者'));
    await tester.pump();
    final list = find.byKey(const PageStorageKey('discovery-0'));
    await tester.drag(list, const Offset(0, -1500));
    await tester.pump(const Duration(milliseconds: 500));
    expect(source.searches, hasLength(2));
    expect(source.searches.last.query, 'original');
    expect(source.searches.last.mode, SearchMode.site);
    expect(source.searches.last.page, 2);
    source.searches.last.complete('page2', total: 13);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('ready error exits loading and displays retry', (tester) async {
    source.failReady = true;
    await showHome(tester);
    await search(tester, 'query');
    await tester.pumpAndSettle();
    expect(find.textContaining('ready failed'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  for (final brightness in Brightness.values) {
    testWidgets(
      'result cards fit compact screen with large text in $brightness',
      (tester) async {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.build(brightness: brightness, seed: 0xFFE91E63),
            home: MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(1.6)),
              child: Scaffold(
                body: ListView(
                  children: [
                    AlbumTile(
                      item: const ComicItem(
                        sid: SourceId('pixiv', '1'),
                        title: '本地阅读与插画收藏 · 一个很长的示例标题',
                        author: '示例作者与工作室',
                      ),
                      onTap: () {},
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );
  }
}
