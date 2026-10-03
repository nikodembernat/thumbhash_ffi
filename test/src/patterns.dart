import 'dart:convert';
import 'dart:typed_data';

import 'reference_fixtures.dart';

/// Generates the input image of the reference fixture called [name].
///
/// Must stay in sync with `tool/reference_generator/src/main.rs`.
Uint8List patternRgba(String name) => switch (name) {
  'gradient' => _generate(
    32,
    32,
    (x, y) => [x * 255 ~/ 31, y * 255 ~/ 31, 128, 255],
  ),
  'landscape' => _generate(
    100,
    60,
    (x, y) => [(x * y) % 256, (x + 3 * y) % 256, 255 - 2 * x, 255],
  ),
  'portrait' => _generate(
    40,
    100,
    (x, y) => [255 - 2 * y, (x * 7) % 256, (x * y ~/ 3) % 256, 255],
  ),
  'circle_alpha' => _generate(64, 64, (x, y) {
    final dx = 2 * x + 1 - 64;
    final dy = 2 * y + 1 - 64;
    final d2 = dx * dx + dy * dy;
    final a = d2 < 48 * 48 ? 255 : (d2 < 56 * 56 ? 128 : 0);
    return [200, (x * 4) % 256, (y * 4) % 256, a];
  }),
  'alpha_gradient' => _generate(
    50,
    80,
    (x, y) => [x * 5, 100, y * 3, y * 255 ~/ 79],
  ),
  'noise' => _noise(100, 100, 42, withAlpha: false),
  'noise_alpha' => _noise(37, 53, 7, withAlpha: true),
  'single_pixel' => Uint8List.fromList([12, 34, 56, 255]),
  'transparent' => Uint8List(10 * 10 * 4),
  'solid' => _generate(20, 20, (_, _) => [10, 200, 90, 255]),
  'wide' => _generate(100, 1, (x, _) => [x * 2, 255 - x * 2, x, 255]),
  'tall' => _generate(1, 100, (_, y) => [y, y * 2, 255 - y * 2, 255]),
  'flower' => base64Decode(flowerRgbaBase64),
  _ => throw ArgumentError.value(name, 'name', 'Unknown pattern'),
};

Uint8List _generate(int w, int h, List<int> Function(int x, int y) pixel) {
  final rgba = Uint8List(w * h * 4);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      rgba.setAll((y * w + x) * 4, pixel(x, y));
    }
  }

  return rgba;
}

Uint8List _noise(int w, int h, int seed, {required bool withAlpha}) {
  var state = seed;
  int next() {
    state = (_mul32(state, 1103515245) + 12345) & 0xFFFFFFFF;
    return (state >> 16) & 255;
  }

  final rgba = Uint8List(w * h * 4);
  for (var i = 0; i < w * h * 4; i += 4) {
    rgba[i] = next();
    rgba[i + 1] = next();
    rgba[i + 2] = next();
    rgba[i + 3] = withAlpha ? next() : 255;
  }

  return rgba;
}

/// The FNV-1a checksum of [bytes].
int fnv1a(Uint8List bytes) {
  var hash = 0x811c9dc5;
  for (final byte in bytes) {
    hash = _mul32(hash ^ byte, 0x01000193);
  }

  return hash;
}

/// Multiplies two 32-bit unsigned integers modulo 2^32, without exceeding the
/// 53 bits of integer precision available on the web.
int _mul32(int a, int b) {
  final low = (a & 0xFFFF) * b;
  final high = (((a >> 16) & 0xFFFF) * b) & 0xFFFF;

  return (low + high * 0x10000) & 0xFFFFFFFF;
}
