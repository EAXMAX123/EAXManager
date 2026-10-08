import argparse
from collections import deque
from pathlib import Path

import numpy as np
from PIL import Image

ROLES = ('discover', 'library', 'downloads', 'settings', 'about')
MINT = np.array([203, 236, 214])
CANVAS = 224
TARGET_DIAMETER = 202.0
REACH_LIMIT = 108.0


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


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('source', type=Path)
    parser.add_argument('destination', type=Path)
    parser.add_argument('preview', type=Path)
    args = parser.parse_args()

    source = Image.open(args.source).convert('RGBA')
    width, height = source.size
    array = np.array(source)
    alpha = array[:, :, 3]
    rgb = array[:, :, :3]
    cell_width, cell_height = width / 5, height / 2

    cells = []
    for row in range(2):
        for column in range(5):
            x0 = int(round(column * cell_width))
            x1 = int(round((column + 1) * cell_width))
            y0 = int(round(row * cell_height))
            y1 = int(round((row + 1) * cell_height))
            cell_alpha = alpha[y0:y1, x0:x1]
            mask = cell_alpha >= 24
            labels, components = labeled_components(mask)
            sticker = max(components, key=len)
            component_mask = np.zeros_like(mask)
            rows = np.array([pixel[0] for pixel in sticker])
            columns = np.array([pixel[1] for pixel in sticker])
            component_mask[rows, columns] = True

            badge_mask = (
                component_mask
                & (np.abs(rgb[y0:y1, x0:x1] - MINT).sum(axis=2) < 90)
                & (cell_alpha > 200)
            )
            badge_rows, badge_columns = np.where(badge_mask)
            if not len(badge_rows):
                raise ValueError(f'No badge found in cell row {row} col {column}')
            badge_center_x = (badge_columns.max() + badge_columns.min()) / 2 + x0
            badge_center_y = (badge_rows.max() + badge_rows.min()) / 2 + y0
            diameter = max(
                badge_columns.max() - badge_columns.min() + 1,
                badge_rows.max() - badge_rows.min() + 1,
            )
            reach = np.sqrt(
                (rows - (badge_center_y - y0)) ** 2
                + (columns - (badge_center_x - x0)) ** 2
            ).max()

            extract = dilate(component_mask, 2) & (cell_alpha > 8)
            sub = array[y0:y1, x0:x1].copy()
            sub[~extract] = 0
            extract_rows, extract_columns = np.where(extract)
            crop_x0 = x0 + extract_columns.min()
            crop_y0 = y0 + extract_rows.min()
            crop = Image.fromarray(
                sub[
                    extract_rows.min():extract_rows.max() + 1,
                    extract_columns.min():extract_columns.max() + 1,
                ],
                'RGBA',
            )
            cells.append({
                'role': ROLES[column],
                'active': row == 1,
                'crop': crop,
                'center_x': badge_center_x - crop_x0,
                'center_y': badge_center_y - crop_y0,
                'diameter': float(diameter),
                'reach': float(reach),
            })

    mean_diameter = sum(cell['diameter'] for cell in cells) / len(cells)
    max_reach = max(cell['reach'] for cell in cells)
    scale = min(TARGET_DIAMETER / mean_diameter, REACH_LIMIT / max_reach)
    print(f'scale {scale:.4f} (mean diameter {mean_diameter:.1f}, reach {max_reach:.1f})')

    args.destination.mkdir(parents=True, exist_ok=True)
    sprites = []
    for cell in cells:
        crop = cell['crop']
        scaled = crop.resize(
            (round(crop.width * scale), round(crop.height * scale)),
            Image.Resampling.LANCZOS,
        )
        layer = Image.new('RGBA', (CANVAS + 32, CANVAS + 32))
        layer.alpha_composite(
            scaled,
            (
                round(CANVAS / 2 - cell['center_x'] * scale) + 16,
                round(CANVAS / 2 - cell['center_y'] * scale) + 16,
            ),
        )
        final = layer.crop((16, 16, 16 + CANVAS, 16 + CANVAS))
        name = f"{cell['role']}{'_active' if cell['active'] else ''}.png"
        final.save(args.destination / name, optimize=True)
        sprites.append((cell, final))
        final_diameter = cell['diameter'] * scale
        print(f"{name}: diameter {final_diameter:.1f}")

    light = Image.new('RGBA', (CANVAS * 5, CANVAS * 2), '#faf8ff')
    dark = Image.new('RGBA', (CANVAS * 5, CANVAS * 2), '#191923')
    for cell, sprite in sprites:
        column = ROLES.index(cell['role'])
        row = 1 if cell['active'] else 0
        light.alpha_composite(sprite, (column * CANVAS, row * CANVAS))
        dark.alpha_composite(sprite, (column * CANVAS, row * CANVAS))
    preview = Image.new('RGBA', (CANVAS * 5, CANVAS * 4))
    preview.paste(light, (0, 0))
    preview.paste(dark, (0, CANVAS * 2))
    args.preview.parent.mkdir(parents=True, exist_ok=True)
    preview.save(args.preview)
    print(f'preview {args.preview}')


if __name__ == '__main__':
    main()
