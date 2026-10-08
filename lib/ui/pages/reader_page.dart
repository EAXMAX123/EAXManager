/// 阅读器：纵向滚动 + 音量键翻页 + 点击放大 + 进度记忆 + 章节切换
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../jm/jm_storage.dart';
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
  });

  final SourceId sid;
  final String albumTitle;
  final int chapterIndex;
  final int chapterCount;

  @override
  State<ReaderPage> createState() => _ReaderPageState();
}

class _ReaderPageState extends State<ReaderPage> with WidgetsBindingObserver {
  final ScrollController _scroll = ScrollController();
  final List<GlobalKey> _keys = [];

  List<File> _files = const [];
  bool _loading = true;
  String? _error;
  bool _showOverlay = true;

  int _currentIndex = 0;
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

    final saved = await AppServices.I.dao.getBookshelf(widget.sid);
    if (!mounted) return;
    _initialIndex = saved != null && saved.lastChapter == widget.chapterIndex
        ? (saved.lastPage - 1).clamp(0, files.length - 1)
        : 0;
    _currentIndex = _initialIndex;
    _keys
      ..clear()
      ..addAll(List.generate(files.length, (_) => GlobalKey()));

    setState(() {
      _files = files;
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
    if (!mounted || !_scroll.hasClients) return;
    if (ModalRoute.of(context)?.isCurrent != true) return;
    if (!AppServices.I.settings.value.volumeKeyPageTurn) return;

    final step = _scroll.position.viewportDimension * 0.92;
    // delta: +1 音量上键 -> 往上；-1 音量下键 -> 往下，所以是减去
    final target = (_scroll.offset - delta * step).clamp(
      _scroll.position.minScrollExtent,
      _scroll.position.maxScrollExtent,
    );
    if (MediaQuery.disableAnimationsOf(context)) {
      _scroll.jumpTo(target);
      return;
    }
    _scroll.animateTo(
      target,
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
    );
  }

  void _onScroll() {
    if (!_scroll.hasClients || _switching) return;

    // 找出当前位于视口顶部的图片
    for (var i = 0; i < _keys.length; i++) {
      final ctx = _keys[i].currentContext;
      if (ctx == null) continue;
      final box = ctx.findRenderObject() as RenderBox?;
      if (box == null || !box.hasSize) continue;
      final top = box.localToGlobal(Offset.zero).dy;
      if (top <= 1 && top + box.size.height > 1) {
        if (_currentIndex != i) setState(() => _currentIndex = i);
        break;
      }
    }

    // 节流保存进度
    _saveThrottle?.cancel();
    _saveThrottle = Timer(const Duration(milliseconds: 600), _saveProgress);
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
          child: Stack(
            children: [
              Positioned.fill(child: _buildContent()),
              if (_showOverlay) _buildTopBar(),
              if (_showOverlay) _buildBottomBar(),
            ],
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
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('返回'),
            ),
          ],
        ),
      );
    }

    return ReadingStrip(
      controller: _scroll,
      initialIndex: _initialIndex,
      itemCount: _files.length,
      itemBuilder: (context, index) {
        return GestureDetector(
          key: _keys[index],
          onTap: () => _openZoom(index),
          child: Image.file(
            _files[index],
            fit: BoxFit.fitWidth,
            width: double.infinity,
            errorBuilder: (_, _, _) => const SizedBox(
              height: 200,
              child: Center(
                child: Text('图片损坏', style: TextStyle(color: Colors.white54)),
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
              onPressed: () => Navigator.of(context).pop(),
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
