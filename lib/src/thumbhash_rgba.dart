import 'dart:typed_data';

/// A decoded ThumbHash: an RGBA image with 8 bits per channel.
final class ThumbhashRgba {
  /// Creates a [ThumbhashRgba].
  const ThumbhashRgba({
    required this.width,
    required this.height,
    required this.rgba,
    required this.premultiplied,
  });

  /// The width of the image in pixels.
  final int width;

  /// The height of the image in pixels.
  final int height;

  /// The pixels of the image, row by row, 4 bytes (R, G, B, A) per pixel.
  ///
  /// Contains exactly `width * height * 4` bytes.
  final Uint8List rgba;

  /// Whether RGB is premultiplied by alpha.
  final bool premultiplied;

  @override
  String toString() =>
      'ThumbhashRgba(${width}x$height, premultiplied: $premultiplied)';
}
