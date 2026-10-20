/// 阅读器：纵向滚动 + 音量键翻页 + 点击放大 + 进度记忆 + 章节切换
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

import '../../jm/jm_storage.dart';
import '../../services/image_aspect.dart';
import '../../services/local_library.dart';
import '../../services/platform_service.dart';
import '../../services/reading_progress_writer.dart';
import '../../source/comic_source.dart';
import '../../state/app_services.dart';
import '../widgets/reading_strip.dart';

class ReaderPage extends StatefulWidget {
  const ReaderPage({
    super.key,
    required this.sid,
    required this.albumTitle,
    required this.chapterIndex,
    this.chapterCount = 0,
    this.onExit,
  });

  final SourceId sid;
  final String albumTitle;
  final int chapterIndex;
  final int chapterCount;

  /// 退出阅读时干什么；给了就用它
  ///
  /// 电脑版阅读是单独一个窗口，里面没有上一层页面可以返回，
  /// 传进来的是「关掉这个窗口」。手机上不传，还是退回上一页。
  final VoidCallback? onExit;

  @override
  State<ReaderPage> createState() => _ReaderPageState();
}

class _ReaderPageState extends State<ReaderPage> with WidgetsBindingObserver {
  final ScrollController _scroll = ScrollController();

  List<File> _files = const [];
  List<double> _ratios = const [];
  List<double> _heights = const [];
  List<double> _startOffsets = const [];
  double _metricsWidth = 0;
  bool _loading = true;
  String? _error;
  bool _showOverlay = true;

