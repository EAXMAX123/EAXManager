/// 通知服务：手机上是通知栏，电脑上是系统横幅
///
/// 桌面端（Windows）走的是 toast，有没有成功注册要看系统给不给面子，
/// 注册不上就整体降级成「不弹通知」，绝不让它拖垮启动流程。
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

  /// 当前平台能不能真的弹通知
  bool _enabled = false;

  AndroidFlutterLocalNotificationsPlugin? get _android => _plugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >();

  Future<void> init() async {
    if (_ready) return;
    _ready = true;

    if (Platform.isAndroid) {
      await _initAndroid();
      return;
    }
    if (Platform.isLinux) {
      await _guard(() async {
        await _plugin.initialize(
          settings: const InitializationSettings(
            linux: LinuxInitializationSettings(defaultActionName: '打开'),
          ),
        );
      });
      _enabled = true;
      return;
    }
    if (Platform.isWindows) {
      await _guard(() async {
        final ok = await _plugin.initialize(
          settings: const InitializationSettings(
            windows: WindowsInitializationSettings(
              appName: 'EAX管理器',
              appUserModelId: 'EAXManager.EAXManager',
              guid: 'd9f2b7a4-6c31-4f58-9a02-1e8d3c5b7f60',
            ),
          ),
        );
        _enabled = ok ?? false;
      });
      return;
    }
  }

  Future<void> _initAndroid() async {
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

    _enabled = true;
  }

  /// 通知这套东西在哪个平台上出岔子都不该影响别的功能
  Future<void> _guard(Future<void> Function() body) async {
    try {
      await body();
    } on Object {
      _enabled = false;
    }
  }

  NotificationDetails _androidDetails(
    String channelId,
    String channelName, {
    String? description,
    bool progress = false,
    int total = 0,
    int done = 0,
  }) => NotificationDetails(
    android: AndroidNotificationDetails(
      channelId,
      channelName,
      channelDescription: description,
      importance: progress ? Importance.low : Importance.defaultImportance,
      priority: progress ? Priority.low : Priority.defaultPriority,
      showProgress: progress,
      maxProgress: total,
      progress: done,
      onlyAlertOnce: progress,
      ongoing: progress,
      autoCancel: !progress,
    ),
    windows: const WindowsNotificationDetails(),
  );

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
    if (!_enabled) return;
    final percent = total == 0 ? 0 : ((done / total) * 100).round();

    await _plugin.show(
      id: _progressId,
      title: '正在下载：$title',
      body: '$done / $total（$percent%）',
      notificationDetails: _androidDetails(
        _channelId,
        _channelName,
        description: '显示漫画下载进度',
        progress: true,
        total: total,
        done: done,
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
    if (!_enabled) return;
    await _plugin.cancel(id: _progressId);
    await _plugin.show(
      id: _progressId + 1,
      title: '下载完成：$title',
      body: detail ?? '共 $count 张图片',
      notificationDetails: _androidDetails(
        _doneChannelId,
        _doneChannelName,
        description: '下载完成提醒',
      ),
    );
  }

  /// 下载失败通知
  Future<void> showFailed({
    required String title,
    required String error,
  }) async {
    await init();
    if (!_enabled) return;
    await _plugin.cancel(id: _progressId);
    await _plugin.show(
      id: _progressId + 2,
      title: '下载失败：$title',
      body: error,
      notificationDetails: _androidDetails(
        _doneChannelId,
        _doneChannelName,
        description: '下载完成提醒',
      ),
    );
  }

  Future<void> cancelProgress() async {
    await init();
    if (!_enabled) return;
    await _plugin.cancel(id: _progressId);
  }

  /// 追更：发现新章节
  Future<void> showNewChapters({
    required int count,
    required String summary,
  }) async {
    await init();
    if (!_enabled) return;
    await _plugin.show(
      id: _progressId + 3,
      title: '$count 本追更的漫画有新章节',
      body: summary,
      notificationDetails: _androidDetails(
        _updateChannelId,
        _updateChannelName,
        description: '追更的本子有新章节时提醒',
      ),
    );
  }
}
