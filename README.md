# EAX管理器

一个 Android 漫画客户端：**搜索、看详情、下载到手机、本地书架、内置阅读器**。
支持四个来源 —— **JM（禁漫）/ 哔咔 / EH / Pixiv**，四个源的结果会汇总到同一个列表里，
下载下来的东西统一进本地书架，不区分来源。

> 本项目是纯客户端，不提供任何内容，也不托管任何图片。

## 版本

当前版本：**v1.3.0-beta**（`buildNumber` = 16）

版本号要改三处，保持一致：

1. `pubspec.yaml` → `version: 1.2.x+N`（N 每次 +1）
2. `lib/app_info.dart` → `version` / `buildNumber`
3. `android/app/src/main/AndroidManifest.xml` → `android:label`

出包产物按 `EAX管理器v<版本>.apk` 命名，旧版本保留不删，出问题可以回滚。

## 功能

### 搜索
- 一个搜索框搜全部：勾选要用的源（JM / 哔咔 / EH / Pixiv），一次拿到多家的结果
- JM 支持按 综合 / 作品 / 作者 / 标签 / 登场角色 检索
- 结果列表显示来源角标，能一眼看出哪条来自哪家

### 排行
- 一个页面看四家的榜单，第一行选源，下面两行跟着源变
- 时间档按源给：
  - JM：今日 / 本周 / 本月 / 全部时间
  - 哔咔：24小时 / 7天 / 30天
  - EH：昨日 / 本月 / 今年 / 全部时间
  - Pixiv：日榜 / 周榜 / 月榜
- 分类档也按源给（JM 有同人/单本/短篇/韩漫/美漫/3D/Cosplay/其他，Pixiv 有男性向/女性向/原创/新人/R18/AI）；
  哔咔和 EH 官方没有分类，这一行不显示
- 榜单里的作品和搜索出来的用法完全一样，能下载、能进书架、能加分类

### 收藏
- 顶部可切 JM / 哔咔，两边能同时登录，不用来回换账号
- 登录过一次之后会记住账号密码，会话掉了自动重登

### 识图
- 从相册选一张图，反查它出自哪一本：上传到 **SauceNAO** 和 **IQDB** 两个识图站，
  认出作品名、作者、出处后，点一下就能丢进四个源里搜
- 识图前自动裁掉四周的黑边 / 白边 / 状态栏，再等比缩放
- 整图认不出来时，自动切上中下三段再各搜一遍（可关）
- 识图设置就在识图页里：API key、相似度门槛、分段重搜、是否查 IQDB
- 另有「用 Google Lens 搜」：软件只负责把图片传上去，结果页交给浏览器打开
  （Lens 的结果页是纯 JS 渲染的，Dart 解析不出来；这一步需要梯子）
- 识图时图片会上传给上述第三方服务，页面上写明了这一点

> 试过但接不进来的：TinEye（国内直连不通）、Yandex（对国内 IP 返回「服务建设中」）、
> ascii2d（Cloudflare 验证挡在外面）、百度识图与 Bing 视觉搜索（都要网页里算出来的令牌）。

### 下载
- 整本下载 / 单章下载
- 下载管理页：暂停、继续、重试、删除，可看进度和速度
- 通知栏显示下载进度与完成提醒，下载期间启用前台服务保活
- 文件存到公共目录，文件管理器可见（目录可自定义，见下）

### 阅读
- 本地书架，显示每本下载进度，可按 创建顺序 / 文件大小 排序
- 内置阅读器：纵向滚动、双指缩放、进度记忆、上一话 / 下一话
- 音量键上下翻页（可在设置里关闭）

### 追更
- 订阅作品，后台定时检查新章节并推送通知
- 书架页「追更」标签可手动检查、取消订阅

### 设置
- 下载目录（**每个源可单独配**）、并发章节数、并发图片数、图片质量
- 代理地址、自定义 API 域名、重新探测线路
- 账号：JM / 哔咔 / EH / Pixiv 各自登录
- 音量键翻页、列表显示封面
- 主题模式、主题色、背景图（内置文件浏览器选择）
- 追更开关与检查间隔
- 通知权限、存储权限（「所有文件访问」）

### 关于
- 公告（每次更新的改动说明）、使用说明、赞助码与交流群

## 下载目录

默认放在公共存储下，按源分开：

```
内部存储/JM/<本子ID>/<章节号>/00001.jpg
内部存储/Pica/...
内部存储/EH/...
内部存储/Pixiv/...
```

每个源在「设置 → 下载」里都能单独改目录。目录下会写入 `.nomedia`，
避免漫画图片被系统相册扫进去。

首次使用建议先到「设置 → 存储权限」授予「所有文件访问」，
否则会退到应用私有目录，文件管理器不方便查看。

## 网络说明

四个源在国内的可达性差别很大，软件按下面策略处理：

| 源 | 是否需要梯子 | 是否需要登录 | 说明 |
| --- | --- | --- | --- |
| JM | 一般不需要 | 收藏夹需要 | 内置多条 API 线路，连不上会自动换 |
| 哔咔 | 需要（或加速器） | **搜索/榜单/收藏都需要登录** | 用**邮箱 + 密码**登录 |
| EH | **需要** | 不需要 | 站点是 SNI 阻断，不挂梯子连不通 |
| Pixiv | 不需要 | 不需要 | 数据与图片走公共镜像，内置多个备用地址 |

