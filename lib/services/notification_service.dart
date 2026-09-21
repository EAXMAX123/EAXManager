/// 通知栏服务：下载进度通知与完成提醒
library;

import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationService {
  NotificationService._();

  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static const String _channelId = 'jm_download';
  static const String _channelName = '下载进度';
  static const String _doneChannelId = 'jm_download_done';
  static const String _doneChannelName = '下载完成';

  static const String _updateChannelId = 'jm_subscribe_update';
  static const String _updateChannelName = '追更提醒';

  static const int _progressId = 1001;

  bool _ready = false;

  AndroidFlutterLocalNotificationsPlugin? get _android => _plugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >();

  Future<void> init() async {
    if (_ready) return;

    // 用专门的单色小图标，插画图标在状态栏会糊成一团白
    const androidInit = AndroidInitializationSettings('ic_stat_jm');
    await _plugin.initialize(
      settings: const InitializationSettings(android: androidInit),
    );

    await _android?.createNotificationChannel(
      const AndroidNotificationChannel(
        _channelId,
        _channelName,
        description: '显示漫画下载进度',
        importance: Importance.low,
        showBadge: false,
      ),
    );
    await _android?.createNotificationChannel(
      const AndroidNotificationChannel(
        _doneChannelId,
        _doneChannelName,
        description: '下载完成提醒',
        importance: Importance.defaultImportance,
      ),
    );
    await _android?.createNotificationChannel(
      const AndroidNotificationChannel(
        _updateChannelId,
        _updateChannelName,
        description: '追更的本子有新章节时提醒',
        importance: Importance.defaultImportance,
      ),
    );

    _ready = true;
  }

  /// 请求通知权限（Android 13+）
  Future<bool> requestPermission() async {
    await init();
    if (!Platform.isAndroid) return true;
    return await _android?.requestNotificationsPermission() ?? true;
  }

  /// 更新下载进度通知
  Future<void> showProgress({
    required String title,
    required int done,
    required int total,
  }) async {
    await init();
    final percent = total == 0 ? 0 : ((done / total) * 100).round();

    await _plugin.show(
      id: _progressId,
      title: '正在下载：$title',
      body: '$done / $total（$percent%）',
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: '显示漫画下载进度',
          importance: Importance.low,
          priority: Priority.low,
          showProgress: true,
          maxProgress: total,
          progress: done,
          onlyAlertOnce: true,
          ongoing: true,
          autoCancel: false,
        ),
      ),
    );
  }

  /// 下载完成通知
  Future<void> showDone({
    required String title,
    required int count,
    String? detail,
  }) async {
    await init();
    await _plugin.cancel(id: _progressId);
    await _plugin.show(
      id: _progressId + 1,
      title: '下载完成：$title',
      body: detail ?? '共 $count 张图片',
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          _doneChannelId,
          _doneChannelName,
          channelDescription: '下载完成提醒',
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
        ),
      ),
    );
  }

  /// 下载失败通知
  Future<void> showFailed({
    required String title,
    required String error,
  }) async {
    await init();
    await _plugin.cancel(id: _progressId);
    await _plugin.show(
      id: _progressId + 2,
      title: '下载失败：$title',
      body: error,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          _doneChannelId,
          _doneChannelName,
          channelDescription: '下载完成提醒',
          importance: Importance.defaultImportance,
        ),
      ),
    );
  }

  Future<void> cancelProgress() async {
    await init();
    await _plugin.cancel(id: _progressId);
  }

  /// 追更：发现新章节
  Future<void> showNewChapters({
    required int count,
    required String summary,
  }) async {
    await init();
    await _plugin.show(
      id: _progressId + 3,
      title: '$count 本追更的漫画有新章节',
      body: summary,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          _updateChannelId,
          _updateChannelName,
          channelDescription: '追更的本子有新章节时提醒',
          importance: Importance.defaultImportance,
        ),
      ),
    );
  }
}
