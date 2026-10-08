import argparse
from collections import deque
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont

MINT = np.array([203, 236, 214])

# 「R18」小贴纸：贴在手捧书页的左页上。
#
# 位置刻意不用绝对像素，而是拿薄荷绿圆牌的圆心和直径当基准换算成比例，
# 这样换源图、换格子、改图标尺寸都不用重新量，贴纸会跟着书一起缩小放大。
R18_BOX = (-0.1931, 0.2854, -0.0258, 0.3712)
R18_TEXT = 0.0665
R18_OUTLINE = 0.00858
R18_ANGLE = -5
R18_FILL = (214, 48, 48, 255)
R18_EDGE = (255, 255, 255, 240)
R18_FONTS = (
    'C:/Windows/Fonts/msyhbd.ttc',
    'C:/Windows/Fonts/arialbd.ttf',
    '/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf',
)

TARGETS = (
    ('assets/app_icon.png', 512, 466),
    ('android/app/src/main/res/drawable-nodpi/ic_launcher_art.png', 432, 320),
    ('android/app/src/main/res/mipmap-mdpi/ic_launcher.png', 48, 44),
    ('android/app/src/main/res/mipmap-hdpi/ic_launcher.png', 72, 66),
    ('android/app/src/main/res/mipmap-xhdpi/ic_launcher.png', 96, 87),
    ('android/app/src/main/res/mipmap-xxhdpi/ic_launcher.png', 144, 131),
    ('android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png', 192, 175),
)


def labeled_components(mask):
    height, width = mask.shape
    labels = np.zeros((height, width), dtype=np.int32)
    components = []
    for row in range(height):
        for column in range(width):
            if not mask[row, column] or labels[row, column]:
                continue
            index = len(components) + 1
            pending = deque([(row, column)])
            labels[row, column] = index
            pixels = []
            while pending:
                current_row, current_column = pending.popleft()
                pixels.append((current_row, current_column))
                neighbors = (
                    (current_row - 1, current_column),
                    (current_row + 1, current_column),
                    (current_row, current_column - 1),
                    (current_row, current_column + 1),
                )
                for neighbor_row, neighbor_column in neighbors:
                    inside = (
                        0 <= neighbor_row < height
                        and 0 <= neighbor_column < width
                    )
                    if (
                        inside
                        and mask[neighbor_row, neighbor_column]
                        and not labels[neighbor_row, neighbor_column]
                    ):
                        labels[neighbor_row, neighbor_column] = index
                        pending.append((neighbor_row, neighbor_column))
            components.append(pixels)
    return labels, components


def dilate(mask, radius):
    grown = mask.copy()
    for _ in range(radius):
        shifted = grown.copy()
        shifted[1:, :] |= grown[:-1, :]
        shifted[:-1, :] |= grown[1:, :]
        shifted[:, 1:] |= grown[:, :-1]
        shifted[:, :-1] |= grown[:, 1:]
        grown = shifted
    return grown


def extract_sticker(cell):
    array = np.array(cell)
    alpha = array[:, :, 3]
    mask = alpha >= 24
    labels, components = labeled_components(mask)
    sticker = max(components, key=len)
    component_mask = np.zeros_like(mask)
    rows = np.array([pixel[0] for pixel in sticker])
    columns = np.array([pixel[1] for pixel in sticker])
    component_mask[rows, columns] = True

    badge_mask = (
        component_mask
        & (np.abs(array[:, :, :3] - MINT).sum(axis=2) < 90)
        & (alpha > 200)
    )
    badge_rows, badge_columns = np.where(badge_mask)
    if not len(badge_rows):
        raise ValueError('No mint badge found in the source cell')
    badge_center_x = (badge_columns.max() + badge_columns.min()) / 2
    badge_center_y = (badge_rows.max() + badge_rows.min()) / 2
    badge_diameter = max(
        badge_columns.max() - badge_columns.min() + 1,
        badge_rows.max() - badge_rows.min() + 1,
    )

    extract = dilate(component_mask, 2) & (alpha > 8)
    cleaned = array.copy()
    cleaned[~extract] = 0
    extract_rows, extract_columns = np.where(extract)
    crop_x0 = extract_columns.min()
    crop_y0 = extract_rows.min()
    crop = Image.fromarray(
        cleaned[
            crop_y0:extract_rows.max() + 1,
            crop_x0:extract_columns.max() + 1,
        ],
        'RGBA',
    )
    return crop, badge_center_x - crop_x0, badge_center_y - crop_y0, float(badge_diameter)


def render_badge(sticker, center_x, center_y, badge_diameter, canvas, target_diameter):
    scale = target_diameter / badge_diameter
    scaled = sticker.resize(
        (round(sticker.width * scale), round(sticker.height * scale)),
        Image.Resampling.LANCZOS,
    )
    pad = 96
    layer = Image.new('RGBA', (canvas + pad * 2, canvas + pad * 2))
    layer.alpha_composite(
        scaled,
        (
            round(pad + canvas / 2 - center_x * scale),
            round(pad + canvas / 2 - center_y * scale),
        ),
    )
    return layer.crop((pad, pad, pad + canvas, pad + canvas))


