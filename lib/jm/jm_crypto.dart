/// 禁漫加解密逻辑，对应 jmcomic 的 JmCryptoTool
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:pointycastle/export.dart';

import 'jm_constants.dart';

class JmCrypto {
  JmCrypto._();

  /// md5 十六进制小写字符串
  static String md5Hex(String input) =>
      md5.convert(utf8.encode(input)).toString();

  /// 当前秒级时间戳（字符串）
  static String timeStamp() =>
      (DateTime.now().millisecondsSinceEpoch ~/ 1000).toString();

  /// 计算请求头所需的 token / tokenparam
  ///
  /// token = md5(ts + secret)
  /// tokenparam = "ts,appVersion"
  static (String token, String tokenparam) tokenAndTokenParam(
    String ts, {
    String secret = JmMagic.appTokenSecret,
    String ver = JmMagic.appVersion,
  }) {
    return (md5Hex('$ts$secret'), '$ts,$ver');
  }

  /// 解密移动端接口返回值
  ///
  /// 1. base64 解码
  /// 2. AES-256-ECB 解密（key = md5(ts + secret) 的 UTF-8 字节）
  /// 3. 去掉 PKCS7 padding
  static String decodeRespData(
    String data,
    String ts, {
    String secret = JmMagic.appDataSecret,
  }) {
    final key = Uint8List.fromList(utf8.encode(md5Hex('$ts$secret')));
    final cipherBytes = base64.decode(data.trim());

    final cipher = ECBBlockCipher(AESEngine())..init(false, KeyParameter(key));

    final out = Uint8List(cipherBytes.length);
    for (var offset = 0; offset < cipherBytes.length; offset += 16) {
      cipher.processBlock(cipherBytes, offset, out, offset);
    }

    var end = out.length;
    if (end > 0) {
      final pad = out[end - 1];
      if (pad >= 1 && pad <= 16 && pad <= end) {
        end -= pad;
      }
    }

    return utf8.decode(out.sublist(0, end), allowMalformed: true);
  }
}
