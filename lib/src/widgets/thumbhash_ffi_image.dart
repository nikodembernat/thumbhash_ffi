import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:thumbhash_ffi/src/thumbhash_ffi.dart';

/// Decodes a ThumbHash as an image.
///
/// ```dart
/// Image(
///   image: ThumbhashFfiImage.fromBase64('k0oGLQaSVsN0BVhX2oq2Z5SQUQcZ'),
///   fit: BoxFit.cover,
/// )
/// ```
///
/// Works great as the placeholder of a `FadeInImage`.
@immutable
class ThumbhashFfiImage extends ImageProvider<ThumbhashFfiImage> {
  /// Creates an image provider that decodes [hash].
  ///
  /// [hash] must not be modified afterwards, since it is part of the key in
  /// the image cache.
  const ThumbhashFfiImage(
    this.hash, {
    this.decodingWidth,
    this.decodingHeight,
    this.scale = 1,
  });

  /// Creates an image provider that decodes a base64 encoded ThumbHash.
  ThumbhashFfiImage.fromBase64(
    String hash, {
    int? decodingWidth,
    int? decodingHeight,
    double scale = 1,
  }) : this(
         base64Decode(hash),
         decodingWidth: decodingWidth,
         decodingHeight: decodingHeight,
         scale: scale,
       );

  /// The ThumbHash to decode.
  final Uint8List hash;

  /// The width of the decoded image, see [ThumbhashFFI.decode].
  final int? decodingWidth;

  /// The height of the decoded image, see [ThumbhashFFI.decode].
  final int? decodingHeight;

  /// The scale to place in the [ImageInfo] object of the image.
  final double scale;

  @override
  Future<ThumbhashFfiImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture<ThumbhashFfiImage>(this);

  @override
  ImageStreamCompleter loadImage(
    ThumbhashFfiImage key,
    ImageDecoderCallback decode,
  ) => OneFrameImageStreamCompleter(
    key._load(),
    informationCollector: () => [
      DiagnosticsProperty<ImageProvider>('Image provider', this),
      DiagnosticsProperty<ThumbhashFfiImage>('Image key', key),
    ],
  );

  Future<ImageInfo> _load() async => ImageInfo(
    image: await ThumbhashFFI.decode(
      hash,
      width: decodingWidth,
      height: decodingHeight,
    ),
    scale: scale,
  );

  @override
  bool operator ==(Object other) =>
      other is ThumbhashFfiImage &&
      other.runtimeType == runtimeType &&
      listEquals(other.hash, hash) &&
      other.decodingWidth == decodingWidth &&
      other.decodingHeight == decodingHeight &&
      other.scale == scale;

  @override
  int get hashCode =>
      Object.hash(Object.hashAll(hash), decodingWidth, decodingHeight, scale);

  @override
  String toString() =>
      '${objectRuntimeType(this, 'ThumbhashFfiImage')}'
      '("${base64Encode(hash)}", scale: ${scale.toStringAsFixed(1)})';
}
