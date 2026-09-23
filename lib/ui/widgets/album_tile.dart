/// 搜索结果里的一行：封面 + 标题 + 来源角标
///
/// 搜索页、关键词结果页、识图结果页都用它，样式保持一致。
library;

import 'package:flutter/material.dart';

import '../../source/comic_source.dart';
import '../../state/app_services.dart';
import 'album_cover.dart';
import 'source_badge.dart';

class AlbumTile extends StatelessWidget {
  const AlbumTile({super.key, required this.item, required this.onTap});

  final ComicItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final subtitle = item.subtitle.isNotEmpty ? item.subtitle : item.author;

    return ListTile(
      onTap: onTap,
      leading: AlbumCover(
        albumId: item.sid.id,
        coverUrl: item.coverUrl,
        httpHeaders: item.coverHeaders,
        show: AppServices.I.settings.value.showCoverInList,
      ),
      title: Row(
        children: [
          Flexible(
            child: Text(
              item.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 6),
          SourceBadge(source: item.sid.source),
        ],
      ),
      subtitle: subtitle.isEmpty
          ? null
          : Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: const Icon(Icons.chevron_right),
    );
  }
}
