/// 以图搜图的编排
///
/// 两个站一起问，结果合并去重。SauceNAO 先只搜一次整图；认不出来才切上中下
/// 三段再搜 —— 分段很吃请求数，匿名通道每 30 秒只给 3 次，能省就省。
library;

import 'dart:typed_data';

import '../../net/net_transport.dart';
import '../comic_source.dart';
import 'google_lens_client.dart';
import 'image_prep.dart';
import 'image_search_models.dart';
import 'iqdb_client.dart';
import 'saucenao_client.dart';

/// 进度回调：给界面显示「正在搜什么」
typedef ImageSearchProgress = void Function(String stage);

class ImageSearchService {
  ImageSearchService({
    required NetTransport transport,
    String sauceNaoKey = '',
    this.enableSauceNao = true,
    this.enableIqdb = true,
  }) : _transport = transport,
       _key = sauceNaoKey,
       _sauceNao = SauceNaoClient(transport: transport, apiKey: sauceNaoKey);

  NetTransport _transport;

  String _key;

  bool enableSauceNao;
  bool enableIqdb;

  SauceNaoClient _sauceNao;

  IqdbClient? _iqdb;

  GoogleLensClient? _lens;

  NetTransport get transport => _transport;

  /// 换代理 / 换线路之后要重建客户端
  ///
  /// 这几个客户端都在构造时就把 transport 存下来了，只改字段是没用的 ——
  /// 那样用户改完代理，识图仍然走旧配置，而且不会有任何报错。
  set transport(NetTransport value) {
    if (value.signature == _transport.signature) return;
    _transport = value;
    _sauceNao = SauceNaoClient(transport: value, apiKey: _key);
    _iqdb = null;
    _lens = null;
  }

  IqdbClient get iqdb => _iqdb ??= IqdbClient(transport: _transport);

  GoogleLensClient get lens => _lens ??= GoogleLensClient(transport: _transport);

  /// 两次 SauceNAO 请求之间至少隔这么久
  ///
  /// 匿名限速是「每 30 秒 3 次」，理论上要隔 10 秒才绝对安全。但绝大多数
  /// 情况只发一两次请求，隔 10 秒纯粹是浪费时间，所以这里只做基本间隔，
  /// 真被限速了再按服务器给的提示等。
  static const Duration _minGap = Duration(milliseconds: 1200);

  DateTime _lastSauceNao = DateTime.fromMillisecondsSinceEpoch(0);

  /// 改了 key 之后重新配置
  void configure({String? sauceNaoKey, bool? enableSauceNao, bool? enableIqdb}) {
    if (sauceNaoKey != null) {
      _key = sauceNaoKey;
      _sauceNao.apiKey = sauceNaoKey;
    }
    if (enableSauceNao != null) this.enableSauceNao = enableSauceNao;
    if (enableIqdb != null) this.enableIqdb = enableIqdb;
  }

  /// 把图片传给 Google Lens，返回结果页地址
  ///
  /// 只有上传这一步在这里做，结果的解析在浏览器里进行（见 GoogleLensClient 的说明）。
  Future<String> lensUrl(Uint8List jpeg, {String filename = 'image.jpg'}) =>
      lens.resultUrl(jpeg, filename: filename);

