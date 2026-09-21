/// 追更服务：定时检查订阅本子是否有新章节，并发出通知
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/app_database.dart';
import '../source/comic_source.dart';
import '../source/source_registry.dart';
import 'notification_service.dart';

/// 一次追更检查中发现的更新
class SubscriptionUpdate {
  const SubscriptionUpdate({
    required this.sid,
    required this.title,
    required this.newChapters,
  });

  final SourceId sid;
  final String title;
  final int newChapters;
}

class SubscriptionService {
  SubscriptionService({required this.dao, required this.sources});

  final AppDao dao;
  final SourceRegistry sources;

  /// 订阅列表（界面监听）
  final ValueNotifier<List<SubscriptionItem>> subscriptions = ValueNotifier(
    const <SubscriptionItem>[],
  );

  /// 是否有检查正在进行
  final ValueNotifier<bool> checking = ValueNotifier(false);

  /// 最近一次检查完成的时间
  final ValueNotifier<DateTime?> lastCheckAt = ValueNotifier(null);

  /// 发现新章节时的回调，供界面弹提示
  void Function(List<SubscriptionUpdate> updates)? onUpdates;

  Timer? _timer;

  Future<void> reload() async {
    subscriptions.value = await dao.listSubscriptions();
  }

  Future<void> add({
    required SourceId sid,
    required String title,
    required String author,
    required int knownChapters,
  }) async {
    await dao.upsertSubscription(
      sid: sid,
      title: title,
      author: author,
      knownChapters: knownChapters,
    );
    await reload();
  }

  Future<void> remove(SourceId sid) async {
    await dao.removeSubscription(sid);
    await reload();
  }

  bool contains(SourceId sid) => subscriptions.value.any((s) => s.sid == sid);

  /// 立即检查全部订阅，返回本次发现的新章节
  Future<List<SubscriptionUpdate>> checkNow() async {
    if (checking.value) return const [];
    if (subscriptions.value.isEmpty) {
      lastCheckAt.value = DateTime.now();
      return const [];
    }

    checking.value = true;
    final updates = <SubscriptionUpdate>[];
    try {
      for (final sub in subscriptions.value) {
        try {
          final source = sources.of(sub.source);
          if (source == null) continue;
          final detail = await source.detail(sub.albumId);
          final count = detail.chapterCount;
          if (count > sub.knownChapters) {
            updates.add(
              SubscriptionUpdate(
                sid: sub.sid,
                title: detail.title.isEmpty ? sub.title : detail.title,
                newChapters: count - sub.knownChapters,
              ),
            );
            await dao.updateSubscriptionCheck(sub.sid, count);
          } else if (count < sub.knownChapters) {
            // 章节变少（作者删章）时同步为实际值，避免一直误报
            await dao.updateSubscriptionCheck(sub.sid, count);
          }
        } on Exception {
          // 单个本子失败不影响其他订阅
          continue;
        }
      }
    } finally {
      checking.value = false;
      lastCheckAt.value = DateTime.now();
      await reload();
    }

    if (updates.isNotEmpty) {
      final summary = updates
          .take(4)
          .map((u) => '《${u.title}》+${u.newChapters} 话')
          .join('\n');
      await NotificationService.instance.showNewChapters(
        count: updates.length,
        summary: updates.length > 4 ? '$summary\n…' : summary,
      );
      onUpdates?.call(updates);
    }
    return updates;
  }

  /// 按设置开启/关闭后台定时检查
  void schedule({required bool enabled, required int intervalSeconds}) {
    _timer?.cancel();
    _timer = null;
    if (!enabled) return;

    // 最短 5 分钟，避免过于频繁地打接口
    final interval = Duration(seconds: intervalSeconds.clamp(300, 86400));
    _timer = Timer.periodic(interval, (_) => checkNow());
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
  }
}
