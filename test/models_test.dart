// 数据模型解析测试：确保接口字段与实体映射保持稳定
import 'package:flutter_test/flutter_test.dart';
import 'package:jm_reader/jm/jm_models.dart';

void main() {
  group('JmFavoritePage', () {
    test('解析 list / folder_list / total', () {
      final page = JmFavoritePage.fromJson(const {
        'list': [
          {
            'id': '363859',
            'name': '测试本子',
            'author': '紺菓',
            'category': {'id': '1', 'title': '同人'},
          },
        ],
        'folder_list': [
          {'FID': '0', 'name': '全部收藏'},
          {'FID': '123', 'name': '稍后再看'},
        ],
        'total': '87',
        'count': 20,
      }, 1);

      expect(page.items, hasLength(1));
      expect(page.items.first.id, '363859');
      expect(page.items.first.name, '测试本子');
      expect(page.items.first.category, '同人');
      expect(page.folders.map((f) => f.id), ['0', '123']);
      expect(page.folders.last.name, '稍后再看');
      expect(page.total, 87);
    });

    test('字段缺失时不抛异常', () {
      final page = JmFavoritePage.fromJson(const {}, 2);
      expect(page.items, isEmpty);
      expect(page.folders, isEmpty);
      expect(page.total, 0);
      expect(page.page, 2);
    });
  });

  group('JmAlbum', () {
    test('章节按 sort 升序排列', () {
      final album = JmAlbum.fromJson(const {
        'id': '123',
        'name': '合集',
        'series': [
          {'id': '3', 'name': '第三话', 'sort': 3},
          {'id': '1', 'name': '第一话', 'sort': 1},
          {'id': '2', 'name': '第二话', 'sort': 2},
        ],
        'is_favorite': true,
      });

      expect(album.sortedSeries.map((e) => e.id), ['1', '2', '3']);
      expect(album.isFavorite, isTrue);
    });

    test('没有作者时给出兜底文案', () {
      final album = JmAlbum.fromJson(const {'id': '1', 'name': 'x'});
      expect(album.authorText, '未知作者');
    });
  });
}
