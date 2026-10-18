/// JM 站点常量：域名、密钥、分类映射、请求头
/// 全部来自 jmcomic 2.7.7 (src/jmcomic/jm_config.py)，保持与上游一致。
library;

class JmMagic {
  JmMagic._();

  // ===== 图片切割算法分界值 =====
  static const int scramble220980 = 220980;
  static const int scramble268850 = 268850;
  static const int scramble421926 = 421926;

  // ===== 移动端 API 密钥 =====
  static const String appTokenSecret = '185Hcomic3PAPP7R';
  static const String appTokenSecret2 = '18comicAPPContent';
  static const String appDataSecret = '185Hcomic3PAPP7R';
  static const String apiDomainServerSecret = 'diosfjckwpqpdfjkvnqQjsik';
  static const String appVersion = '2.1.7';

  // ===== 排序 =====
  static const String orderLatest = 'mr';
  static const String orderView = 'mv';
  static const String orderPicture = 'mp';
  static const String orderLike = 'tf';
  static const String orderScore = 'tr';
  static const String orderComment = 'md';

  // ===== 时间段 =====
  static const String timeToday = 't';
  static const String timeWeek = 'w';
  static const String timeMonth = 'm';
  static const String timeAll = 'a';

  // ===== 分类 =====
  static const String categoryAll = '0';
  static const String categoryDoujin = 'doujin';
  static const String categorySingle = 'single';
  static const String categoryShort = 'short';
  static const String categoryAnother = 'another';
  static const String categoryHanman = 'hanman';
  static const String categoryMeiman = 'meiman';
  static const String categoryDoujinCosplay = 'doujin_cosplay';
  static const String category3d = '3D';
}

class JmDomains {
  JmDomains._();

  /// 移动端图片 CDN 域名（API 客户端随机选一个）
  static const List<String> imageList = [
    'cdn-msp.jmapiproxy1.cc',
    'cdn-msp.jmapiproxy2.cc',
    'cdn-msp2.jmapiproxy2.cc',
    'cdn-msp3.jmapiproxy2.cc',
    'cdn-msp.jmapinodeudzn.net',
    'cdn-msp3.jmapinodeudzn.net',
  ];

  /// 移动端 API 域名
  static const List<String> apiList = [
    'www.cdnhjk.net',
    'www.cdngwc.cc',
    'www.cdngwc.net',
    'www.cdngwc.club',
    'www.cdnutc.me',
  ];

  /// 获取最新 API 域名的地址（返回内容为 AES 加密文本）
  static const List<String> apiDomainServerList = [
    'https://rup4a04-c01.tos-ap-southeast-1.bytepluses.com/newsvr-2025.txt',
    'https://rup4a04-c02.tos-cn-hongkong.bytepluses.com/newsvr-2025.txt',
    'https://rup4a04-c03.tos-cn-beijing.bytepluses.com.cn/newsvr-2025.txt',
  ];

  /// 网页端候选域名（API 不可用时兜底）
  static const List<String> htmlList = [
    '18comic.vip',
    '18comic.org',
    '18comic.cc',
    'jmcomic.me',
  ];

  /// 永久域名发布页
  static const String pubUrl = 'https://jmcomicgo.org';
}

class JmHeaders {
  JmHeaders._();

  static const String appUserAgent =
      'Mozilla/5.0 (Linux; Android 9; V1938CT Build/PQ3A.190705.11211812; wv) '
      'AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/91.0.4472.114 '
      'Safari/537.36';

  /// 移动端 API 通用请求头
  static const Map<String, String> appTemplate = {
    'Accept-Encoding': 'gzip, deflate',
    'user-agent': appUserAgent,
  };

  /// 移动端图片请求头
  static Map<String, String> appImage() => {
    'Accept':
        'image/avif,image/webp,image/apng,image/svg+xml,image/*,*/*;q=0.8',
    'X-Requested-With': 'com.JMComic3.app',
    'Referer': 'https://${JmDomains.apiList[0]}',
    'Accept-Language': 'zh-CN,zh;q=0.9,en-US;q=0.8,en;q=0.7',
  };

  /// 网页端请求头
  static Map<String, String> html(String referer) => {
    'accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8',
    'accept-language': 'zh-CN,zh;q=0.9',
    'cache-control': 'no-cache',
    'pragma': 'no-cache',
    'referer': referer,
    'upgrade-insecure-requests': '1',
    'user-agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
  };
}

/// 分类：用户可见名称 -> API 参数
const Map<String, String> jmCategoryMap = {
  'all': JmMagic.categoryAll,
  'doujin': JmMagic.categoryDoujin,
  'single': JmMagic.categorySingle,
  'short': JmMagic.categoryShort,
  'hanman': JmMagic.categoryHanman,
  'meiman': JmMagic.categoryMeiman,
  '3d': JmMagic.category3d,
  'cosplay': JmMagic.categoryDoujinCosplay,
  'another': JmMagic.categoryAnother,
};

const Map<String, String> jmCategoryNames = {
  '0': '全部',
  'doujin': '同人',
  'single': '单本',
  'short': '短篇',
  'hanman': '韩漫',
  'meiman': '美漫',
  '3D': '3D',
  'doujin_cosplay': 'Cosplay',
  'another': '其他',
};

/// 排序：用户输入 -> API 参数
const Map<String, String> jmOrderMap = {
  'new': JmMagic.orderLatest,
  'hot': JmMagic.orderView,
  'pic': JmMagic.orderPicture,
  'like': JmMagic.orderLike,
};

const Map<String, String> jmOrderNames = {
  'mr': '最新',
  'mv': '热门',
  'mp': '图多',
  'tf': '点赞',
};

/// 时间段：用户输入 -> API 参数
const Map<String, String> jmTimeMap = {
  'day': JmMagic.timeToday,
  'week': JmMagic.timeWeek,
  'month': JmMagic.timeMonth,
  'all': JmMagic.timeAll,
};

const Map<String, String> jmTimeNames = {
  't': '今日',
  'w': '本周',
  'm': '本月',
  'a': '全部时间',
};

/// 搜索模式 -> main_tag
const Map<String, int> jmSearchMainTag = {
  'site': 0,
  'work': 1,
  'author': 2,
  'tag': 3,
  'actor': 4,
};

const Map<String, String> jmSearchModeNames = {
  'site': '综合',
  'work': '作品',
  'author': '作者',
  'tag': '标签',
  'actor': '登场角色',
};
