/// 封面组件：优先本地已下载的首图，其次网络封面
library;

import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../jm/jm_client.dart';

class AlbumCover extends StatelessWidget {
  const AlbumCover({
    super.key,
    required this.albumId,
    this.coverUrl = '',
    this.localPath = '',
    this.httpHeaders,
    this.width = 72,
    this.height = 96,
    this.radius = 8,
    this.show = true,
  });

  final String albumId;
  final String coverUrl;
  final String localPath;

  /// 封面需要鉴权时传（哔咔的封面要带 authorization）
  final Map<String, String>? httpHeaders;
  final double width;
  final double height;
  final double radius;

  /// 关闭后不渲染任何内容（设置里的「列表显示封面」）
  final bool show;

  @override
  Widget build(BuildContext context) {
    if (!show) return const SizedBox.shrink();

    Widget child;

    if (localPath.isNotEmpty && File(localPath).existsSync()) {
      child = Image.file(
        File(localPath),
        width: width,
        height: height,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => _network(context),
      );
    } else {
      child = _network(context);
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox(width: width, height: height, child: child),
    );
  }

  Widget _network(BuildContext context) {
    if (coverUrl.isEmpty) return _placeholder(context);

    return CachedNetworkImage(
      imageUrl: coverUrl,
      width: width,
      height: height,
      fit: BoxFit.cover,
      httpHeaders: httpHeaders ?? JmClient.imageHeadersStatic,
      placeholder: (_, _) => _placeholder(context),
      errorWidget: (_, _, _) => _placeholder(context),
    );
  }

  Widget _placeholder(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      color: scheme.surfaceContainerHighest,
      alignment: Alignment.center,
      child: Icon(
        Icons.image_outlined,
        size: width * 0.4,
        color: scheme.onSurfaceVariant,
      ),
    );
  }
}
