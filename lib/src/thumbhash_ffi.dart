import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:thumbhash_ffi/src/codec/codec.dart' as codec;
import 'package:thumbhash_ffi/src/constants.dart';
import 'package:thumbhash_ffi/src/exception.dart';
import 'package:thumbhash_ffi/src/hash_header.dart';
import 'package:thumbhash_ffi/src/thumbhash_rgba.dart';

/// Decodes larger than this many pixels run on a background isolate.
///
/// Decoding a placeholder of the default size (at most 32x32 pixels) takes a
/// few microseconds, much less than spawning an isolate would.
const _backgroundDecodeThreshold = 256 * 256;

/// Encodes images to ThumbHashes and decodes ThumbHashes to images.
///
/// A ThumbHash is a very compact (at most 25 bytes) representation of an
/// image placeholder, see https://evanw.github.io/thumbhash/. Hashes are
/// usually stored as base64 strings, use `base64Encode` and `base64Decode`
/// from `dart:convert` to convert them.
///
/// The codec is implemented in C and called through `dart:ffi`. On the web,
/// where `dart:ffi` is not available, an equivalent Dart implementation is
/// used instead, see [isNative].
abstract final class ThumbhashFFI {
  /// The maximum number of bytes in a ThumbHash.
  static const maxHashLength = thumbhashMaxHashLength;

  /// The maximum width and height of an image accepted by [encodeRgba].
  static const maxEncodeSize = thumbhashMaxEncodeSize;

  /// The maximum width and height of a decoded image.
  static const maxDecodeSize = thumbhashMaxDecodeSize;

  /// Whether the codec runs native code (`true` everywhere but on the web).
  static bool get isNative => codec.isNativeCodec;

  /// Encodes the image provided by [imageProvider] to a ThumbHash.
  ///
  /// Works with any [ImageProvider], e.g. [NetworkImage], [AssetImage],
  /// [FileImage] or [MemoryImage]. The image is decoded by the engine
  /// directly at a size of at most [maxEncodeSize] pixels, so encoding even
  /// a very large image is cheap.
  ///
  /// Throws a [ThumbhashFFIException] if the image cannot be loaded.
  static Future<Uint8List> encode(ImageProvider imageProvider) async {
    final ui.Image image;
    try {
      image = await _resolveImage(
        ResizeImage(
          imageProvider,
          width: maxEncodeSize,
          height: maxEncodeSize,
          policy: ResizeImagePolicy.fit,
        ),
      );
    } catch (err) {
      throw ThumbhashFFIException('Could not load the image.', err);
    }

    try {
      return await encodeImage(image);
    } finally {
      image.dispose();
    }
  }

  /// Encodes [image] to a ThumbHash.
  ///
  /// Images larger than [maxEncodeSize] pixels are downscaled first. The
  /// caller remains responsible for disposing [image].
  ///
  /// Throws a [ThumbhashFFIException] if the pixels of [image] cannot be
  /// read.
  static Future<Uint8List> encodeImage(ui.Image image) async {
    final scaled = image.width > maxEncodeSize || image.height > maxEncodeSize
        ? await _downscale(image)
        : null;
    final source = scaled ?? image;
    try {
      final data = await source.toByteData(
        format: ui.ImageByteFormat.rawStraightRgba,
      );
      if (data == null) {
        throw const ThumbhashFFIException('Could not read the image pixels.');
      }

      return encodeRgba(
        source.width,
        source.height,
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      );
    } finally {
      scaled?.dispose();
    }
  }

  /// Encodes an RGBA image to a ThumbHash.
  ///
  /// [rgba] holds the pixels row by row, with 4 bytes (R, G, B, A) per pixel
  /// and RGB not premultiplied by alpha. [width] and [height] must be in
  /// range [1, [maxEncodeSize]]: downscale larger images first (encoding
  /// larger images is slow and does not improve the result).
  ///
  /// This runs synchronously and takes well under a millisecond.
  static Uint8List encodeRgba(int width, int height, Uint8List rgba) {
    RangeError.checkValueInInterval(width, 1, maxEncodeSize, 'width');
    RangeError.checkValueInInterval(height, 1, maxEncodeSize, 'height');
    if (rgba.length != width * height * 4) {
      throw ArgumentError.value(
        rgba.length,
        'rgba',
        'Must contain width * height * 4 = ${width * height * 4} bytes',
      );
    }

    return codec.encodeRgba(width, height, rgba);
  }

