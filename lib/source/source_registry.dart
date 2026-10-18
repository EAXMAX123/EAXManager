/// 漫画源注册表：UI 只通过这里拿源，不直接依赖具体实现
library;

import 'comic_source.dart';

class SourceRegistry {
  final Map<String, ComicSource> _map = {};

  void register(ComicSource source) => _map[source.key] = source;

  ComicSource? of(String key) => _map[key];

  ComicSource? byId(SourceId sid) => _map[sid.source];

  /// 按注册顺序返回（JM / 哔咔 / EH）
  List<ComicSource> get all => _map.values.toList();

  List<ComicSource> ofKeys(Iterable<String> keys) => [
    for (final k in keys)
      if (_map[k] != null) _map[k]!,
  ];
}
