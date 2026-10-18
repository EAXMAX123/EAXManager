/// 把底层网络异常翻译成用户看得懂、且能自己处理的话
///
/// 之前这里直接把 DioException 原文抛给用户，长这样：
///   JmException(network):DioException [connection error]: The connection errored:
///   … This indicates an error which most likely cannot be solved by the library.
/// 用户看完不知道能做什么。现在按原因分类，每类给一句具体建议。
library;

import 'dart:io';

import 'package:dio/dio.dart';

enum NetFault {
  /// DNS 被污染，解析到假 IP
  dnsPoisoned,

  /// 线路被重置 / 阻断
  blocked,

  /// 连不上，或超时
  timeout,

  /// 代理本身没起来或填错了
  proxyDown,

  /// 证书不对（多半也是污染或中间人）
  certificate,

  /// 服务器返回了错误状态
  server,

  unknown,
}

class NetErrorInfo {
  const NetErrorInfo({
    required this.fault,
    required this.title,
    required this.advice,
    this.detail = '',
  });

  final NetFault fault;

  /// 一句话结论
  final String title;

  /// 建议怎么做
  final String advice;

  /// 底层原文，放在折叠区给需要排查的人看
  final String detail;

  String get message => advice.isEmpty ? title : '$title，$advice';

  @override
  String toString() => message;
}

/// 候选地址全试过了，还是没连上
///
/// 用专门的类型是为了让上层能一眼认出「这是彻底连不上」，
/// 而不是去猜 SocketException 的文案。
class NetUnreachableException implements Exception {
  const NetUnreachableException(this.host, {this.attempts = 0});

  final String host;

  /// 一共试了几个地址
  final int attempts;

  @override
  String toString() => 'NetUnreachableException: $host 连不上（试了 $attempts 个地址）';
}

class NetError {
  NetError._();

  /// 所有候选线路都试过了还是连不上
  ///
  /// 底层抛这个类型而不是一串裸的 SocketException 文案，界面才能给出
  /// 「换个网络或开代理」这种具体建议，而不是甩一段英文原文给用户。
  static NetErrorInfo unreachable(
    String sourceName, {
    bool proxyConfigured = false,
    bool vpnActive = false,
    String detail = '',
  }) => NetErrorInfo(
    fault: NetFault.blocked,
    title: '$sourceName 的线路全都连不上',
    advice: _unreachableAdvice(sourceName, proxyConfigured, vpnActive),
    detail: detail,
  );

  static String _unreachableAdvice(
    String sourceName,
    bool proxyConfigured,
    bool vpnActive,
  ) {
    if (proxyConfigured) return '代理开着还是不通，换个节点再试一次';
    if (vpnActive) return '梯子开着还是不通，换个节点再试一次';
    return '先换个网络（流量 / 别的 Wi-Fi）试试。一直不行就是当前网络把 '
        '$sourceName 屏蔽了，需要开代理或加速器';
  }

  /// [sourceName] 是展示名，如「JM」「哔咔」；[proxyConfigured] 表示用户填了代理
  static NetErrorInfo describe(
    Object error, {
    required String sourceName,
    bool proxyConfigured = false,
    bool vpnActive = false,
  }) {
    if (error is NetErrorInfo) return error;

    final raw = error.toString();

    // 彻底连不上（所有候选地址都失败）：直接给结论，别按文案猜
    final unreachable = _findUnreachable(error);
    if (unreachable != null) {
      return NetError.unreachable(
        sourceName,
        proxyConfigured: proxyConfigured,
        vpnActive: vpnActive,
        detail: raw,
      );
    }

    final socket = _findSocketException(error);
    final socketText = socket?.toString() ?? '';
    final lower = '$raw $socketText'.toLowerCase();

    // 代理填了但连不上代理本身
    if (proxyConfigured &&
        (lower.contains('connection refused') ||
            lower.contains('errno = 111') ||
            lower.contains('errno = 10061'))) {
      return NetErrorInfo(
        fault: NetFault.proxyDown,
        title: '$sourceName 连不上代理',
        advice: '检查代理软件是否在运行，端口号是否和设置里填的一致',
        detail: raw,
      );
    }

    if (error is DioException &&
        error.type == DioExceptionType.badCertificate) {
      return NetErrorInfo(
        fault: NetFault.certificate,
        title: '$sourceName 的证书校验没通过',
        advice: '多半是连到了假线路。重试一次，还不行就在设置里打开「强制使用真实 IP」',
        detail: raw,
      );
    }

    final hasHandshake =
        lower.contains('handshakeexception') ||
        lower.contains('certificate') ||
        lower.contains('tlsv1') ||
        lower.contains('wrong version number');
    if (hasHandshake) {
      return NetErrorInfo(
        fault: NetFault.certificate,
        title: '$sourceName 的连接被中途干扰了',
        advice: '重试一次；EH 这类站点则必须挂梯子',
        detail: raw,
      );
    }

    final isReset =
        lower.contains('connection reset') ||
        lower.contains('errno = 104') ||
        lower.contains('errno = 10054') ||
        lower.contains('connection closed') ||
        lower.contains('broken pipe');
    if (isReset) {
      return NetErrorInfo(
        fault: NetFault.blocked,
        title: '$sourceName 这条线路被掐断了',
        advice: '重试一次；反复失败就在设置里打开「强制使用真实 IP」',
        detail: raw,
      );
    }

    final isLookup =
        lower.contains('failed host lookup') ||
        lower.contains('nodename nor servname') ||
        lower.contains('name or service not known') ||
        lower.contains('no address associated');
    if (isLookup) {
      return NetErrorInfo(
        fault: NetFault.dnsPoisoned,
        title: '$sourceName 的域名解析失败了',
        advice: '重试一次；还不行就在设置里打开「强制使用真实 IP」，它会改用加密 DNS 拿真实地址',
        detail: raw,
      );
    }

    final isTimeout = error is DioException
        ? error.type == DioExceptionType.connectionTimeout ||
              error.type == DioExceptionType.sendTimeout ||
              error.type == DioExceptionType.receiveTimeout ||
              error.type == DioExceptionType.connectionError
        : lower.contains('timed out') || lower.contains('timeout');
    if (isTimeout) {
      return NetErrorInfo(
        fault: NetFault.timeout,
        title: '$sourceName 连接超时',
        advice: vpnActive
            ? '已经挂着梯子还超时，试试在设置里换个节点或换条线路'
            : '先检查网络。如果只有这个站点连不上，重试一次，或在设置里打开「强制使用真实 IP」',
        detail: raw,
      );
    }

    return NetErrorInfo(
      fault: NetFault.unknown,
      title: '$sourceName 网络异常',
      advice: '稍后重试，或在设置里重新探测线路',
      detail: raw,
    );
  }

  static SocketException? _findSocketException(Object error) {
    if (error is SocketException) return error;
    if (error is DioException) {
      final inner = error.error;
      if (inner is SocketException) return inner;
      if (inner is HttpException) return null;
    }
    return null;
  }

  static NetUnreachableException? _findUnreachable(Object error) {
    if (error is NetUnreachableException) return error;
    if (error is DioException) {
      final inner = error.error;
      if (inner is NetUnreachableException) return inner;
    }
    return null;
  }
}
