/// 阅读器：纵向滚动 + 音量键翻页 + 点击放大 + 进度记忆 + 章节切换
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../jm/jm_storage.dart';
import '../../services/local_library.dart';
import '../../services/platform_service.dart';
import '../../source/comic_source.dart';
import '../../state/app_services.dart';

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

class _ReaderPageState extends State<ReaderPage> {
  final ScrollController _scroll = ScrollController();
  final List<GlobalKey> _keys = [];

  List<File> _files = const [];
  bool _loading = true;
  String? _error;
  bool _showOverlay = true;

  int _currentIndex = 0;
  Timer? _saveThrottle;
  double _lastOffset = 0;

  @override
  void initState() {
    super.initState();
    _load();
    PlatformService.onVolumeKey = _onVolumeKey;
    PlatformService.setVolumeKeyEnabled(
      AppServices.I.settings.value.volumeKeyPageTurn,
    );
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    PlatformService.onVolumeKey = null;
    PlatformService.setVolumeKeyEnabled(false);
    _saveThrottle?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
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

    _keys
      ..clear()
      ..addAll(List.generate(files.length, (_) => GlobalKey()));

    setState(() {
      _files = files;
      _loading = false;
    });

    await _restoreProgress();
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

  Future<void> _restoreProgress() async {
    final item = await AppServices.I.dao.getBookshelf(widget.sid);
    if (item == null || !mounted) return;
    if (item.lastChapter != widget.chapterIndex) return;

    final index = (item.lastPage - 1).clamp(0, _files.length - 1);
    _currentIndex = index;

    // 等首帧布局完成后再跳转
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      final ctx = index < _keys.length ? _keys[index].currentContext : null;
      if (ctx == null) return;
      final box = ctx.findRenderObject() as RenderBox?;
      if (box == null) return;
      final target = _scroll.offset + box.localToGlobal(Offset.zero).dy;
      _scroll.jumpTo(target.clamp(0, _scroll.position.maxScrollExtent));
    });
  }

  /// 音量键翻页：音量上键往上翻（上一页），音量下键往下翻（下一页）
  void _onVolumeKey(int delta) {
    if (!mounted || !_scroll.hasClients) return;
    if (!AppServices.I.settings.value.volumeKeyPageTurn) return;

    final step = _scroll.position.viewportDimension * 0.92;
    // delta: +1 音量上键 -> 往上；-1 音量下键 -> 往下，所以是减去
    final target = (_scroll.offset - delta * step).clamp(
      0.0,
      _scroll.position.maxScrollExtent,
    );
    _scroll.animateTo(
      target,
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
    );
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;

    // 找出当前位于视口顶部的图片
    for (var i = 0; i < _keys.length; i++) {
      final ctx = _keys[i].currentContext;
      if (ctx == null) continue;
      final box = ctx.findRenderObject() as RenderBox?;
      if (box == null) continue;
      final top = box.localToGlobal(Offset.zero).dy;
      if (top <= 1) {
        _currentIndex = i;
      } else {
        break;
      }
    }

    // 节流保存进度
    _saveThrottle?.cancel();
    _saveThrottle = Timer(const Duration(milliseconds: 600), _saveProgress);
  }

  Future<void> _saveProgress() async {
    final offset = _scroll.hasClients ? _scroll.offset : _lastOffset;
    _lastOffset = offset;
    await AppServices.I.dao.updateReadProgress(
      widget.sid,
      widget.chapterIndex,
      _currentIndex + 1,
    );
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
    return Scaffold(
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

    return ListView.builder(
      controller: _scroll,
      physics: const BouncingScrollPhysics(),
      padding: EdgeInsets.zero,
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
                  _scroll.animateTo(
                    0,
                    duration: const Duration(milliseconds: 250),
                    curve: Curves.easeOut,
                  );
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
