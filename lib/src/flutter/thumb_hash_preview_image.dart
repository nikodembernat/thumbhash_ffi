import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:thumbhash_ffi/src/thumb_hash.dart';

/// Shows what the ThumbHash placeholder of [source] looks like, by encoding
/// it and decoding the hash.
///
/// ```dart
/// Image(image: ThumbHashPreviewImage(AssetImage('assets/photo.jpg')))
/// ```
///
/// This loads [source] to compute its hash, so it is no use as a
/// placeholder for [source] itself: store the hash with the image and use a
/// `ThumbHashImage` or a `ThumbHashPlaceholder` for that.
@immutable
class ThumbHashPreviewImage extends ImageProvider<ThumbHashPreviewImage> {
  /// Creates an image provider that shows the placeholder of [source].
  const ThumbHashPreviewImage(this.source, {this.scale = 1});

  /// The image to encode.
  final ImageProvider source;

  /// The scale to place in the [ImageInfo] object of the image.
  final double scale;

  @override
  Future<ThumbHashPreviewImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture<ThumbHashPreviewImage>(this);

  @override
  ImageStreamCompleter loadImage(
    ThumbHashPreviewImage key,
    ImageDecoderCallback decode,
  ) => OneFrameImageStreamCompleter(
    key._load(),
    informationCollector: () => [
      DiagnosticsProperty<ImageProvider>('Image provider', this),
      DiagnosticsProperty<ThumbHashPreviewImage>('Image key', key),
    ],
  );

  Future<ImageInfo> _load() async {
    final hash = await ThumbHash.encode(source);

    return ImageInfo(image: await hash.toImage(), scale: scale);
  }

  @override
  bool operator ==(Object other) =>
      other is ThumbHashPreviewImage &&
      other.runtimeType == runtimeType &&
      other.source == source &&
      other.scale == scale;

  @override
  int get hashCode => Object.hash(source, scale);

  @override
  String toString() =>
      '${objectRuntimeType(this, 'ThumbHashPreviewImage')}'
      '($source, scale: ${scale.toStringAsFixed(1)})';
}
