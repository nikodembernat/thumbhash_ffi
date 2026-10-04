import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:thumbhash_ffi/src/codec/codec.dart' as codec;
import 'package:thumbhash_ffi/src/hash_header.dart';

/// A ThumbHash: a very compact (at most 25 bytes) representation of an
/// image, rendered as a blurry placeholder while the actual image loads.
///
/// See https://evanw.github.io/thumbhash/.
///
/// Instances are immutable and always valid: the constructors reject
/// malformed hashes. Two hashes are equal if they have the same bytes.
///
/// ```dart
/// // When an image is uploaded, compute its hash and store it with the image.
/// final hash = await ThumbHash.encode(FileImage(file));
/// final stored = hash.toBase64();
///
/// // Later, show it while the image loads.
/// ThumbHashPlaceholder(
///   hash: ThumbHash.fromBase64(stored),
///   image: NetworkImage(url),
/// )
/// ```
///
/// On every platform but the web, encoding and decoding run C code through
/// `dart:ffi`. On the web, an equivalent Dart implementation is used
/// instead, see [isNative].
@immutable
final class ThumbHash {
  /// Creates a hash from its bytes.
  ///
  /// Trailing bytes that are not part of the hash are dropped.
  ///
  /// Throws a [FormatException] if [bytes] is not a valid ThumbHash.
  factory ThumbHash.fromBytes(List<int> bytes) {
    final header = HashHeader.parse(bytes);

    return ThumbHash._(Uint8List.fromList(bytes.sublist(0, header.length)));
  }

  /// Creates a hash from its base64 encoding (padded or not, standard or URL
  /// safe).
  ///
  /// Throws a [FormatException] if [encoded] is not a valid base64 encoded
  /// ThumbHash.
  factory ThumbHash.fromBase64(String encoded) =>
      ThumbHash.fromBytes(base64.decode(base64.normalize(encoded)));

  /// Encodes an RGBA image.
  ///
  /// [rgba] holds the pixels row by row, with 4 bytes (R, G, B, A) per pixel
  /// and RGB not premultiplied by alpha. [width] and [height] must be in
  /// range [1, [maxEncodeSize]]: downscale larger images first (larger
  /// images take longer to encode without improving the result), or use
  /// [encode] or [encodeImage], which do that for you.
  ///
  /// Runs synchronously and takes well under a millisecond.
  factory ThumbHash.encodeRgba(int width, int height, Uint8List rgba) {
    RangeError.checkValueInInterval(width, 1, maxEncodeSize, 'width');
    RangeError.checkValueInInterval(height, 1, maxEncodeSize, 'height');
    if (rgba.length != width * height * 4) {
      throw ArgumentError.value(
        rgba.length,
        'rgba.length',
        'Must be width * height * 4 = ${width * height * 4}',
      );
    }

    return ThumbHash._(codec.encodeRgba(width, height, rgba));
  }

  ThumbHash._(this._bytes);

  /// The maximum width and height of an image accepted by [ThumbHash.encodeRgba].
  static const maxEncodeSize = 100;

  /// The maximum number of bytes in a ThumbHash.
  static const maxLength = codec.maxHashLength;

  /// Whether encoding and decoding run native code: `true` everywhere but
  /// on the web.
  static bool get isNative => codec.isNativeCodec;

  /// Returns whether [bytes] is a valid ThumbHash.
  static bool isValid(List<int> bytes) {
    try {
      HashHeader.parse(bytes);
      return true;
    } on FormatException {
      return false;
    }
  }

  /// Encodes the image provided by [imageProvider], e.g. a [NetworkImage],
  /// [AssetImage], [FileImage] or [MemoryImage].
  ///
  /// The engine decodes the image directly at a size of at most
  /// [maxEncodeSize] pixels, so encoding even a very large image is cheap.
  ///
  /// Completes with the error of [imageProvider] if the image fails to load.
  static Future<ThumbHash> encode(ImageProvider imageProvider) async {
    final image = await _resolve(
      ResizeImage(
        imageProvider,
        width: maxEncodeSize,
        height: maxEncodeSize,
        policy: ResizeImagePolicy.fit,
      ),
    );
    try {
      return await encodeImage(image);
    } finally {
      image.dispose();
    }
  }

