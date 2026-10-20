/// 详情页：本子信息、章节列表、下载与追更（源无关）
library;

import 'package:flutter/material.dart';

import '../../data/app_database.dart';
import '../../jm/jm_storage.dart';
import '../../services/local_library.dart';
import '../../services/pdf_share_service.dart';
import '../../services/platform_service.dart';
import '../../source/comic_source.dart';
import '../../state/app_services.dart';
import '../widgets/album_cover.dart';
import '../widgets/category_picker.dart';
import '../widgets/source_badge.dart';
import '../reader_launcher.dart';

class DetailPage extends StatefulWidget {
  const DetailPage({super.key, required this.sid, this.title = ''});

  final SourceId sid;
  final String title;

  @override
  State<DetailPage> createState() => _DetailPageState();
}

class _DetailPageState extends State<DetailPage> {
  ComicDetail? _detail;
  bool _loading = true;
  String? _error;
  bool _subscribed = false;
  bool? _favorite;
  bool _favoriteBusy = false;
  bool _offline = false;
  bool _sharing = false;
  int _shareDone = 0;
  int _shareTotal = 0;

  /// 本地真有图的章节序号
  ///
  /// 只判断目录在不在是不够的：下载失败、中途取消都会留下空目录，
  /// 标着「可直接阅读」点进去却什么都没有。
  Set<int> _localChapters = const {};

  /// 本地封面（本子目录里第一张图）
  String _localCover = '';

  /// 这本书已经打包好的本地 PDF
  List<PdfPackageItem> _pdfPackages = const [];

  @override
  void initState() {
    super.initState();
    _load();
    AppServices.I.downloads.addListener(_onDownloadsChanged);
    AppServices.I.pdfPackagesRevision.addListener(_onPdfPackagesChanged);
  }

  @override
  void dispose() {
    AppServices.I.downloads.removeListener(_onDownloadsChanged);
    AppServices.I.pdfPackagesRevision.removeListener(_onPdfPackagesChanged);
    super.dispose();
  }

  void _onDownloadsChanged() {
    if (mounted) setState(() {});
  }

  void _onPdfPackagesChanged() {
    if (mounted) _refreshPackages();
  }

  Future<void> _refreshPackages() async {
    final packages = await PdfShareService.packagesForAlbum(widget.sid);
    if (!mounted) return;
    setState(() => _pdfPackages = packages);
  }

  /// 本地全部章节是不是已经有一份完整的 PDF
  bool get _allLocalPacked {
    if (_localChapters.isEmpty || _pdfPackages.isEmpty) return false;
    for (final item in _pdfPackages) {
      if (item.chapters.length != _localChapters.length) continue;
      if (item.chapters.every(_localChapters.contains)) return true;
    }
    return false;
  }

