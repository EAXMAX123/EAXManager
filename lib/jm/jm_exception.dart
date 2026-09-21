/// JM 异常分类，便于界面给出可读提示
library;

enum JmErrorKind {
  /// 网络不可达、超时
  network,

  /// 本子/章节不存在
  notFound,

  /// IP 地区受限、被风控
  restricted,

  /// 接口返回异常
  api,

  /// 未登录 / 登录失效
  unauthorized,
}

class JmException implements Exception {
  JmException(this.kind, this.message);

  factory JmException.network(String message) =>
      JmException(JmErrorKind.network, message);
  factory JmException.notFound(String message) =>
      JmException(JmErrorKind.notFound, message);
  factory JmException.restricted(String message) =>
      JmException(JmErrorKind.restricted, message);
  factory JmException.api(String message) =>
      JmException(JmErrorKind.api, message);
  factory JmException.unauthorized(String message) =>
      JmException(JmErrorKind.unauthorized, message);

  final JmErrorKind kind;
  final String message;

  /// 面向用户的中文提示
  String get friendlyMessage => switch (kind) {
    JmErrorKind.network => message.isEmpty ? '网络连接失败，请检查网络或代理设置' : message,
    JmErrorKind.notFound => message,
    JmErrorKind.restricted =>
      message.isEmpty ? '当前网络被限制访问，请更换线路或开启代理' : message,
    JmErrorKind.api => '接口异常：$message',
    JmErrorKind.unauthorized => message.isEmpty ? '登录已失效，请重新登录' : message,
  };

  @override
  String toString() => 'JmException(${kind.name}): $message';
}