  /// Decodes [hash] to an image.
  ///
  /// By default the image has the size used by the reference implementation
  /// (see [decodedSize]): placeholders are smooth, so it is cheaper to let
  /// Flutter scale a small image up. Pass [width] and/or [height] to render
  /// the placeholder at a different size; when only one of them is given,
  /// the other is derived from the [approximateAspectRatio].
  ///
  /// Throws a [ThumbhashFFIException] if [hash] is invalid.
  static Future<ui.Image> decode(
    Uint8List hash, {
    int? width,
    int? height,
  }) async {
    final size = _resolveDecodeSize(hash, width, height);
    final rgba = size.width * size.height > _backgroundDecodeThreshold
        ? await compute(_decodePremultiplied, (hash, size.width, size.height))
        : _decodePremultiplied((hash, size.width, size.height));

    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      rgba,
      size.width,
      size.height,
      ui.PixelFormat.rgba8888,
      completer.complete,
    );

    return await completer.future;
  }

  /// Decodes [hash] to RGBA pixels.
  ///
  /// The size is determined like in [decode]. RGB is not premultiplied by
  /// alpha unless [premultiplied] is `true`.
  ///
  /// This runs synchronously and, at the default size, takes a few
  /// microseconds.
  ///
  /// Throws a [ThumbhashFFIException] if [hash] is invalid.
  static ThumbhashRgba decodeRgba(
    Uint8List hash, {
    int? width,
    int? height,
    bool premultiplied = false,
  }) {
    final size = _resolveDecodeSize(hash, width, height);

    return ThumbhashRgba(
      width: size.width,
      height: size.height,
      rgba: codec.decodeRgba(
        hash,
        size.width,
        size.height,
        premultiplied: premultiplied,
      ),
      premultiplied: premultiplied,
    );
  }

  /// Returns whether [hash] is a well-formed ThumbHash.
  static bool isValid(Uint8List hash) => HashHeader.isValid(hash);

  /// Returns the approximate aspect ratio (width / height) of the original
  /// image.
  ///
  /// Throws a [ThumbhashFFIException] if [hash] is invalid.
  static double approximateAspectRatio(Uint8List hash) =>
      HashHeader.parse(hash).aspectRatio;

  /// Returns the size of the image returned by [decode] and [decodeRgba]
  /// when no size is given: the larger side is 32 pixels and the aspect
  /// ratio matches the [approximateAspectRatio].
  ///
  /// Throws a [ThumbhashFFIException] if [hash] is invalid.
  static ({int width, int height}) decodedSize(Uint8List hash) =>
      HashHeader.parse(hash).decodedSize;

  /// Returns the average color of the image, which is a good background
  /// to show while the placeholder is being decoded.
  ///
  /// Throws a [ThumbhashFFIException] if [hash] is invalid.
  static Color averageColor(Uint8List hash) {
    final (:red, :green, :blue, :alpha) = HashHeader.parse(hash).averageRgba;

    return Color.from(alpha: alpha, red: red, green: green, blue: blue);
  }

  static ({int width, int height}) _resolveDecodeSize(
    Uint8List hash,
    int? width,
    int? height,
  ) {
    final header = HashHeader.parse(hash);
    final size = switch ((width, height)) {
      (null, null) => header.decodedSize,
      (final width?, null) => (
        width: width,
        height: math.max(1, (width / header.aspectRatio).round()),
      ),
      (null, final height?) => (
        width: math.max(1, (height * header.aspectRatio).round()),
        height: height,
      ),
      (final width?, final height?) => (width: width, height: height),
    };
    RangeError.checkValueInInterval(size.width, 1, maxDecodeSize, 'width');
    RangeError.checkValueInInterval(size.height, 1, maxDecodeSize, 'height');

    return size;
  }
}

Uint8List _decodePremultiplied((Uint8List, int, int) args) {
  final (hash, width, height) = args;

  return codec.decodeRgba(hash, width, height, premultiplied: true);
}

Future<ui.Image> _resolveImage(ImageProvider imageProvider) {
  final completer = Completer<ui.Image>();
  final stream = imageProvider.resolve(ImageConfiguration.empty);
  late final ImageStreamListener listener;
  listener = ImageStreamListener(
    (info, _) {
      stream.removeListener(listener);
      if (!completer.isCompleted) {
        completer.complete(info.image.clone());
      }
      info.dispose();
    },
    onError: (error, stackTrace) {
      stream.removeListener(listener);
      if (!completer.isCompleted) {
        completer.completeError(error, stackTrace);
      }
    },
  );
  stream.addListener(listener);

  return completer.future;
}

Future<ui.Image> _downscale(ui.Image image) async {
  final scale = thumbhashMaxEncodeSize / math.max(image.width, image.height);
  final width = math.max(1, (image.width * scale).round());
  final height = math.max(1, (image.height * scale).round());

  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawImageRect(
    image,
    Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
    Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    Paint()..filterQuality = FilterQuality.medium,
  );
  final picture = recorder.endRecording();
  try {
    return await picture.toImage(width, height);
  } finally {
    picture.dispose();
  }
}
