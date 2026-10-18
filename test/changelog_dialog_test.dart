import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jm_reader/app_info.dart';
import 'package:jm_reader/data/app_docs.dart';
import 'package:jm_reader/ui/widgets/changelog_dialog.dart';

void main() {
  test('当前版本必须有对应的更新公告', () {
    expect(Changelog.entryFor(AppInfo.version), isNotNull);
    expect(Changelog.entries.first.version, AppInfo.version);
  });

  testWidgets('公告弹窗展示本版内容并能正常关闭', (tester) async {
    bool? openRecords;
    final entry = Changelog.entryFor(AppInfo.version)!;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () async {
                  openRecords = await ChangelogDialog.show(context, entry);
                },
                child: const Text('打开公告'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开公告'));
    await tester.pumpAndSettle();

    expect(find.text('已更新到 v${AppInfo.version}'), findsOneWidget);
    expect(find.text('新增'), findsOneWidget);

    await tester.tap(find.text('知道了'));
    await tester.pumpAndSettle();

    expect(openRecords, isFalse);
    expect(find.text('已更新到 v${AppInfo.version}'), findsNothing);
  });
}