  /// Encodes [image], downscaling it first if it is larger than
  /// [maxEncodeSize] pixels.
  ///
  /// The caller remains responsible for disposing [image].
  static Future<ThumbHash> encodeImage(ui.Image image) async {
    final scaled = image.width > maxEncodeSize || image.height > maxEncodeSize
        ? await _downscale(image)
        : null;
    final source = scaled?.image ?? image;
    try {
      final data = await source.toByteData(
        format: ui.ImageByteFormat.rawStraightRgba,
      );
      if (data == null) {
        throw StateError('Could not read the pixels of $source.');
      }

      return ThumbHash.encodeRgba(
        source.width,
        source.height,
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      );
    } finally {
      // On the web, the image may reference the picture until it is gone.
      scaled?.image.dispose();
      scaled?.picture.dispose();
    }
  }

  final Uint8List _bytes;

  /// Parsed on first use: the bytes are always valid.
  late final HashHeader _header = HashHeader.parse(_bytes);

  /// The bytes of the hash, which cannot be modified.
  Uint8List get bytes => _bytes.asUnmodifiableView();

  /// Whether the original image has transparent pixels.
  bool get hasAlpha => _header.hasAlpha;

  /// The approximate aspect ratio (width / height) of the original image.
  ///
  /// Useful to size the placeholder, e.g. with an `AspectRatio` widget.
  double get aspectRatio => _header.aspectRatio;

  /// The average color of the image, which is a good background to show
  /// before the placeholder is decoded.
  late final Color averageColor = () {
    final (:red, :green, :blue, :alpha) = _header.averageRgba;

    return Color.from(alpha: alpha, red: red, green: green, blue: blue);
  }();

  /// Returns the base64 encoding of the hash, the usual way to store it.
  String toBase64() => base64.encode(_bytes);

  /// Decodes the placeholder to RGBA pixels.
  ///
  /// The larger side of the image is 32 pixels and its aspect ratio
  /// matches [aspectRatio]: placeholders are smooth, so Flutter can scale
  /// them up without visible artifacts. RGB is premultiplied by alpha if
  /// [premultiplied] is `true`.
  ///
  /// Runs synchronously and takes a few microseconds.
  ThumbHashPixels toPixels({bool premultiplied = false}) {
    final (:width, :height) = _header.decodedSize;

    return ThumbHashPixels._(
      width: width,
      height: height,
      rgba: codec.decodeRgba(_bytes, _header, premultiplied: premultiplied),
      premultiplied: premultiplied,
    );
  }

  /// Decodes the placeholder to an image, see [toPixels].
  ///
  /// To display the placeholder, use a `ThumbHashImage` or a
  /// `ThumbHashPlaceholder` instead.
  Future<ui.Image> toImage() {
    final pixels = toPixels(premultiplied: true);
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      pixels.rgba,
      pixels.width,
      pixels.height,
      ui.PixelFormat.rgba8888,
      completer.complete,
    );

    return completer.future;
  }

  @override
  bool operator ==(Object other) =>
      other is ThumbHash && listEquals(other._bytes, _bytes);

  @override
  int get hashCode => Object.hashAll(_bytes);

  @override
  String toString() => 'ThumbHash(${toBase64()})';
}

/// A decoded ThumbHash: an RGBA image with 8 bits per channel.
@immutable
final class ThumbHashPixels {
  const ThumbHashPixels._({
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
  final Uint8List rgba;

  /// Whether RGB is premultiplied by alpha.
  final bool premultiplied;

  @override
  String toString() =>
      'ThumbHashPixels(${width}x$height, premultiplied: $premultiplied)';
}

Future<ui.Image> _resolve(ImageProvider imageProvider) {
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

/// Draws [image] scaled down to fit [ThumbHash.maxEncodeSize].
///
/// The caller must dispose both the image and the picture it is drawn from.
Future<({ui.Image image, ui.Picture picture})> _downscale(
  ui.Image image,
) async {
  final scale = ThumbHash.maxEncodeSize / math.max(image.width, image.height);
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
    return (image: await picture.toImage(width, height), picture: picture);
  } catch (_) {
    picture.dispose();
    rethrow;
  }
}