  ComicSource? get _source => AppServices.I.sources.byId(widget.sid);

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final source = _source;
      if (source == null) {
        throw SourceException('找不到源「${widget.sid.source}」');
      }
      final detail = await source.detail(widget.sid.id);
      if (!mounted) return;
      setState(() {
        _detail = detail;
        _subscribed = AppServices.I.subscriptions.contains(widget.sid);
        _favorite = detail.isFavorite;
        _loading = false;
      });
      await _refreshLocal();
    } on Exception catch (e) {
      if (!mounted) return;

      // 没网的时候也要能打开本地已下载的书：用本地章节拼一个详情页，
      // 至少能阅读、加入书架和导出 PDF。
      final local = await LocalLibrary.chapters(widget.sid);
      if (!mounted) return;
      if (local.isNotEmpty) {
        final title = widget.title.trim().isEmpty
            ? '本地漫画 ${widget.sid.id}'
            : widget.title.trim();
        setState(() {
          _detail = ComicDetail(
            sid: widget.sid,
            title: title,
            chapters: [
              for (final index in local)
                ComicChapter(
                  id: 'local-$index',
                  title: '第 $index 话',
                  index: index,
                  order: index,
                ),
            ],
            isFavorite: null,
            meta: const [MapEntry('来源', '本地已下载')],
          );
          _offline = true;
          _localChapters = local.toSet();
          _error = null;
          _loading = false;
        });
        await _refreshLocal();
        return;
      }

      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  DownloadTask? _taskOf(String chapterId) {
    for (final t in AppServices.I.downloads.tasks) {
      if (t.sid == widget.sid && t.chapterId == chapterId) return t;
    }
    return null;
  }

  Future<void> _downloadAll() async {
    final detail = _detail;
    if (detail == null) return;
    final added = await AppServices.I.downloads.enqueueAlbum(detail);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(added > 0 ? '已加入下载队列（$added 个章节）' : '这些章节已在队列中')),
    );
  }

  Future<void> _toggleSubscribe() async {
    final detail = _detail;
    if (detail == null) return;

    final service = AppServices.I.subscriptions;
    if (_subscribed) {
      await service.remove(widget.sid);
      if (!mounted) return;
      setState(() => _subscribed = false);
      return;
    }

    await service.add(
      sid: widget.sid,
      title: detail.title,
      author: detail.authorText,
      knownChapters: detail.chapterCount,
    );
    if (!mounted) return;
    setState(() => _subscribed = true);
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('已追更，有新章节时会提醒你')));
  }

  /// 收藏 / 取消收藏
  Future<void> _toggleFavorite() async {
    final detail = _detail;
    final source = _source;
    if (detail == null || source == null || _favoriteBusy) return;

    if (widget.sid.source == 'jm' && AppServices.I.account.value.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('请先在「设置 → 账号」登录 JM 账号')));
      return;
    }

    final want = !(_favorite ?? false);
    setState(() => _favoriteBusy = true);
    try {
      final now = await source.setFavorite(widget.sid.id, want: want);
      if (!mounted) return;
      setState(() {
        _favorite = now ?? want;
        _favoriteBusy = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text((_favorite ?? false) ? '已加入收藏' : '已取消收藏')),
      );
    } on Exception catch (e) {
      if (!mounted) return;
      setState(() => _favoriteBusy = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Flexible(
              child: Text(
                widget.title.isEmpty ? '本子详情' : widget.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            SourceBadge(source: widget.sid.source),
          ],
        ),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.error_outline,
                size: 48,
                color: Theme.of(context).colorScheme.error,
              ),
              const SizedBox(height: 12),
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton(onPressed: _load, child: const Text('重试')),
            ],
          ),
        ),
      );
    }

    final detail = _detail!;
    final chapters = detail.chapters;
    final isSingle = chapters.isEmpty;
    final isVideo = detail.mediaKind.isVideo;
    final rows = isSingle
        ? [
            ComicChapter(
              id: detail.sid.id,
              title: detail.title,
              index: 1,
              order: 1,
            ),
          ]
        : chapters;

    return ListView(
      padding: const EdgeInsets.only(bottom: 32),
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AlbumCover(
                albumId: detail.sid.id,
                coverUrl: detail.coverUrl,
                httpHeaders: detail.coverHeaders,
                localPath: _localCover,
                width: 120,
                height: 160,
                radius: 12,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      detail.title,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    _kv('作者', detail.authorText),
                    _kv('章节', isSingle ? '单章' : '${chapters.length} 章'),
                    for (final entry in detail.meta)
                      _kv(entry.key, entry.value),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (detail.tags.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(
              spacing: 8,
              runSpacing: 4,
              children: detail.tags
                  .map(
                    (t) => Chip(
                      label: Text(t),
                      visualDensity: VisualDensity.compact,
                    ),
                  )
                  .toList(),
            ),
          ),
        if (detail.description.trim().isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Text(
              detail.description,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        if (isVideo) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.tertiaryContainer,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.play_circle_outline,
                    size: 20,
                    color: Theme.of(context).colorScheme.onTertiaryContainer,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '这是视频内容，暂不支持下载和内置播放。'
                      '可以在原站打开观看。',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context)
                            .colorScheme
                            .onTertiaryContainer,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: detail.webUrl.trim().isEmpty
                    ? null
                    : () => PlatformService.openUrl(detail.webUrl.trim()),
                icon: const Icon(Icons.open_in_new),
                label: Text(
                  detail.webUrl.trim().isEmpty ? '暂无可用观看链接' : '打开原站观看',
                ),
              ),
            ),
          ),
        ] else ...[
          if (_offline)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.secondaryContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.cloud_off_outlined,
                      size: 18,
                      color: Theme.of(context).colorScheme.onSecondaryContainer,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '当前没有连上网络，只显示本地已下载的章节',
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context)
                              .colorScheme
                              .onSecondaryContainer,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                if (_offline)
                  Expanded(
                    child: Text(
                      '本地共 ${_localChapters.length} 话',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  )
                else
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _downloadAll,
                      icon: const Icon(Icons.download),
                      label: Text(
                        isSingle ? '下载本子' : '下载全部（${chapters.length} 章）',
                      ),
                    ),
                  ),
                // EH 的画廊就是固定的一话，没有「追更」这回事
                if (!_offline && widget.sid.source != 'eh') ...[
                  const SizedBox(width: 8),
                  IconButton.filledTonal(
                    onPressed: _toggleSubscribe,
                    icon: Icon(
                      _subscribed
                          ? Icons.notifications_active
                          : Icons.notifications_none,
                    ),
                    tooltip: _subscribed ? '取消追更' : '追更',
                  ),
                ],
                // isFavorite 为 null 表示这个源没有收藏接口（EH），不显示按钮，
                // 免得点了之后弹「已加入收藏」但其实什么都没发生
                if (!_offline && detail.isFavorite != null) ...[
                  const SizedBox(width: 8),
                  IconButton.filledTonal(
                    onPressed: _favoriteBusy ? null : _toggleFavorite,
                    icon: Icon(
                      (_favorite ?? false)
                          ? Icons.favorite
                          : Icons.favorite_border,
                      color: (_favorite ?? false) ? Colors.pinkAccent : null,
                    ),
                    tooltip: (_favorite ?? false) ? '取消收藏' : '收藏',
                  ),
                ],
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _addToShelf,
                    icon: const Icon(Icons.bookmark_add_outlined),
                    label: const Text('加入书架'),
                  ),
                ),
                if (_localChapters.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton.tonalIcon(
                      onPressed: _sharing ? null : _sharePdf,
                      icon: _sharing
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.picture_as_pdf_outlined),
                      label: Text(_sharing ? '生成中' : '分享 PDF'),
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (_pdfPackages.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
              child: Row(
                children: [
                  const Icon(
                    Icons.check_circle,
                    size: 14,
                    color: Color(0xFF2E7D32),
                  ),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      _allLocalPacked
                          ? '本地已打包！点击分享可直接发送，不会重新生成'
                          : '本地已打包 ${_pdfPackages.length} 份，点分享可选择直接发送',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF2E7D32),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          if (_sharing)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  LinearProgressIndicator(
                    value: _shareTotal > 0 ? _shareDone / _shareTotal : null,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _shareTotal > 0
                        ? '正在打包 $_shareDone / $_shareTotal 张图片'
                        : '正在准备 PDF…',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
        ],
        const Divider(height: 1),
        for (final chapter in rows) _chapterTile(chapter),
      ],
    );
  }

  /// 把本地章节打成一个 PDF，再调系统分享面板
  Future<void> _sharePdf() async {
    if (_sharing || _detail == null) return;

    final selected = await _pickShareChapters();
    if (selected == null || selected.isEmpty || !mounted) return;

    final settings = AppServices.I.settings.value;
    var password = settings.sharePdfPassword.trim();
    if (settings.sharePdfWithPassword && password.isEmpty) {
      final typed = await _askSharePassword();
      if (typed == null || typed.trim().isEmpty) return;
      password = typed.trim();
    }
    if (!settings.sharePdfWithPassword) password = '';

    final ordered = selected.toList()..sort();

    // 之前打包过一模一样的章节就直接发，不再重新拼一遍
    final cached = await PdfShareService.findPackage(
      sid: widget.sid,
      chapterIndexes: ordered,
      password: password,
    );
    if (!mounted) return;
    if (cached != null) {
      final shared = await PlatformService.shareFile(
        path: cached.path,
        title: cached.fileName,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            shared
                ? '已使用本地打包好的 PDF（${cached.pageCount} 页），没有重新生成'
                : '本地 PDF 在：${cached.path}',
          ),
        ),
      );
      return;
    }

    setState(() {
      _sharing = true;
      _shareDone = 0;
      _shareTotal = 0;
    });

    try {
      final result = await PdfShareService.buildAlbumPdf(
        sid: widget.sid,
        title: _detail!.title,
        chapterIndexes: ordered,
        fileNameBase: _shareFileName(ordered),
        password: password,
        onProgress: (done, total) {
          if (!mounted) return;
          setState(() {
            _shareDone = done;
            _shareTotal = total;
          });
        },
      );
      if (!mounted) return;

      final shared = await PlatformService.shareFile(
        path: result.path,
        title: result.fileName,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            shared
                ? 'PDF 已生成（${result.pageCount} 页），请在分享面板里选择 QQ、微信等'
                : 'PDF 已生成（${result.pageCount} 页）：${result.path}',
          ),
        ),
      );
    } on Exception catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('$error')));
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  /// 选择要打包的章节；只有一话时不用弹面板
  Future<Set<int>?> _pickShareChapters() async {
    final local = await LocalLibrary.chapters(widget.sid);
    if (!mounted) return null;
    if (local.isEmpty) return null;
    if (local.length == 1) return local.toSet();

    final selected = <int>{};
    return showModalBottomSheet<Set<int>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          final allSelected = selected.length == local.length;
          final packedSelection = _matchesPackedSelection(selected);
          return SafeArea(
            top: false,
            child: SizedBox(
              height: MediaQuery.sizeOf(ctx).height * 0.72,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 12, 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '选择要分享的章节',
                                style: Theme.of(ctx).textTheme.titleMedium,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '本地共 ${local.length} 话，可多选',
                                style: Theme.of(ctx).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                        TextButton(
                          onPressed: () {
                            setSheetState(() {
                              if (allSelected) {
                                selected.clear();
                              } else {
                                selected
                                  ..clear()
                                  ..addAll(local);
                              }
                            });
                          },
                          child: Text(allSelected ? '取消全选' : '全选'),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: ListView.builder(
                      itemCount: local.length,
                      itemBuilder: (ctx, i) {
                        final index = local[i];
                        return CheckboxListTile(
                          value: selected.contains(index),
                          onChanged: (checked) {
                            setSheetState(() {
                              if (checked ?? false) {
                                selected.add(index);
                              } else {
                                selected.remove(index);
                              }
                            });
                          },
                          title: Text(
                            _chapterLabel(index),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          controlAffinity: ListTileControlAffinity.leading,
                          dense: true,
                        );
                      },
                    ),
                  ),
                  if (packedSelection)
                    const Padding(
                      padding: EdgeInsets.fromLTRB(20, 6, 20, 0),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          '这组章节本地已打包，点下面会直接分享，不会重新生成',
                          style: TextStyle(
                            fontSize: 12,
                            color: Color(0xFF2E7D32),
                          ),
                        ),
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                    child: SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: selected.isEmpty
                            ? null
                            : () => Navigator.pop(ctx, Set<int>.from(selected)),
                        child: Text(
                          selected.isEmpty
                              ? '请选择章节'
                              : packedSelection
                              ? '分享已打包 PDF（已选 ${selected.length} 话）'
                              : '生成 PDF（已选 ${selected.length} 话）',
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  bool _matchesPackedSelection(Set<int> selected) {
    if (selected.isEmpty) return false;
    for (final item in _pdfPackages) {
      if (item.chapters.length != selected.length) continue;
      if (item.chapters.every(selected.contains)) return true;
    }
    return false;
  }

  String _chapterLabel(int index) {
    for (final chapter in _detail?.chapters ?? const <ComicChapter>[]) {
      if (chapter.index != index) continue;
      final title = chapter.title.trim();
      if (title.isNotEmpty) return title;
    }
    return '第 $index 话';
  }

  String _shareFileName(List<int> selected) {
    final title = _detail!.title;
    if (selected.length == 1) {
      return '$title - ${_chapterLabel(selected.first)}';
    }
    if (selected.length < _localChapters.length) {
      return '$title - 已选${selected.length}话';
    }
    return title;
  }

  Future<String?> _askSharePassword() async {
    final controller = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('输入 PDF 打开密码'),
        content: TextField(
          controller: controller,
          autofocus: true,
          obscureText: true,
          decoration: const InputDecoration(hintText: '收到的人打开 PDF 时需要输入'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('开始生成'),
          ),
        ],
      ),
    );
    controller.dispose();
    return value;
  }

  /// 把本子收进书架并挑选分类
  ///
  /// 没下载也能先收着——书架本来就不等于「已下载」，
  /// 很多人是先收藏再慢慢下。
  Future<void> _addToShelf() async {
    final detail = _detail;
    if (detail == null) return;

    final dao = AppServices.I.dao;
    final existing = await dao.getBookshelf(detail.sid);
    final done = AppServices.I.downloads.tasks
        .where((t) => t.sid == detail.sid && t.status == DownloadStatus.done)
        .map((t) => t.chapterIndex)
        .toSet()
        .length;

    await dao.upsertBookshelf(
      sid: detail.sid,
      title: detail.title,
      author: detail.authorText,
      coverUrl: detail.coverUrl,
      tags: detail.tags.join(' '),
      chapterCount: detail.chapterCount,
      downloaded: done > 0 ? done : (existing?.downloaded ?? 0),
      rootPath: AppServices.I.rootDir.value,
    );
    await AppServices.I.reloadLibrary();

    if (!mounted) return;
    final picked = await CategoryPicker.show(context, sid: detail.sid);
    if (picked == null) return;

    await dao.setCategoriesOf(detail.sid, picked);
    await AppServices.I.reloadLibrary();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          picked.isEmpty ? '已加入书架（还没选分类）' : '已加入书架，归到 ${picked.length} 个分类',
        ),
      ),
    );
  }

  /// 看看本地到底有哪些话、封面用哪张
  Future<void> _refreshLocal() async {
    final chapters = await LocalLibrary.chapters(widget.sid);
    final packages = await PdfShareService.packagesForAlbum(widget.sid);

    var cover = '';
    if (chapters.isNotEmpty) {
      final dir = await LocalLibrary.chapterDir(widget.sid, chapters.first);
      if (dir != null) {
        cover = (await JmStorage.firstImage(dir))?.path ?? '';
      }
    }

    if (!mounted) return;
    setState(() {
      _localChapters = chapters.toSet();
      _localCover = cover;
      _pdfPackages = packages;
    });
  }

  Widget _chapterTile(ComicChapter chapter) {
    final task = _taskOf(chapter.id);
    final detail = _detail!;
    final isVideo = detail.mediaKind.isVideo;

    return ListTile(
      title: Text(
        chapter.title.isEmpty ? '第 ${chapter.index} 话' : chapter.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: isVideo
          ? const Text('视频内容 · 暂不支持下载和内置播放')
          : _taskSubtitle(task) ?? _localSubtitle(chapter.index),
      leading: CircleAvatar(
        radius: 18,
        child: Text('${chapter.index}', style: const TextStyle(fontSize: 12)),
      ),
      onTap: isVideo
          ? (detail.webUrl.trim().isEmpty
                ? null
                : () => PlatformService.openUrl(detail.webUrl.trim()))
          : () => _openReader(chapter.index),
      trailing: isVideo
          ? IconButton(
              icon: const Icon(Icons.open_in_new),
              tooltip: '在原站观看',
              onPressed: detail.webUrl.trim().isEmpty
                  ? null
                  : () => PlatformService.openUrl(detail.webUrl.trim()),
            )
          : _offline
          ? const Icon(Icons.check_circle, color: Colors.green)
          : _taskTrailing(task, detail, chapter),
    );
  }

  /// 没有下载记录时，看看本地是不是真有这一话（重装应用后仍能识别）
  Widget? _localSubtitle(int chapterIndex) {
    if (!_localChapters.contains(chapterIndex)) return null;
    return const Text('本地已存在，可直接阅读');
  }

  Widget? _taskSubtitle(DownloadTask? task) {
    if (task == null) return null;
    switch (task.status) {
      case DownloadStatus.pending:
        return const Text('等待下载');
      case DownloadStatus.running:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('下载中 ${task.done}/${task.total}'),
            const SizedBox(height: 4),
            LinearProgressIndicator(value: task.progress),
          ],
        );
      case DownloadStatus.paused:
        return const Text('已暂停');
      case DownloadStatus.done:
        return Text(task.error.isEmpty ? '已下载' : '已下载（${task.error}）');
      case DownloadStatus.failed:
        return Text(
          '失败：${task.error}',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        );
    }
  }

  Widget _taskTrailing(
    DownloadTask? task,
    ComicDetail detail,
    ComicChapter chapter,
  ) {
    if (task == null) {
      return IconButton(
        icon: const Icon(Icons.download_outlined),
        tooltip: '下载本章',
        onPressed: () async {
          await AppServices.I.downloads.enqueueChapter(
            detail: detail,
            chapter: chapter,
          );
        },
      );
    }

    switch (task.status) {
      case DownloadStatus.pending:
      case DownloadStatus.running:
        return IconButton(
          icon: const Icon(Icons.pause_circle_outline),
          tooltip: '暂停',
          onPressed: () => AppServices.I.downloads.cancelTask(task.id),
        );
      case DownloadStatus.paused:
      case DownloadStatus.failed:
        return IconButton(
          icon: const Icon(Icons.refresh),
          tooltip: '继续',
          onPressed: () => AppServices.I.downloads.retryTask(task.id),
        );
      case DownloadStatus.done:
        return const Icon(Icons.check_circle, color: Colors.green);
    }
  }

  Widget _kv(String key, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 40,
            child: Text(
              key,
              style: TextStyle(
                color: Theme.of(context).colorScheme.outline,
                fontSize: 12,
              ),
            ),
          ),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 12))),
        ],
      ),
    );
  }

  void _openReader(int chapterIndex) {
    openReader(
      context,
      sid: widget.sid,
      albumTitle: _detail!.title,
      chapterIndex: chapterIndex,
      chapterCount: _detail!.chapterCount,
    );
  }
}
