/// 识图页：从相册选图，反查这是哪一本
///
/// 两个识图站（SauceNAO / IQDB）都是第三方公共服务，图片会被上传过去，
/// 页面上写清楚这一点，不做偷偷上传。设置也放在这一页，免得散到设置页里
/// 找不着。
library;

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../services/platform_service.dart';
import '../../source/image_search/image_prep.dart';
import '../../source/image_search/image_search_models.dart';
import '../../state/app_services.dart';
import 'keyword_search_page.dart';

class ImageSearchPage extends StatefulWidget {
  const ImageSearchPage({super.key});

  @override
  State<ImageSearchPage> createState() => _ImageSearchPageState();
}

class _ImageSearchPageState extends State<ImageSearchPage>
    with AutomaticKeepAliveClientMixin {
  final TextEditingController _keyController = TextEditingController();

  Uint8List? _picked;
  String _pickedName = '';

  bool _busy = false;
  bool _lensBusy = false;
  String _stage = '';
  String? _fatal;
  ImageSearchReport? _report;

  late double _threshold = AppServices.I.settings.value.imageSearchThreshold
      .toDouble();
  late bool _segment = AppServices.I.settings.value.imageSearchSegment;
  late bool _useIqdb = AppServices.I.settings.value.imageSearchUseIqdb;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _keyController.text = AppServices.I.settings.value.imageSearchKey;
  }

  @override
  void dispose() {
    _keyController.dispose();
    super.dispose();
  }

  // ==================== 选图与识图 ====================

  Future<void> _pick() async {
    try {
      final file = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        // 只挡一下超大的图，真正裁边缩放交给 ImagePrep，避免二次压缩
        maxWidth: 3000,
        maxHeight: 3000,
      );
      if (file == null) return;
      final bytes = await file.readAsBytes();
      if (!mounted) return;
      setState(() {
        _picked = bytes;
        _pickedName = file.name;
        _report = null;
        _fatal = null;
      });
    } on Exception catch (e) {
      if (!mounted) return;
      setState(() => _fatal = '打不开相册：$e');
    }
  }

  Future<void> _run() async {
    final bytes = _picked;
    if (bytes == null) {
      setState(() => _fatal = '先选一张图');
      return;
    }

    setState(() {
      _busy = true;
      _fatal = null;
      _report = null;
      _stage = '正在准备图片…';
    });

    try {
      final report = await AppServices.I.imageSearch.search(
        bytes,
        segmentRetry: _segment,
        threshold: _threshold,
        onProgress: (stage) {
          if (mounted) setState(() => _stage = stage);
        },
      );
      if (!mounted) return;
      setState(() {
        _report = report;
        _busy = false;
        _stage = '';
      });
    } on Exception catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _stage = '';
        _fatal = '识图失败：$e';
      });
    }
  }

  /// 用 Google Lens 搜：上传交给软件做，结果页交给浏览器打开
  ///
  /// Lens 的结果页是纯 JS 的，Dart 解析不出来，所以这里不做解析，
  /// 只把「手动在 Google 页面上选文件」这一步省掉。
  Future<void> _runLens() async {
    final bytes = _picked;
    if (bytes == null) {
      setState(() => _fatal = '先选一张图');
      return;
    }

    setState(() {
      _lensBusy = true;
      _fatal = null;
    });

    try {
      final prepared = ImagePrep.prepare(bytes);
      if (prepared == null) {
        setState(() {
          _lensBusy = false;
          _fatal = '这张图解不开';
        });
        return;
      }

      final url = await AppServices.I.imageSearch.lensUrl(prepared.bytes);
      if (!mounted) return;
      setState(() => _lensBusy = false);

      final opened = await PlatformService.openUrl(url);
      if (!opened && mounted) {
        setState(() => _fatal = '打不开浏览器，结果地址是：$url');
      }
    } on Exception catch (e) {
      if (!mounted) return;
      setState(() {
        _lensBusy = false;
        _fatal = 'Google Lens 用不了：$e';
      });
    }
  }

  void _openKeywordSearch(String keyword) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => KeywordSearchPage(query: keyword)),
    );
  }

  // ==================== 设置 ====================

  Future<void> _saveKey() async {
    final settings = AppServices.I.settings.value;
    await AppServices.I.updateSettings(
      settings.copyWith(imageSearchKey: _keyController.text.trim()),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('已保存')));
  }

  Future<void> _saveThreshold(double value) async {
    final settings = AppServices.I.settings.value;
    await AppServices.I.updateSettings(
      settings.copyWith(imageSearchThreshold: value.round()),
    );
  }

  Future<void> _saveSegment(bool value) async {
    setState(() => _segment = value);
    final settings = AppServices.I.settings.value;
    await AppServices.I.updateSettings(
      settings.copyWith(imageSearchSegment: value),
    );
  }

  Future<void> _saveUseIqdb(bool value) async {
    setState(() => _useIqdb = value);
    final settings = AppServices.I.settings.value;
    await AppServices.I.updateSettings(
      settings.copyWith(imageSearchUseIqdb: value),
    );
  }

  // ==================== 界面 ====================

  @override
  Widget build(BuildContext context) {
    super.build(context);

    return ListView(
      padding: const EdgeInsets.only(bottom: 32),
      children: [
        _pickCard(),
        _settingsTile(),
        if (_busy) _progressCard(),
        if (_fatal != null) _messageCard(_fatal!, isError: true),
        if (_report != null) ..._reportSection(_report!),
        if (_picked == null && !_busy) _emptyHint(),
      ],
    );
  }

  Widget _pickCard() {
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 6),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(
                    width: 76,
                    height: 76,
                    child: _picked == null
                        ? Container(
                            color: theme.colorScheme.surfaceContainerHighest,
                            child: Icon(
                              Icons.image_outlined,
                              color: theme.colorScheme.outline,
                            ),
                          )
                        : Image.memory(_picked!, fit: BoxFit.cover),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _picked == null ? '从相册选一张图' : '已选好图片',
                        style: theme.textTheme.titleSmall,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _picked == null
                            ? '封面图命中率最高，内页基本认不出'
                            : _pickedName,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.outline,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: _busy ? null : _pick,
                    icon: const Icon(Icons.photo_library_outlined, size: 18),
                    label: const Text('选图'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: (_picked == null || _busy) ? null : _run,
                    icon: const Icon(Icons.search, size: 18),
                    label: const Text('识图'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: (_picked == null || _busy || _lensBusy)
                    ? null
                    : _runLens,
                icon: _lensBusy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.travel_explore, size: 18),
                label: const Text('用 Google Lens 搜（需梯子）'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _settingsTile() {
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        leading: const Icon(Icons.tune),
        title: const Text('识图设置'),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        children: [
          TextField(
            controller: _keyController,
            decoration: InputDecoration(
              labelText: 'SauceNAO API key（可留空）',
              helperText: '留空走匿名通道，每 30 秒只能搜 3 次',
              helperMaxLines: 2,
              suffixIcon: TextButton(
                onPressed: _saveKey,
                child: const Text('保存'),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Text('相似度门槛'),
              Expanded(
                child: Slider(
                  value: _threshold,
                  min: 30,
                  max: 90,
                  divisions: 12,
                  label: '${_threshold.round()}%',
                  onChanged: (v) => setState(() => _threshold = v),
                  onChangeEnd: _saveThreshold,
                ),
              ),
              SizedBox(
                width: 44,
                child: Text(
                  '${_threshold.round()}%',
                  textAlign: TextAlign.end,
                ),
              ),
            ],
          ),
          Text(
            '整图搜到的最高相似度低于这个数，就切上中下三段再搜一遍',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _segment,
            onChanged: _saveSegment,
            title: const Text('分段重搜'),
            subtitle: const Text('整图认不出时切开再搜，命中率更高但更慢'),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _useIqdb,
            onChanged: _saveUseIqdb,
            title: const Text('同时查 IQDB'),
            subtitle: const Text('免费不限量，但索引偏动画向，对本子帮助有限'),
          ),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.info_outline,
                size: 16,
                color: theme.colorScheme.outline,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '识图时图片会上传给 SauceNAO 和 IQDB 这两个第三方服务，'
                  '不想上传就别点「识图」。',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _progressCard() {
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 14),
            Expanded(child: Text(_stage.isEmpty ? '正在识图…' : _stage)),
          ],
        ),
      ),
    );
  }

  Widget _messageCard(String text, {bool isError = false}) {
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      color: isError
          ? theme.colorScheme.errorContainer
          : theme.colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              isError ? Icons.error_outline : Icons.lightbulb_outline,
              size: 18,
            ),
            const SizedBox(width: 10),
            Expanded(child: Text(text)),
          ],
        ),
      ),
    );
  }

  List<Widget> _reportSection(ImageSearchReport report) {
    final out = <Widget>[];

    if (report.notice.isNotEmpty) {
      out.add(_messageCard(report.notice));
    }

    if (report.matches.isEmpty) {
      out.add(_attemptSummary(report));
      return out;
    }

    out.add(
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 2),
        child: Text(
          '找到 ${report.matches.length} 条（已按相似度排序）',
          style: Theme.of(context).textTheme.titleSmall,
        ),
      ),
    );

    for (final match in report.matches) {
      out.add(_matchCard(match));
    }

    out.add(_attemptSummary(report));
    return out;
  }

  Widget _attemptSummary(ImageSearchReport report) {
    if (report.attempts.isEmpty) return const SizedBox.shrink();

    final lines = <String>[];
    for (final attempt in report.attempts) {
      lines.add(
        attempt.ok
            ? '${attempt.engine} · ${attempt.region}：${attempt.count} 条'
            : '${attempt.engine} · ${attempt.region}：失败（${attempt.error}）',
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Text(
        lines.join('\n'),
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: Theme.of(context).colorScheme.outline,
        ),
      ),
    );
  }

  Widget _matchCard(ImageMatch match) {
    final theme = Theme.of(context);
    final reliable = match.similarity >= _threshold;
    final keywords = match.keywords;

    return Card(
      margin: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: SizedBox(
                    width: 64,
                    height: 64,
                    child: match.thumbnailUrl.isEmpty
                        ? Container(
                            color: theme.colorScheme.surfaceContainerHighest,
                            child: Icon(
                              Icons.broken_image_outlined,
                              size: 20,
                              color: theme.colorScheme.outline,
                            ),
                          )
                        : Image.network(
                            match.thumbnailUrl,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => Container(
                              color: theme.colorScheme.surfaceContainerHighest,
                              child: Icon(
                                Icons.broken_image_outlined,
                                size: 20,
                                color: theme.colorScheme.outline,
                              ),
                            ),
                          ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          _chip(
                            '${match.similarity.toStringAsFixed(1)}%',
                            reliable
                                ? theme.colorScheme.primary
                                : theme.colorScheme.outline,
                          ),
                          _chip(match.index, theme.colorScheme.tertiary),
                          _chip(match.engine, theme.colorScheme.secondary),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        match.title.isEmpty
                            ? '（这个来源没给出作品名）'
                            : match.title,
                        style: theme.textTheme.titleSmall,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (match.author.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          '作者：${match.author}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            if (_extraFields(match).isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                _extraFields(match),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),
            ],
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final keyword in keywords.take(2))
                  FilledButton.tonalIcon(
                    onPressed: () => _openKeywordSearch(keyword),
                    icon: const Icon(Icons.search, size: 18),
                    label: Text('用「${_short(keyword)}」搜'),
                  ),
                if (match.sourceUrl.isNotEmpty)
                  TextButton.icon(
                    onPressed: () => PlatformService.openUrl(match.sourceUrl),
                    icon: const Icon(Icons.open_in_new, size: 18),
                    label: const Text('打开来源页'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 标题和作者已经在上面显示了，这里只补别的字段
  static String _extraFields(ImageMatch match) {
    final parts = <String>[];
    for (final entry in match.fields.entries) {
      if (entry.key == 'Title' || entry.key == 'Author') continue;
      final value = entry.value.trim();
      if (value.isEmpty) continue;
      parts.add('${entry.key}：$value');
    }
    return parts.join('　');
  }

  static String _short(String text) =>
      text.length <= 14 ? text : '${text.substring(0, 14)}…';

  Widget _chip(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _emptyHint() {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 0),
      child: Column(
        children: [
          Icon(
            Icons.image_search,
            size: 48,
            color: theme.colorScheme.outline,
          ),
          const SizedBox(height: 12),
          Text(
            '选一张图，软件会去 SauceNAO 和 IQDB 反查它出自哪一本，\n'
            '认出作品名后可以直接拿去四个源里搜。',
            textAlign: TextAlign.center,
            style: TextStyle(color: theme.colorScheme.outline),
          ),
        ],
      ),
    );
  }
}
