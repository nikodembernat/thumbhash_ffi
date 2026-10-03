import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:thumbhash_ffi/src/thumbhash_ffi.dart';

/// Encodes [inputImage] to a ThumbHash and decodes it back, all in one step.
///
/// Shows what the ThumbHash placeholder of an image looks like:
///
/// ```dart
/// Image(
///   image: ThumbhashTheImage(NetworkImage(url)),
///   fit: BoxFit.cover,
/// )
/// ```
///
/// To display placeholders while images load, store the hashes with the
/// images and use `ThumbhashFfiImage` or the `ThumbhashFfi` widget instead.
@immutable
class ThumbhashTheImage extends ImageProvider<ThumbhashTheImage> {
  /// Creates an image provider that shows the ThumbHash of [inputImage].
  const ThumbhashTheImage(
    this.inputImage, {
    this.decodingWidth,
    this.decodingHeight,
    this.scale = 1,
  });

  /// The image to encode.
  final ImageProvider inputImage;

  /// The width of the decoded image, see [ThumbhashFFI.decode].
  final int? decodingWidth;

  /// The height of the decoded image, see [ThumbhashFFI.decode].
  final int? decodingHeight;

  /// The scale to place in the [ImageInfo] object of the image.
  final double scale;

  @override
  Future<ThumbhashTheImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture<ThumbhashTheImage>(this);

  @override
  ImageStreamCompleter loadImage(
    ThumbhashTheImage key,
    ImageDecoderCallback decode,
  ) => OneFrameImageStreamCompleter(
    key._load(),
    informationCollector: () => [
      DiagnosticsProperty<ImageProvider>('Image provider', this),
      DiagnosticsProperty<ThumbhashTheImage>('Image key', key),
    ],
  );

  Future<ImageInfo> _load() async {
    final hash = await ThumbhashFFI.encode(inputImage);

    return ImageInfo(
      image: await ThumbhashFFI.decode(
        hash,
        width: decodingWidth,
        height: decodingHeight,
      ),
      scale: scale,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ThumbhashTheImage &&
      other.runtimeType == runtimeType &&
      other.inputImage == inputImage &&
      other.decodingWidth == decodingWidth &&
      other.decodingHeight == decodingHeight &&
      other.scale == scale;

  @override
  int get hashCode =>
      Object.hash(inputImage, decodingWidth, decodingHeight, scale);

  @override
  String toString() =>
      '${objectRuntimeType(this, 'ThumbhashTheImage')}'
      '($inputImage, scale: ${scale.toStringAsFixed(1)})';
}
