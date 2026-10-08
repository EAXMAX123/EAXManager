import argparse
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter


def save_png(image, path):
    path.parent.mkdir(parents=True, exist_ok=True)
    image.save(path, optimize=True)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('launcher', type=Path)
    parser.add_argument('navigation', type=Path)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    launcher = Image.open(args.launcher).convert('RGBA')
    launcher = launcher.resize((1254, 1254), Image.Resampling.LANCZOS)
    portrait = launcher
    save_png(portrait.resize((512, 512), Image.Resampling.LANCZOS),
             root / 'assets/app_icon.png')
    resources = root / 'android/app/src/main/res'
    for density, size in [('mdpi', 48), ('hdpi', 72), ('xhdpi', 96),
                          ('xxhdpi', 144), ('xxxhdpi', 192)]:
        save_png(portrait.resize((size, size), Image.Resampling.LANCZOS),
                 resources / f'mipmap-{density}/ic_launcher.png')
    adaptive = Image.new('RGBA', (432, 432), '#eee9fa')
    adaptive.alpha_composite(portrait.resize((264, 264), Image.Resampling.LANCZOS), (84, 84))
    save_png(adaptive,
             resources / 'drawable-nodpi/ic_launcher_art.png')

    reference = Image.open(args.navigation).convert('RGBA')
    reference = reference.resize((2048, 683), Image.Resampling.LANCZOS)
    head_mask = Image.new('L', reference.size)
    head_draw = ImageDraw.Draw(head_mask)
    head_draw.polygon([
        (549, 143), (574, 142), (601, 133), (648, 133), (682, 143),
        (705, 155), (720, 184), (734, 207), (774, 227), (767, 251),
        (748, 266), (746, 304), (755, 344), (740, 367), (732, 359),
        (736, 346), (730, 333), (739, 329), (724, 307), (684, 306),
        (602, 306), (588, 337), (578, 379),
        (555, 372), (532, 353), (534, 317), (518, 313), (530, 285),
        (529, 253), (539, 218), (538, 170),
    ], fill=255)
    head = reference.copy()
    head.putalpha(head_mask.filter(ImageFilter.GaussianBlur(0.5)))
    head = head.crop((474, 102, 798, 426)).resize((448, 448), Image.Resampling.LANCZOS)
    save_png(head, root / 'assets/navigation/mascot_head.png')
    regions = [
        ('discover', (225, 264), [(85, 126, 365, 398)]),
        ('library', (636, 264), [(498, 128, 774, 398), (490, 234, 528, 280)]),
        ('downloads', (1027, 264), [(888, 127, 1165, 399)]),
        ('settings', (1427, 264), [(1284, 126, 1560, 399), (1503, 195, 1571, 259)]),
        ('about', (1845, 264), [(1697, 128, 1973, 399), (1899, 220, 1994, 311)]),
    ]
    stickers = []
    for name, center, ellipses in regions:
        mask = Image.new('L', reference.size)
        draw = ImageDraw.Draw(mask)
        for ellipse in ellipses:
            draw.ellipse(ellipse, fill=255)
        mask = mask.filter(ImageFilter.GaussianBlur(0.6))
        sticker = reference.copy()
        sticker.putalpha(mask)
        center_x, center_y = center
        sticker = sticker.crop((center_x - 162, center_y - 162,
                                center_x + 162, center_y + 162))
        sticker = sticker.resize((224, 224), Image.Resampling.LANCZOS)
        save_png(sticker, root / f'assets/navigation/{name}.png')
        stickers.append(sticker)

    preview = Image.new('RGBA', (1120, 560), '#faf8ff')
    draw = ImageDraw.Draw(preview)
    draw.rectangle((0, 280, 1120, 560), fill='#191923')
    for index, sticker in enumerate(stickers):
        preview.alpha_composite(sticker, (index * 224, 20))
        preview.alpha_composite(sticker, (index * 224, 300))
    save_png(preview, root / 'build/mascot-assets-preview.png')


if __name__ == '__main__':
    main()
