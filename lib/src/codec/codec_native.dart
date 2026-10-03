import 'dart:ffi';
import 'dart:typed_data';

import 'package:thumbhash_ffi/src/ffi/thumbhash_ffi_bindings.g.dart'
    as bindings;

/// Whether the codec is backed by native code.
const isNativeCodec = true;

/// The maximum number of bytes in a ThumbHash.
const maxHashLength = bindings.THUMBHASH_MAX_HASH_LENGTH;

/// Encodes an RGBA image to a ThumbHash. The arguments must be validated.
Uint8List encodeRgba(int width, int height, Uint8List rgba) {
  final hash = Uint8List(maxHashLength);
  // Typed data is passed to leaf calls without copying.
  final length = bindings.thumbhash_encode(
    width,
    height,
    rgba.address,
    rgba.length,
    hash.address,
  );
  _check(length);

  return hash.sublist(0, length);
}

/// Decodes a valid ThumbHash to an RGBA image whose larger side is 32px.
({int width, int height, Uint8List rgba}) decodeRgba(
  Uint8List hash, {
  required bool premultiplied,
}) {
  final rgba = Uint8List(bindings.THUMBHASH_MAX_DECODED_LENGTH);
  final size = Uint32List(2);
  _check(
    bindings.thumbhash_decode(
      hash.address,
      hash.length,
      premultiplied,
      rgba.address,
      size.address,
    ),
  );
  final [width, height] = size;

  return (
    width: width,
    height: height,
    rgba: rgba.sublist(0, width * height * 4),
  );
}

/// Returns the average color of a valid ThumbHash as (red, green, blue,
/// alpha) in range [0, 1].
({double red, double green, double blue, double alpha}) averageRgba(
  Uint8List hash,
) {
  final rgba = Float32List(4);
  _check(
    bindings.thumbhash_average_rgba(hash.address, hash.length, rgba.address),
  );
  final [red, green, blue, alpha] = rgba;

  return (red: red, green: green, blue: blue, alpha: alpha);
}

/// Returns the approximate aspect ratio of a valid ThumbHash.
double approximateAspectRatio(Uint8List hash) {
  final ratio = bindings.thumbhash_approximate_aspect_ratio(
    hash.address,
    hash.length,
  );
  _check(ratio < 0 ? ratio.toInt() : bindings.THUMBHASH_OK);

  return ratio;
}

/// Hashes are validated before they reach the native code, so any error is
/// a bug.
void _check(int result) {
  if (result < 0) {
    throw StateError(switch (result) {
      bindings.THUMBHASH_ERROR_INVALID_ARGUMENT => 'Invalid argument.',
      bindings.THUMBHASH_ERROR_INVALID_HASH => 'Invalid ThumbHash.',
      bindings.THUMBHASH_ERROR_PANIC =>
        'The ThumbHash implementation panicked.',
      _ => 'Unknown ThumbHash error $result.',
    });
  }
}
