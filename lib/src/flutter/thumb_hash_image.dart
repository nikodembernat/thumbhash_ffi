import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:thumbhash_ffi/src/thumb_hash.dart';

/// Decodes a [ThumbHash] as an image.
///
/// ```dart
/// Image(
///   image: ThumbHashImage(ThumbHash.fromBase64('k0oGLQaSVsN0BVhX2oq2Z5SQUQcZ')),
///   fit: BoxFit.cover,
/// )
/// ```
///
/// Also works as the placeholder of a `FadeInImage`.
@immutable
class ThumbHashImage extends ImageProvider<ThumbHashImage> {
  /// Creates an image provider that decodes [hash].
  const ThumbHashImage(this.hash, {this.scale = 1});

  /// The hash to decode.
  final ThumbHash hash;

  /// The scale to place in the [ImageInfo] object of the image.
  final double scale;

  @override
  Future<ThumbHashImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture<ThumbHashImage>(this);

  @override
  ImageStreamCompleter loadImage(
    ThumbHashImage key,
    ImageDecoderCallback decode,
  ) => OneFrameImageStreamCompleter(
    key._load(),
    informationCollector: () => [
      DiagnosticsProperty<ImageProvider>('Image provider', this),
      DiagnosticsProperty<ThumbHashImage>('Image key', key),
    ],
  );

  Future<ImageInfo> _load() async =>
      ImageInfo(image: await hash.toImage(), scale: scale);

  @override
  bool operator ==(Object other) =>
      other is ThumbHashImage &&
      other.runtimeType == runtimeType &&
      other.hash == hash &&
      other.scale == scale;

  @override
  int get hashCode => Object.hash(hash, scale);

  @override
  String toString() =>
      '${objectRuntimeType(this, 'ThumbHashImage')}'
      '($hash, scale: ${scale.toStringAsFixed(1)})';
}