def mock_background(size, circle, color='#101014'):
    layer = Image.new('RGBA', (size, size))
    draw = ImageDraw.Draw(layer)
    if circle:
        draw.ellipse((0, 0, size - 1, size - 1), fill=color)
    else:
        draw.rounded_rectangle((0, 0, size - 1, size - 1), radius=round(size * 0.25), fill=color)
    return layer


def load_r18_font(pixel_size):
    for candidate in R18_FONTS:
        if Path(candidate).exists():
            return ImageFont.truetype(candidate, pixel_size)
    raise FileNotFoundError(f'No bold font found among {R18_FONTS}')


def draw_r18_mark(sticker, center_x, center_y, badge_diameter):
    x0 = center_x + R18_BOX[0] * badge_diameter
    y0 = center_y + R18_BOX[1] * badge_diameter
    x1 = center_x + R18_BOX[2] * badge_diameter
    y1 = center_y + R18_BOX[3] * badge_diameter
    width = round(x1 - x0)
    height = round(y1 - y0)
    outline = max(1, round(R18_OUTLINE * badge_diameter))
    font = load_r18_font(max(6, round(R18_TEXT * badge_diameter)))

    pad = outline * 6
    plate = Image.new('RGBA', (width + pad * 2, height + pad * 2), (0, 0, 0, 0))
    draw = ImageDraw.Draw(plate)
    draw.rounded_rectangle(
        (pad, pad, pad + width, pad + height),
        radius=round(min(width, height) * 0.26),
        fill=R18_FILL,
        outline=R18_EDGE,
        width=outline,
    )
    box = draw.textbbox((0, 0), 'R18', font=font)
    draw.text(
        (
            pad + width / 2 - (box[2] - box[0]) / 2 - box[0],
            pad + height / 2 - (box[3] - box[1]) / 2 - box[1],
        ),
        'R18',
        font=font,
        fill=(255, 255, 255, 255),
    )
    plate = plate.rotate(
        R18_ANGLE,
        resample=Image.Resampling.BICUBIC,
        expand=True,
        center=(pad + width / 2, pad + height / 2),
    )

    marked = sticker.copy()
    marked.alpha_composite(
        plate,
        (
            round(x0) - pad - (plate.width - width - pad * 2) // 2,
            round(y0) - pad - (plate.height - height - pad * 2) // 2,
        ),
    )
    return marked


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('source', type=Path)
    parser.add_argument('root', type=Path)
    parser.add_argument('preview', type=Path)
    parser.add_argument('--row', type=int, default=1)
    parser.add_argument('--column', type=int, default=1)
    parser.add_argument(
        '--r18',
        action='store_true',
        help='在书页上贴一张 R18 小标',
    )
    args = parser.parse_args()

    sheet = Image.open(args.source).convert('RGBA')
    cell_width = sheet.width / 5
    cell_height = sheet.height / 2
    x0 = int(round(args.column * cell_width))
    x1 = int(round((args.column + 1) * cell_width))
    y0 = int(round(args.row * cell_height))
    y1 = int(round((args.row + 1) * cell_height))
    sticker, center_x, center_y, badge_diameter = extract_sticker(
        sheet.crop((x0, y0, x1, y1))
    )
    print(f'badge diameter {badge_diameter:.1f}, sticker {sticker.size}')
    if args.r18:
        sticker = draw_r18_mark(sticker, center_x, center_y, badge_diameter)
        print('R18 mark drawn on the book page')

    for relative, canvas, target in TARGETS:
        icon = render_badge(sticker, center_x, center_y, badge_diameter, canvas, target)
        destination = args.root / relative
        destination.parent.mkdir(parents=True, exist_ok=True)
        icon.save(destination, optimize=True)
        print(f'{relative}: {canvas}x{canvas}, badge {target}')

    adaptive_square = mock_background(240, circle=False)
    adaptive_circle = mock_background(240, circle=True)
    badge_240 = render_badge(sticker, center_x, center_y, badge_diameter, 240, 178)
    adaptive_square.alpha_composite(badge_240, (0, 0))
    adaptive_circle.alpha_composite(badge_240, (0, 0))
    legacy_192 = render_badge(sticker, center_x, center_y, badge_diameter, 192, 175)
    about_96 = mock_background(96, circle=False)
    about_96.alpha_composite(
        render_badge(sticker, center_x, center_y, badge_diameter, 96, 87), (0, 0)
    )

    items = (adaptive_square, adaptive_circle, legacy_192, about_96)
    gaps = 32
    padding = 48
    row_width = sum(item.width for item in items) + gaps * (len(items) - 1)
    preview = Image.new(
        'RGBA',
        (row_width + padding * 2, padding + 240 + 24 + 240 + padding),
        '#faf8ff',
    )
    preview.paste(
        Image.new('RGBA', (preview.width, 240), '#191923'),
        (0, padding + 240 + 24),
    )
    for row_top in (padding, padding + 240 + 24):
        offset = padding
        for item in items:
            preview.alpha_composite(item, (offset, row_top + (240 - item.height) // 2))
            offset += item.width + gaps
    args.preview.parent.mkdir(parents=True, exist_ok=True)
    preview.save(args.preview)
    print(f'preview {args.preview}')


if __name__ == '__main__':
    main()