  /// 识图主流程
  ///
  /// [segmentRetry] 打开时，整图认不出来会把图片切成上中下三段再各搜一次。
  /// [threshold] 是「够可信」的相似度门槛，低于它就认为还需要再试。
  Future<ImageSearchReport> search(
    Uint8List raw, {
    bool segmentRetry = true,
    double threshold = 60,
    ImageSearchProgress? onProgress,
  }) async {
    final prepared = ImagePrep.prepare(raw);
    if (prepared == null) {
      return const ImageSearchReport(notice: '这张图解不开，换一张试试');
    }
    if (prepared.width < ImagePrep.minSide ||
        prepared.height < ImagePrep.minSide) {
      return ImageSearchReport(
        notice:
            '图片太小了（${prepared.width}×${prepared.height}），'
            '识图站认不出来，换张清晰点的',
      );
    }

    final attempts = <ImageSearchAttempt>[];
    var notice = '';
    final collected = <ImageMatch>[];

    onProgress?.call('正在搜整图…');
    final first = await _queryAll(prepared.bytes, '整图', attempts);
    collected.addAll(first);

    var best = _bestSimilarity(collected);
    if (segmentRetry && best < threshold && enableSauceNao) {
      final regions = ImagePrep.regions(prepared);
      for (final region in regions) {
        if (best >= threshold) break;
        onProgress?.call('整图没认出来，正在搜${region.label}…');
        final items = await _queryAll(region.bytes, region.label, attempts);
        collected.addAll(items);
        best = _bestSimilarity(collected);
      }
    }

    if (attempts.any((e) => e.error.contains('限速'))) {
      notice =
          'SauceNAO 匿名通道被限速了（每 30 秒 3 次），这次少搜了几轮。'
          '在下面填一个自己的 API key 可以放宽限制。';
    }

    final merged = mergeMatches(collected);
    if (merged.isEmpty && notice.isEmpty) {
      notice = segmentRetry
          ? '没找到匹配。这张图可能不在识图站的索引里（内页比封面难认很多）'
          : '没找到匹配';
    }

    return ImageSearchReport(
      matches: merged,
      attempts: attempts,
      notice: notice,
    );
  }

  /// 同一个图块同时问两个站
  Future<List<ImageMatch>> _queryAll(
    Uint8List bytes,
    String region,
    List<ImageSearchAttempt> attempts,
  ) async {
    final results = await Future.wait([
      if (enableSauceNao) _askSauceNao(bytes, region, attempts),
      if (enableIqdb) _askIqdb(bytes, region, attempts),
    ]);
    return [for (final list in results) ...list];
  }

  Future<List<ImageMatch>> _askSauceNao(
    Uint8List bytes,
    String region,
    List<ImageSearchAttempt> attempts,
  ) async {
    for (var round = 0; round < 2; round++) {
      final gap = DateTime.now().difference(_lastSauceNao);
      if (gap < _minGap) await Future<void>.delayed(_minGap - gap);

      try {
        _lastSauceNao = DateTime.now();
        final items = await _sauceNao.search(bytes);
        attempts.add(
          ImageSearchAttempt(engine: 'SauceNAO', region: region, count: items.length),
        );
        return items;
      } on ImageSearchThrottled catch (e) {
        // 第一次被限速就按服务器说的等一会儿再来；第二次还是不行就放弃这一轮
        if (round == 0) {
          await Future<void>.delayed(e.wait);
          continue;
        }
        attempts.add(
          ImageSearchAttempt(
            engine: 'SauceNAO',
            region: region,
            error: '被限速（${e.message}）',
          ),
        );
        return const [];
      } on Exception catch (e) {
        attempts.add(
          ImageSearchAttempt(engine: 'SauceNAO', region: region, error: _message(e)),
        );
        return const [];
      }
    }
    return const [];
  }

  Future<List<ImageMatch>> _askIqdb(
    Uint8List bytes,
    String region,
    List<ImageSearchAttempt> attempts,
  ) async {
    try {
      final items = await iqdb.search(bytes);
      attempts.add(
        ImageSearchAttempt(engine: 'IQDB', region: region, count: items.length),
      );
      return items;
    } on Exception catch (e) {
      attempts.add(
        ImageSearchAttempt(engine: 'IQDB', region: region, error: _message(e)),
      );
      return const [];
    }
  }

  static double _bestSimilarity(List<ImageMatch> items) {
    var best = 0.0;
    for (final item in items) {
      if (item.similarity > best) best = item.similarity;
    }
    return best;
  }

  /// 合并两个站的结果：同一个来源页面只留相似度最高的那条
  static List<ImageMatch> mergeMatches(List<ImageMatch> items) {
    final byKey = <String, ImageMatch>{};
    for (final item in items) {
      final key = item.dedupeKey;
      final existing = byKey[key];
      if (existing == null || item.similarity > existing.similarity) {
        byKey[key] = item;
      }
    }
    final out = byKey.values.toList()
      ..sort((a, b) => b.similarity.compareTo(a.similarity));
    return out;
  }

  static String _message(Object error) {
    if (error is SourceException) return error.message;
    if (error is ImageSearchThrottled) return error.message;
    return error.toString();
  }
}
