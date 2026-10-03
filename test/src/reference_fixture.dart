/// A test case generated with the upstream Rust implementation of ThumbHash.
class ReferenceFixture {
  const ReferenceFixture({
    required this.name,
    required this.width,
    required this.height,
    required this.inputChecksum,
    required this.hashBase64,
    required this.decodedWidth,
    required this.decodedHeight,
    required this.decodedBase64,
    required this.averageRgba,
    required this.aspectRatio,
  });

  final String name;
  final int width;
  final int height;

  /// The FNV-1a checksum of the input pixels.
  final int inputChecksum;

  /// The hash computed by `rgba_to_thumb_hash`.
  final String hashBase64;

  /// The image computed by `thumb_hash_to_rgba`.
  final int decodedWidth;
  final int decodedHeight;
  final String decodedBase64;

  /// The color computed by `thumb_hash_to_average_rgba`.
  final (double, double, double, double) averageRgba;

  /// The ratio computed by `thumb_hash_to_approximate_aspect_ratio`.
  final double aspectRatio;
}
