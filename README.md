# EAX管理器

EAX管理器是一款 Flutter 编写的 Android 漫画搜索、下载与本地阅读工具，当前版本为 **v1.7.6（build 44）**。

## 功能

- 多源搜索：JM、哔咔、EH、Pixiv、Rule34、SankakuBlack
- 多源排行与推荐
- 作品详情、章节下载、下载队列与通知栏进度
- 本地书架、自定义分类、排序、追更
- 纵向阅读、双指缩放、音量键翻页、阅读进度保存
- 本地章节打包成 PDF 分享，可选打开密码；已打包文件长期缓存，可在书架「已打包」页管理
- JM / 哔咔 / EH 账号登录与收藏
- 图片识图反查
- 浅色 / 深色主题、自定义背景
- Windows 桌面端支持

## 构建

环境要求：

- Flutter 3.41 或兼容版本
- Dart 3.13.4 或更高版本
- Android SDK

```bash
flutter pub get
flutter analyze
flutter test
flutter build apk --release
```

Windows 桌面端：

```bash
flutter build windows --release
```

## 目录

- `lib/`：应用源码
- `assets/`：图标、导航素材与群二维码
- `android/`：Android 原生工程
- `windows/`：Windows 原生工程
- `test/`：测试

## 说明

请仅将本项目用于学习与个人用途，并遵守所在地法律法规及内容来源网站的使用条款。
