import argparse
from collections import deque
from pathlib import Path

from PIL import Image


def isolate_badge(image):
    width, height = image.size
    alpha = image.getchannel('A').tobytes()
    start = (height // 2) * width + width // 2
    if alpha[start] < 32:
        raise ValueError('Expected an opaque badge at the center of each cell')
    retained = bytearray(width * height)
    retained[start] = 255
    pending = deque([start])
    while pending:
        position = pending.popleft()
        column, row = position % width, position // width
        neighbors = []
        if column:
            neighbors.append(position - 1)
        if column + 1 < width:
            neighbors.append(position + 1)
        if row:
            neighbors.append(position - width)
        if row + 1 < height:
            neighbors.append(position + width)
        for neighbor in neighbors:
            if not retained[neighbor] and alpha[neighbor] >= 32:
                retained[neighbor] = 255
                pending.append(neighbor)
    cleaned_alpha = bytes(
        original if keep else 0 for original, keep in zip(alpha, retained)
    )
    image.putalpha(Image.frombytes('L', image.size, cleaned_alpha))
    return image


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('source', type=Path)
    parser.add_argument('destination', type=Path)
    args = parser.parse_args()
    source = Image.open(args.source).convert('RGBA')
    if source.size != (1774, 887):
        raise ValueError('Expected the approved 1774x887 discovery pose sheet')
    args.destination.mkdir(parents=True, exist_ok=True)
    preview = Image.new('RGBA', (448, 448), '#faf8ff')
    preview.paste('#191923', (0, 224, 448, 448))
    for index, name in enumerate(('discover', 'discover_active')):
        cell = source.crop((index * 887, 0, (index + 1) * 887, 887))
        badge = isolate_badge(cell).resize((202, 202), Image.Resampling.LANCZOS)
        sticker = Image.new('RGBA', (224, 224))
        sticker.alpha_composite(badge, (11, 11))
        sticker.save(args.destination / f'{name}.png', optimize=True)
        preview.alpha_composite(sticker, (index * 224, 0))
        preview.alpha_composite(sticker, (index * 224, 224))
    preview.save(args.source.parent / 'discover-beta5-preview.png')


if __name__ == '__main__':
    main()
