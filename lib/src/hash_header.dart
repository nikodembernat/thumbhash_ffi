import 'dart:typed_data';

/// The constants stored at the beginning of every ThumbHash.
///
/// Used to validate hashes on every platform, and by the pure Dart codec on
/// the web.
final class HashHeader {
  /// Parses the header of [hash].
  ///
  /// Throws a [FormatException] if [hash] is malformed or shorter than its
  /// header says it should be.
  factory HashHeader.parse(List<int> hash) {
    if (hash.length < 5) {
      throw _invalid(hash, 'expected at least 5 bytes');
    }

    final header24 = hash[0] | (hash[1] << 8) | (hash[2] << 16);
    final header16 = hash[3] | (hash[4] << 8);
    final hasAlpha = (header24 >> 23) != 0;
    final isLandscape = (header16 >> 15) != 0;
    final lMin = header16 & 7;
    if (lMin == 0) {
      // The reference implementation would decode an empty image.
      throw _invalid(hash, 'no luminance components');
    }

    final lMax = hasAlpha ? 5 : 7;
    final rawLx = isLandscape ? lMax : lMin;
    final rawLy = isLandscape ? lMin : lMax;
    final lx = rawLx < 3 ? 3 : rawLx;
    final ly = rawLy < 3 ? 3 : rawLy;
    final acStart = hasAlpha ? 6 : 5;
    final nibbles = acCount(lx, ly) + 2 * 5 + (hasAlpha ? 14 : 0);
    final length = acStart + (nibbles + 1) ~/ 2;
    if (hash.length < length) {
      throw _invalid(hash, 'expected $length bytes');
    }

    return HashHeader._(
      lDc: (header24 & 63) / 63,
      pDc: ((header24 >> 6) & 63) / 31.5 - 1,
      qDc: ((header24 >> 12) & 63) / 31.5 - 1,
      lScale: ((header24 >> 18) & 31) / 31,
      pScale: ((header16 >> 3) & 63) / 63,
      qScale: ((header16 >> 9) & 63) / 63,
      aDc: hasAlpha ? (hash[5] & 15) / 15 : 1,
      aScale: hasAlpha ? (hash[5] >> 4) / 15 : 1,
      hasAlpha: hasAlpha,
      aspectRatio: rawLx / rawLy,
      lx: lx,
      ly: ly,
      acStart: acStart,
      length: length,
    );
  }

  const HashHeader._({
    required this.lDc,
    required this.pDc,
    required this.qDc,
    required this.lScale,
    required this.pScale,
    required this.qScale,
    required this.aDc,
    required this.aScale,
    required this.hasAlpha,
    required this.aspectRatio,
    required this.lx,
    required this.ly,
    required this.acStart,
    required this.length,
  });

  /// The DC (average) luminance.
  final double lDc;

  /// The DC (average) yellow-blue chrominance.
  final double pDc;

  /// The DC (average) red-green chrominance.
  final double qDc;

  /// The scale of the luminance AC coefficients.
  final double lScale;

  /// The scale of the yellow-blue chrominance AC coefficients.
  final double pScale;

  /// The scale of the red-green chrominance AC coefficients.
  final double qScale;

  /// The DC (average) alpha.
  final double aDc;

  /// The scale of the alpha AC coefficients.
  final double aScale;

  /// Whether the image has transparent pixels.
  final bool hasAlpha;

  /// The approximate aspect ratio (width / height) of the original image.
  final double aspectRatio;

  /// The number of luminance components along the x axis.
  final int lx;

  /// The number of luminance components along the y axis.
  final int ly;

  /// The index of the first byte with AC coefficients.
  final int acStart;

  /// The number of meaningful bytes in the hash.
  final int length;

  /// The size of the decoded placeholder: the larger side is 32px and the
  /// aspect ratio is preserved.
  ({int width, int height}) get decodedSize => aspectRatio > 1
      ? (width: 32, height: (32 / aspectRatio).round())
      : (width: (32 * aspectRatio).round(), height: 32);

  /// The average color of the image as (red, green, blue, alpha) in range
  /// [0, 1]. RGB is not premultiplied by alpha.
  ({double red, double green, double blue, double alpha}) get averageRgba {
    final b = lDc - 2 / 3 * pDc;
    final r = (3 * lDc - b + qDc) / 2;
    final g = r - qDc;

    return (
      red: r.clamp(0, 1),
      green: g.clamp(0, 1),
      blue: b.clamp(0, 1),
      alpha: aDc,
    );
  }

  static FormatException _invalid(List<int> hash, String reason) =>
      FormatException('Invalid ThumbHash of ${hash.length} bytes: $reason');
}

/// The number of AC coefficients in a channel with `nx` by `ny` components.
int acCount(int nx, int ny) {
  var count = 0;
  for (var cy = 0; cy < ny; cy++) {
    for (var cx = cy > 0 ? 0 : 1; cx * ny < nx * (ny - cy); cx++) {
      count++;
    }
  }

  return count;
}

/// Premultiplies the RGB of [rgba] by its alpha, rounding like the native
/// implementation.
void premultiply(Uint8List rgba) {
  for (var i = 0; i < rgba.length; i += 4) {
    final a = rgba[i + 3];
    rgba
      ..[i] = (rgba[i] * a + 127) ~/ 255
      ..[i + 1] = (rgba[i + 1] * a + 127) ~/ 255
      ..[i + 2] = (rgba[i + 2] * a + 127) ~/ 255;
  }
}