- JM / 哔咔 / EH 的域名在国内存在 DNS 污染，工程内置了 DoH 解析与 IP 直连兜底
  （`lib/net/`），但**代理开关是用户自己的事**，软件不会替你翻墙。
- 代理在「设置 → 代理地址」里填，支持 `http://` 与 `socks5://`。

## 更新机制

- App 联网后会去读仓库 `EAXMAX123/eam-update` 里的 `update.json`，比对版本号
- 发现新版本会提示，点「前往下载」时会先探一圈哪条线路能下
  （GitHub 的下载地址在国内常常直连不通，会自动挑一个能用的加速站再交给浏览器）
- 更新包**不会覆盖安装**，是让你手动装新包，旧版本 APK 一直留着

## 构建

需要 JDK 17 与 Flutter（本工程在 Flutter 3.47 / Dart 3.13 上开发）。

```bash
flutter pub get
flutter analyze
flutter test
flutter build apk --release
```

产物：`build/app/outputs/flutter-apk/app-release.apk`

### 关于签名

**目前所有发布版用的都是 debug 签名**（Flutter 默认行为）。
这意味着：

- 自己装来用完全没问题
- 但如果换一台机器重新出包，签名会不一样，**没法覆盖安装**，只能卸载重装
- 要做正式发布，需要在 `android/app/build.gradle.kts` 里配置自己的 keystore，
  并且把 `android/key.properties` 排除在版本控制之外（`.gitignore` 里已经排除了）

## 代码结构

```
lib/
  main.dart                入口
  app_info.dart            版本号、更新检查地址

  jm/                      纯 Dart 层，不依赖 Flutter，可单独跑测试
    jm_constants.dart        域名、密钥、分类/排序/时间映射、请求头
    jm_crypto.dart           token 签名、AES-256-ECB 响应解密
    jm_models.dart           数据模型（搜索项、本子、章节、收藏夹…）
    jm_exception.dart        异常分类与中文提示
    jm_client.dart           JM API 客户端：域名探测、搜索、详情、登录、收藏
    jm_scramble.dart         图片乱序还原算法
    jm_storage.dart          目录规划、图片列举、自然排序

  net/                     网络底层：DoH 解析、IP 直连、代理、错误归类
    doh_resolver.dart        DNS over HTTPS，绕开污染
    net_transport.dart       连接工厂（TLS / IP 直连 / 代理）
    net_ip_table.dart        IP 结果缓存
    net_error.dart           把底层异常翻译成人话

  source/                  四个来源的统一抽象
    image_search/            识图：SauceNAO / IQDB 客户端 + 图片预处理 + 编排
    comic_source.dart        统一接口：搜索 / 详情 / 章节 / 排行 / 收藏
    source_registry.dart     源注册表
    jm_source.dart           JM 适配
    chapter_downloader.dart  章节内并发下载 + 还原
    image_worker_pool.dart   图片处理线程池
    pica/                    哔咔适配（pica_client.dart / pica_source.dart）
    eh/                      EH 适配（eh_account / eh_client / eh_source）
    pixiv/                   Pixiv 适配（pixiv_client / pixiv_source）

  data/
    app_database.dart        sqflite：书架 / 下载任务 / 追更订阅 / 分类
    settings_store.dart      设置与账号的持久化
    app_docs.dart            公告与使用说明的文案

  services/
    local_library.dart       本地书架扫描与管理
    shelf_sizes.dart         书架体积统计
    notification_service.dart 通知栏（下载进度、完成、追更）
    platform_service.dart    与 Android 原生通信（音量键、前台服务、存储权限）
    subscription_service.dart 追更检查
    update_service.dart      版本检查与下载地址选路

  state/
    app_services.dart        全局服务容器（单例 AppServices.I）
    download_manager.dart    下载队列调度

  ui/
    app.dart                 MaterialApp + 底部导航
    theme.dart               主题与背景（**想改外观改这里**）
    pages/                   搜索 / 排行 / 收藏 / 识图 / 详情 / 阅读器 / 书架 / 下载 / 设置 / 关于
    widgets/                 封面组件、列表行、分类选择器、来源角标、文件浏览器

android/app/src/main/kotlin/com/jmreader/jm_reader/
  MainActivity.kt              音量键转发、前台服务与存储权限通道
  DownloadForegroundService.kt 下载期间保活

test/                        单元测试（纯 Dart 部分）
tool/                        开发期用的探针脚本（抓接口、验证线路），不参与打包
```

## 免责声明

- 本工程仅供**个人学习与技术交流**使用，不提供、不存储、不传播任何内容。
- 所有内容均来自第三方站点，版权归各自作者所有。请勿用于商业用途。
- 使用本软件产生的任何后果由使用者自行承担。
- 如果你是权利人且认为本项目不妥，请提 Issue，会及时处理。

## 许可证

[AGPL-3.0](LICENSE)

选择 AGPL-3.0 的原因：本工程的图片还原与加解密算法移植自 **jmcomic**（MIT），
产品形态参考了 **JM-Cosmos II**（AGPL-3.0），采用同一族许可证最省事。

如果你希望换成更宽松的 MIT，欢迎提 Issue 讨论。

## 致谢

见 [THANKS.md](THANKS.md)。
