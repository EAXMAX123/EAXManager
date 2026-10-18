/// EH 账号：只存浏览器 Cookie 里的三个关键字段
///
/// EH 没有可用的账号密码登录接口（登录要走论坛的复杂表单 + 验证码），
/// 第三方客户端一律用「从浏览器复制 Cookie」的方式，这里也一样。
///
/// 需要三个值：
///   ipb_member_id  用户 ID
///   ipb_pass_hash  密码哈希
///   igneous        只有 ExHentai 才需要，没有它就只能用 e-hentai
library;

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class EhAccount {
  const EhAccount({
    this.memberId = '',
    this.passHash = '',
    this.igneous = '',
    this.useEx = false,
  });

  final String memberId;
  final String passHash;
  final String igneous;

  /// 是否走 ExHentai（需要 igneous）
  final bool useEx;

  bool get hasLogin => memberId.isNotEmpty && passHash.isNotEmpty;

  /// 能拼成 ExHentai 需要的完整凭据
  bool get canUseEx => hasLogin && igneous.isNotEmpty;

  String get baseUrl =>
      (useEx && canUseEx) ? 'https://exhentai.org' : 'https://e-hentai.org';

  String get cookieHeader {
    final parts = <String>[
      if (memberId.isNotEmpty) 'ipb_member_id=$memberId',
      if (passHash.isNotEmpty) 'ipb_pass_hash=$passHash',
      if (igneous.isNotEmpty) 'igneous=$igneous',
    ];
    return parts.join('; ');
  }

  EhAccount copyWith({
    String? memberId,
    String? passHash,
    String? igneous,
    bool? useEx,
  }) => EhAccount(
    memberId: memberId ?? this.memberId,
    passHash: passHash ?? this.passHash,
    igneous: igneous ?? this.igneous,
    useEx: useEx ?? this.useEx,
  );

  /// 从用户粘贴的一大串 Cookie 里挑出需要的字段
  ///
  /// 浏览器里复制出来的通常是 `a=1; b=2; ipb_member_id=123; ...` 这种形式，
  /// 也可能是 `ipb_member_id=123&ipb_pass_hash=abc`，两种都认。
  static EhAccount parsePasted(String raw, {bool useEx = false}) {
    final text = raw.trim();
    if (text.isEmpty) return EhAccount(useEx: useEx);

    final map = <String, String>{};
    // 浏览器复制出来是分号分隔，有些工具给的是 & 分隔，两种都认
    for (final chunk in text.split(RegExp(r'[;\n&]'))) {
      final pair = chunk.trim().split('=');
      if (pair.length < 2) continue;
      final key = pair.first.trim();
      final value = pair.sublist(1).join('=').trim();
      if (key.isEmpty || value.isEmpty) continue;
      map[key] = value;
    }

    return EhAccount(
      memberId: map['ipb_member_id'] ?? '',
      passHash: map['ipb_pass_hash'] ?? '',
      igneous: map['igneous'] ?? '',
      useEx: useEx,
    );
  }

  Map<String, Object?> toJson() => {
    'memberId': memberId,
    'passHash': passHash,
    'igneous': igneous,
    'useEx': useEx,
  };

  factory EhAccount.fromJson(Map<String, dynamic> json) => EhAccount(
    memberId: json['memberId'] as String? ?? '',
    passHash: json['passHash'] as String? ?? '',
    igneous: json['igneous'] as String? ?? '',
    useEx: json['useEx'] as bool? ?? false,
  );
}

class EhAccountStore {
  EhAccountStore._();

  static const String _key = 'eh_account';

  static Future<EhAccount?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return null;
    try {
      final json = jsonDecode(raw);
      if (json is Map<String, dynamic>) return EhAccount.fromJson(json);
    } on FormatException {
      // 数据损坏时当作未登录
    }
    return null;
  }

  static Future<void> save(EhAccount account) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(account.toJson()));
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