  int _currentIndex = 0;
  int _targetIndex = 0;
  bool _pageAnimating = false;
  Timer? _saveThrottle;
  int _initialIndex = 0;
  bool _switching = false;
  late final _progress = ReadingProgressWriter(
    (page) async {
      await AppServices.I.dao.updateReadProgress(
        widget.sid,
        widget.chapterIndex,
        page,
      );
      await AppServices.I.reloadLibrary();
    },
    onError: (error, stack) =>
        debugPrint('Reading progress save failed: $error'),
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
    PlatformService.onVolumeKey = _onVolumeKey;
    PlatformService.setVolumeKeyEnabled(
      AppServices.I.settings.value.volumeKeyPageTurn,
    );
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_saveProgress());
    if (PlatformService.onVolumeKey == _onVolumeKey) {
      PlatformService.onVolumeKey = null;
      PlatformService.setVolumeKeyEnabled(false);
    }
    _saveThrottle?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      _saveThrottle?.cancel();
      unawaited(_saveProgress());
    }
  }

  Future<void> _load() async {
    try {
      await _loadLocalChapter();
    } on Exception catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '读取本地章节失败，请确认文件和存储权限：$error';
      });
    }
  }

  Future<void> _loadLocalChapter() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    final root = AppServices.I.rootDir.value;
    if (root.isEmpty || root.startsWith('(')) {
      setState(() {
        _error = '没有存储权限，无法读取已下载的漫画';
        _loading = false;
      });
      return;
    }

    // 目录以数据库里记的落盘位置为准：换过下载目录的老书也能找到
    final dir = await LocalLibrary.chapterDir(widget.sid, widget.chapterIndex);
    final files = dir == null
        ? const <File>[]
        : await JmStorage.listImages(dir);

    if (!mounted) return;
    if (files.isEmpty) {
      final message = await _missingMessage();
      if (!mounted) return;
      setState(() {
        _error = message;
        _loading = false;
      });
      return;
    }

    // 先读尺寸再进列表：图片高度固定下来，滚动时 Sliver 不会因为
    // 图片解码先后而反复改高度，页码也就不会突然乱跳。
    final ratios = await ImageAspect.ratios(files);
    if (!mounted) return;

    final saved = await AppServices.I.dao.getBookshelf(widget.sid);
    if (!mounted) return;
    _initialIndex = saved != null && saved.lastChapter == widget.chapterIndex
        ? (saved.lastPage - 1).clamp(0, files.length - 1)
        : 0;
    _currentIndex = _initialIndex;
    _targetIndex = _initialIndex;
    _metricsWidth = 0;
    _heights = const [];
    _startOffsets = const [];

    setState(() {
      _files = files;
      _ratios = ratios;
      _loading = false;
    });
  }

  /// 这一话没有图时给一句有用的话：本地到底有哪几话
  ///
  /// 光说「本章还没有下载」，用户只会以为是软件坏了——
  /// 其实是这一话没下、别的话下了，书架点进来默认开的那一话不对。
  Future<String> _missingMessage() async {
    final local = await LocalLibrary.chapters(widget.sid);
    if (local.isEmpty) return '本章还没有下载';
    final shown = local.take(6).join('、');
    final more = local.length > 6 ? '…' : '';
    return '本章还没有下载，本地有第 $shown$more 话';
  }

  /// 音量键翻页：音量上键往上翻（上一页），音量下键往下翻（下一页）
  void _onVolumeKey(int delta) {
    if (!AppServices.I.settings.value.volumeKeyPageTurn) return;
    // delta: +1 音量上键 -> 往上；-1 音量下键 -> 往下
    _page(-delta);
  }

  /// 翻页：direction 为 +1 往下（下一页），-1 往上
  void _page(int direction) {
    if (!mounted || !_scroll.hasClients || _files.isEmpty) return;
    if (ModalRoute.of(context)?.isCurrent != true) return;

    if (_startOffsets.length != _files.length) {
      _ensureMetrics(MediaQuery.sizeOf(context).width);
    }
    if (_startOffsets.length != _files.length) return;

    // 动画还没跑完时接着按，按「上一次的目标页」继续加，
    // 不要拿还没滚到的当前位置当基准，否则连按会原地打转。
    final base = _pageAnimating ? _targetIndex : _currentIndex;
    var target = (base + direction).clamp(0, _files.length - 1);

    // 一页比屏幕高的时候，先回到本页顶部，再按才翻到上一页。
    if (direction < 0 && !_pageAnimating) {
      final pageStart = _startOffsets[_currentIndex];
      if (_scroll.offset - pageStart >
          _scroll.position.viewportDimension * 0.08) {
        target = _currentIndex;
      }
    }

    if (_pageAnimating && target == _targetIndex) return;
    _targetIndex = target;
    if (!_pageAnimating) unawaited(_animateToTargetPage());
  }

  Future<void> _animateToTargetPage() async {
    _pageAnimating = true;
    try {
      while (mounted && _scroll.hasClients) {
        final target = _targetIndex.clamp(0, _startOffsets.length - 1);
        final offset = _startOffsets[target].clamp(
          _scroll.position.minScrollExtent,
          _scroll.position.maxScrollExtent,
        );
        if (MediaQuery.disableAnimationsOf(context)) {
          _scroll.jumpTo(offset);
        } else {
          await _scroll.animateTo(
            offset,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
          );
        }
        if (!mounted || _targetIndex == target) break;
      }
    } finally {
      _pageAnimating = false;
    }
  }

  void _scrollTo(double target) {
    final clamped = target.clamp(
      _scroll.position.minScrollExtent,
      _scroll.position.maxScrollExtent,
    );
    if (MediaQuery.disableAnimationsOf(context)) {
      _scroll.jumpTo(clamped);
      return;
    }
    _scroll.animateTo(
      clamped,
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
    );
  }

  /// 电脑上的键盘：上下键、翻页键、空格翻页，F11 全屏，Esc 退出
  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;

    if (key == LogicalKeyboardKey.arrowDown ||
        key == LogicalKeyboardKey.pageDown ||
        key == LogicalKeyboardKey.space) {
      _page(1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp || key == LogicalKeyboardKey.pageUp) {
      _page(-1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.home) {
      _targetIndex = 0;
      if (_scroll.hasClients) _scrollTo(_scroll.position.minScrollExtent);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.end) {
      if (_files.isNotEmpty) _targetIndex = _files.length - 1;
      if (_scroll.hasClients) _scrollTo(_scroll.position.maxScrollExtent);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.f11) {
      unawaited(_toggleFullScreen());
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.escape) {
      unawaited(_exitFullScreenThenPop());
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  bool get _desktop =>
      Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  Future<void> _toggleFullScreen() async {
    if (!_desktop) return;
    try {
      await windowManager.setFullScreen(!await windowManager.isFullScreen());
    } on Object {
      // 桌面窗口管理器没接管时忽略
    }
  }

  Future<void> _exitFullScreenThenPop() async {
    if (_desktop) {
      try {
        if (await windowManager.isFullScreen()) {
          await windowManager.setFullScreen(false);
          return;
        }
      } on Object {
        // 忽略
      }
    }
    if (mounted) _exit();
  }

  /// 返回 / 关窗：手机上是退回上一页，电脑阅读窗口是关掉窗口
  void _exit() {
    final onExit = widget.onExit;
    if (onExit != null) {
      onExit();
      return;
    }
    if (Navigator.of(context).canPop()) Navigator.of(context).pop();
  }

  void _onScroll() {
    if (!_scroll.hasClients || _switching) return;
    _syncCurrentFromOffset();

    // 节流保存进度
    _saveThrottle?.cancel();
    _saveThrottle = Timer(const Duration(milliseconds: 600), _saveProgress);
  }

  /// 用固定的页面起始偏移算当前页，不再依赖 GlobalKey 的屏幕坐标
  void _syncCurrentFromOffset() {
    if (_startOffsets.length != _files.length || _startOffsets.isEmpty) return;

    final offset = _scroll.offset;
    var low = 0;
    var high = _startOffsets.length - 1;
    var found = 0;
    while (low <= high) {
      final mid = (low + high) >> 1;
      if (_startOffsets[mid] <= offset + 0.5) {
        found = mid;
        low = mid + 1;
      } else {
        high = mid - 1;
      }
    }
    if (_currentIndex != found) setState(() => _currentIndex = found);
  }

  /// 按屏幕宽度把高宽比换成像素高度，并算出每页的起始偏移
  void _ensureMetrics(double width) {
    if (_files.isEmpty) return;
    if ((_metricsWidth - width).abs() < 0.5 &&
        _startOffsets.length == _files.length) {
      return;
    }

    _metricsWidth = width;
    final heights = List<double>.generate(_files.length, (index) {
      final ratio = index < _ratios.length
          ? _ratios[index]
          : ImageAspect.fallback;
      return (width * ratio).clamp(80.0, 20000.0);
    });

    final starts = List<double>.filled(_files.length, 0);
    final initial = _initialIndex.clamp(0, _files.length - 1);
    for (var i = initial - 1; i >= 0; i--) {
      starts[i] = starts[i + 1] - heights[i];
    }
    for (var i = initial + 1; i < _files.length; i++) {
      starts[i] = starts[i - 1] + heights[i - 1];
    }

    _heights = heights;
    _startOffsets = starts;
  }

  Future<void> _saveProgress() async {
    if (_loading || _error != null || _files.isEmpty) return;
    await _progress.save(_currentIndex + 1);
  }

  void _openZoom(int index) {
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black,
        pageBuilder: (_, _, _) =>
            _ZoomViewer(files: _files, initialIndex: index),
      ),
    );
  }

  Future<void> _switchChapter(int delta) async {
    final target = widget.chapterIndex + delta;
    if (target < 1) return;
    if (widget.chapterCount > 0 && target > widget.chapterCount) return;

    final dir = await LocalLibrary.chapterDir(widget.sid, target);
    final files = dir == null
        ? const <File>[]
        : await JmStorage.listImages(dir);
    if (!mounted) return;

    if (files.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('第 $target 话还没有下载')));
      return;
    }

    if (_switching) return;
    _switching = true;
    _saveThrottle?.cancel();
    await _saveProgress();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => ReaderPage(
          sid: widget.sid,
          albumTitle: widget.albumTitle,
          chapterIndex: target,
          chapterCount: widget.chapterCount,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) {
          _saveThrottle?.cancel();
          unawaited(_saveProgress());
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: GestureDetector(
          onTap: () => setState(() => _showOverlay = !_showOverlay),
          child: Focus(
            autofocus: true,
            onKeyEvent: _onKeyEvent,
            child: Stack(
              children: [
                Positioned.fill(child: _buildContent()),
                if (_showOverlay) _buildTopBar(),
                if (_showOverlay) _buildBottomBar(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContent() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.inbox_outlined, size: 56, color: Colors.white38),
            const SizedBox(height: 12),
            Text(
              _error!,
              style: const TextStyle(color: Colors.white70),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton(onPressed: _exit, child: const Text('返回')),
          ],
        ),
      );
    }

    final width = MediaQuery.sizeOf(context).width;
    _ensureMetrics(width);
    final decodeWidth = (width * MediaQuery.devicePixelRatioOf(context))
        .round()
        .clamp(360, 1440);

    return ReadingStrip(
      controller: _scroll,
      initialIndex: _initialIndex,
      itemCount: _files.length,
      itemExtentBuilder: (index) =>
          index < _heights.length ? _heights[index] : null,
      itemBuilder: (context, index) {
        final height = index < _heights.length
            ? _heights[index]
            : width * ImageAspect.fallback;
        return SizedBox(
          height: height,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _openZoom(index),
            child: Image.file(
              _files[index],
              fit: BoxFit.contain,
              width: double.infinity,
              height: height,
              cacheWidth: decodeWidth,
              filterQuality: FilterQuality.medium,
              errorBuilder: (_, _, _) => const Center(
                child: Text(
                  '图片损坏',
                  style: TextStyle(color: Colors.white54),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildTopBar() {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: EdgeInsets.only(
          top: MediaQuery.of(context).padding.top + 4,
          bottom: 8,
          left: 8,
          right: 8,
        ),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.black87, Colors.transparent],
          ),
        ),
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: _exit,
            ),
            Expanded(
              child: Text(
                widget.albumTitle,
                style: const TextStyle(color: Colors.white),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Text(
              '第 ${widget.chapterIndex} 话  ${_currentIndex + 1}/${_files.length}',
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomBar() {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).padding.bottom + 8,
          top: 8,
        ),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [Colors.black87, Colors.transparent],
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            TextButton.icon(
              onPressed: () => _switchChapter(-1),
              icon: const Icon(Icons.skip_previous, color: Colors.white),
              label: const Text('上一话', style: TextStyle(color: Colors.white)),
            ),
            TextButton.icon(
              onPressed: () {
                if (_scroll.hasClients) {
                  setState(() {
                    _initialIndex = 0;
                    _currentIndex = 0;
                    _targetIndex = 0;
                    _metricsWidth = 0;
                  });
                  _scroll.jumpTo(0);
                  unawaited(_saveProgress());
                }
              },
              icon: const Icon(Icons.vertical_align_top, color: Colors.white),
              label: const Text('顶部', style: TextStyle(color: Colors.white)),
            ),
            TextButton.icon(
              onPressed: () => _switchChapter(1),
              icon: const Icon(Icons.skip_next, color: Colors.white),
              label: const Text('下一话', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }
}

/// 单图放大查看：双指缩放 + 拖动
class _ZoomViewer extends StatefulWidget {
  const _ZoomViewer({required this.files, required this.initialIndex});

  final List<File> files;
  final int initialIndex;

  @override
  State<_ZoomViewer> createState() => _ZoomViewerState();
}

class _ZoomViewerState extends State<_ZoomViewer> {
  late final PageController _controller = PageController(
    initialPage: widget.initialIndex,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('双指缩放 / 拖动查看'),
      ),
      body: PageView.builder(
        controller: _controller,
        itemCount: widget.files.length,
        itemBuilder: (context, index) => InteractiveViewer(
          minScale: 1,
          maxScale: 5,
          child: Center(
            child: Image.file(widget.files[index], fit: BoxFit.contain),
          ),
        ),
      ),
    );
  }
}
