import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

void main(List<String> arguments) {
  if (arguments.length != 2) {
    throw ArgumentError('Expected source sheet and output directory');
  }
  final source = img.decodePng(File(arguments[0]).readAsBytesSync());
  if (source == null || source.width != 2172 || source.height != 724) {
    throw ArgumentError('Expected the approved 2172x724 RGBA sprite sheet');
  }
  final directory = Directory(arguments[1])..createSync(recursive: true);
  final preview = img.Image(width: 1120, height: 448, numChannels: 4);
  img.fill(preview, color: img.ColorRgba8(250, 248, 255, 255));
  img.fillRect(
    preview,
    x1: 0,
    y1: 224,
    x2: 1119,
    y2: 447,
    color: img.ColorRgba8(25, 25, 35, 255),
  );
  const roles = ['discover', 'library', 'downloads', 'settings', 'about'];
  for (var index = 0; index < roles.length; index++) {
    final left = (source.width * index / roles.length).round();
    final right = (source.width * (index + 1) / roles.length).round();
    final crop = img.copyCrop(
      source,
      x: left,
      y: 110,
      width: right - left,
      height: 448,
    );
    for (final pixel in crop) {
      final horizontal = (pixel.x - crop.width / 2) / (crop.width / 2 - 3);
      final vertical = (pixel.y - 224) / 220;
      final distance = math.sqrt(horizontal * horizontal + vertical * vertical);
      final feather = ((1 - distance) * 90).clamp(0.0, 1.0);
      pixel.a = pixel.a < 32 ? 0 : (pixel.a * feather).round();
    }
    retainMainSticker(crop);
    final sticker = img.Image(width: 224, height: 224, numChannels: 4);
    final scaled = img.copyResize(
      crop,
      width: 202,
      height: 208,
      interpolation: img.Interpolation.cubic,
    );
    img.compositeImage(sticker, scaled, dstX: 11, dstY: 8);
    File('${directory.path}/${roles[index]}_active.png')
        .writeAsBytesSync(img.encodePng(sticker));
    img.compositeImage(preview, sticker, dstX: index * 224);
    img.compositeImage(preview, sticker, dstX: index * 224, dstY: 224);
  }
  File('build/mascot-active-preview.png')
      .writeAsBytesSync(img.encodePng(preview));
}

void retainMainSticker(img.Image image) {
  final visited = Uint8List(image.width * image.height);
  var largest = <int>[];
  for (final pixel in image) {
    final start = pixel.y * image.width + pixel.x;
    if (visited[start] != 0 || pixel.a == 0) continue;
    final component = <int>[start];
    visited[start] = 1;
    for (var cursor = 0; cursor < component.length; cursor++) {
      final position = component[cursor];
      final column = position % image.width;
      final row = position ~/ image.width;
      final neighbors = [
        if (column > 0) position - 1,
        if (column + 1 < image.width) position + 1,
        if (row > 0) position - image.width,
        if (row + 1 < image.height) position + image.width,
      ];
      for (final neighbor in neighbors) {
        if (visited[neighbor] != 0) continue;
        visited[neighbor] = 1;
        if (image.getPixel(neighbor % image.width, neighbor ~/ image.width).a >
            0) {
          component.add(neighbor);
        }
      }
    }
    if (component.length > largest.length) largest = component;
  }
  final retained = Uint8List(visited.length);
  for (final position in largest) {
    retained[position] = 1;
  }
  for (final pixel in image) {
    if (retained[pixel.y * image.width + pixel.x] == 0) pixel.a = 0;
  }
}
