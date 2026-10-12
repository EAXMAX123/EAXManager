import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../services/platform_service.dart';
import 'reward_code_dialog.dart';

/// 顶栏右上角那颗「求赞助」小胶囊。
///
/// 左边是软件图标里那只猫娘，点一下随机换一种神态，右边的文字跟着一起换。
///
/// 按的次数还有彩蛋：第 2 下弹赞赏码，第 5 下进彩蛋（见 [tapForReward] / [tapForEgg]）。
/// 素材全部来自本地 assets，不连网、不发请求。
class SponsorChip extends StatefulWidget {
  const SponsorChip({super.key});

  /// 按到第几下弹赞赏码
  static const int tapForReward = 2;

  /// 按到第几下放彩蛋
  static const int tapForEgg = 5;

  @override
  State<SponsorChip> createState() => _SponsorChipState();
}

/// 一种神态：歪头角度、缩放、贴纸，以及配的那句话
class _Mood {
  const _Mood({
    required this.text,
    required this.emoji,
    required this.tilt,
    required this.scale,
    required this.zoom,
    required this.align,
  });

  /// 胶囊上显示的话
  final String text;

  /// 猫娘身边的贴纸，空字符串表示不贴
  final String emoji;

  /// 歪头角度（弧度）
  final double tilt;

  /// 抖动缩放
  final double scale;

  /// 头像放大倍数，看起来像凑近 / 缩远
  final double zoom;

  /// 头像取景位置，配合 [zoom] 决定镜头对准脸的哪一块
  final Alignment align;
}

class _SponsorChipState extends State<SponsorChip>
    with SingleTickerProviderStateMixin {
  static const List<_Mood> _moods = [
    _Mood(
      text: '求赞助！',
      emoji: '',
      tilt: 0,
      scale: 1,
      zoom: 1,
      align: Alignment.center,
    ),
    _Mood(
      text: '给点吧～',
      emoji: '💰',
      tilt: -0.11,
      scale: 0.98,
      zoom: 1.06,
      align: Alignment(0, -0.06),
    ),
    _Mood(
      text: '不准按！',
      emoji: '💢',
      tilt: 0.12,
      scale: 1.06,
      zoom: 0.96,
      align: Alignment(0, 0.04),
    ),
    _Mood(
      text: '老板大气！',
      emoji: '✨',
      tilt: 0,
      scale: 1.04,
      zoom: 1.04,
      align: Alignment(-0.08, -0.05),
    ),
    _Mood(
      text: '谢谢你♪',
      emoji: '❤️',
      tilt: 0.07,
      scale: 1,
      zoom: 1.08,
      align: Alignment(0.06, -0.04),
    ),
  ];

  /// 头像外圈直径
  static const double _avatarSize = 24;

  final math.Random _random = math.Random();

  int _index = 0;

  /// 累计按了几下，放完彩蛋归零重新数
  int _taps = 0;

  /// 点一下放一次的「弹一下」，1 表示已经归位
  late final AnimationController _pop = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 360),
    value: 1,
  );

  bool _reducedMotion = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduced = MediaQuery.disableAnimationsOf(context);
    if (reduced == _reducedMotion) return;
    _reducedMotion = reduced;
    // 系统关了动画就停在归位状态，别留一个半截的形变
    if (reduced) _pop.value = 1;
  }

  @override
  void dispose() {
    _pop.dispose();
    super.dispose();
  }

  void _tap() {
    // 随机换一个，但不会连着两次都是同一个样子
    var next = _random.nextInt(_moods.length);
    if (next == _index) next = (next + 1) % _moods.length;
    setState(() => _index = next);
    if (!_reducedMotion) _pop.forward(from: 0);
    _countTaps();
  }

  /// 数按了几下：第 2 下弹赞赏码，第 5 下放彩蛋
  void _countTaps() {
    _taps++;
    if (_taps == SponsorChip.tapForReward) {
      showDialog<void>(
        context: context,
        builder: (_) => const RewardCodeDialog(),
      );
      return;
    }
    if (_taps >= SponsorChip.tapForEgg) {
      _taps = 0;
      _playEasterEgg();
    }
  }

  Future<void> _playEasterEgg() async {
    final played = await PlatformService.playEasterEggVideo();
    if (played || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('彩蛋要在手机上看哦'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final mood = _moods[_index];
    return Semantics(
      button: true,
      label: '${mood.text}，点一下换个样子',
      onTap: _tap,
      excludeSemantics: true,
      child: Tooltip(
        message: '点一下试试',
        child: InkWell(
          onTap: _tap,
          borderRadius: BorderRadius.circular(999),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.fromLTRB(2, 0, 10, 0),
            decoration: BoxDecoration(
              color: scheme.primaryContainer.withValues(alpha: 0.8),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: scheme.primary.withValues(alpha: 0.3)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _avatar(scheme, mood),
                const SizedBox(width: 6),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  transitionBuilder: (child, animation) => FadeTransition(
                    opacity: animation,
                    child: SizeTransition(
                      sizeFactor: animation,
                      axis: Axis.horizontal,
                      alignment: Alignment.centerLeft,
                      child: child,
                    ),
                  ),
                  child: Text(
                    mood.text,
                    key: ValueKey<String>(mood.text),
                    maxLines: 1,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: scheme.onPrimaryContainer,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _avatar(ColorScheme scheme, _Mood mood) {
    return SizedBox.square(
      dimension: _avatarSize,
      child: AnimatedBuilder(
        animation: _pop,
        builder: (context, _) {
          // 0 → 1 → 0 的一次弹跳
          final bump = _reducedMotion
              ? 0.0
              : math.sin(_pop.value * math.pi) * 0.22;
          return Transform.rotate(
            angle: mood.tilt,
            child: Transform.scale(
              scale: mood.scale * (1 + bump),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned.fill(
                    child: ClipOval(
                      child: ColoredBox(
                        color: scheme.primary.withValues(alpha: 0.14),
                        child: Transform.translate(
                          // 放大之后把镜头往 align 指的那一侧挪一点
                          offset: Offset(
                            -mood.align.x * _avatarSize * (mood.zoom - 1) / 2,
                            -mood.align.y * _avatarSize * (mood.zoom - 1) / 2,
                          ),
                          child: Transform.scale(
                            scale: mood.zoom,
                            child: Image.asset(
                              _faceAsset,
                              fit: BoxFit.contain,
                              filterQuality: FilterQuality.medium,
                              gaplessPlayback: true,
                              excludeFromSemantics: true,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (mood.emoji.isNotEmpty)
                    Positioned(
                      right: -1,
                      bottom: -1,
                      child: Text(
                        mood.emoji,
                        style: const TextStyle(fontSize: 10, height: 1),
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  /// 从软件图标裁出来的小头像——就是桌面图标上抱着 R18 那只猫娘
  static const String _faceAsset = 'assets/sponsor/mascot_face.png';
}
