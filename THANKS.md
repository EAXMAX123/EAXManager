# 致谢

EAX管理器 的实现离不开下面这些开源项目。这里按用途列清楚，也说明各自对本工程的影响范围。

## 算法与协议参考

### jmcomic（JMComic-Crawler-Python）

- 项目：https://github.com/hect0x7/JMComic-Crawler-Python
- 许可证：MIT
- 影响范围：**有代码移植**。本工程 `lib/jm/` 下的以下部分是对它的 Dart 移植，
  保留了原有算法逻辑与常量，版权归其作者所有：
  - `jm_constants.dart` —— 移动端 API 密钥、域名列表、分类/排序/时间映射（对应 `jm_config.py`）
  - `jm_crypto.dart` —— token 签名、AES-256-ECB 响应解密（对应 `JmCryptoTool`）
  - `jm_scramble.dart` —— 图片乱序还原（对应 `JmImageTool.get_num` / `decode_and_save`）

  按 MIT 许可证要求，上述移植部分的原始版权声明与许可声明一并保留。

### JM-Cosmos II（AstrBot 插件）

- 许可证：AGPL-3.0
- 影响范围：**仅功能参考，无代码移植**。本工程的页面组织、下载流程、追更订阅等
  产品形态参考了它的功能设计，但没有复制其任何代码。

### astrbot_plugin_pica

- 项目：https://github.com/huashuiyue07/astrbot_plugin_pica
- 许可证：MIT
- 影响范围：**接口参考**。哔咔（PicACG）的 API 签名方式、请求头构造与登录流程
  参考了该项目，未直接复制代码。

## 站点接口参考

- **EhViewer / keiyoushi/extensions-source** —— EH 的 `toplist.php` 榜单参数、
  哔咔 `comics/leaderboard` 的 `tt` / `ct` 取值参考了这些开源实现的抓包结论。
- **Pixiv 公共镜像** —— Pixiv 的数据与图片走的是社区公共反代服务，
  不隶属于本项目，随时可能失效；本工程内置了多个备选地址并会自动切换。

## 依赖库

界面与网络层建立在 Flutter 生态之上，主要依赖见 `pubspec.yaml`：
`dio`、`dio_cookie_manager`、`cookie_jar`、`html`、`sqflite`、`path_provider`、
`flutter_local_notifications`、`crypto`、`pointycastle`、`cached_network_image`、
`shared_preferences`、`image`。
