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
    final showCover = AppServices.I.settings.value.showCoverInList;
    return Card(
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              if (showCover) ...[
                AlbumCover(
                  albumId: item.sid.id,
                  coverUrl: item.coverUrl,
                  httpHeaders: item.coverHeaders,
                  width: 60,
                  height: 80,
                ),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    if (subtitle.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                    const SizedBox(height: 8),
                    SourceBadge(source: item.sid.source),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.chevron_right, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}
