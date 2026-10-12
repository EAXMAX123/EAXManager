"""从软件图标里裁出顶栏「求赞助」胶囊用的小头像。

顶栏那颗胶囊要跟手机桌面上的图标长得一样，所以素材直接用
`assets/app_icon.png`（猫娘抱着 R18 那本），而不是导航栏那套头像——
那套是另一版画风，跟图标不是同一个角色。

图标本身就是「透明底 + 一个圆形构图」，这里只要：

1. 按圆形的外沿裁成正方形；
2. 缩到 256px 给顶栏用。

用法：
    python tool/prepare_sponsor_assets.py
"""

from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'assets/app_icon.png'
TARGET = ROOT / 'assets/sponsor/mascot_face.png'

# 512x512 的图标里，猫娘那个圆大约占 x 18..494 / y 31..503
CROP = (18, 29, 494, 505)

SIZE = 256


def main() -> None:
    image = Image.open(SOURCE).convert('RGBA').crop(CROP)

    TARGET.parent.mkdir(parents=True, exist_ok=True)
    image.resize((SIZE, SIZE), Image.Resampling.LANCZOS).save(
        TARGET, optimize=True
    )
    print(f'{TARGET.relative_to(ROOT)}  {TARGET.stat().st_size} bytes')


if __name__ == '__main__':
    main()
