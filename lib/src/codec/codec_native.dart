import 'dart:ffi';
import 'dart:typed_data';

import 'package:thumbhash_ffi/src/constants.dart';
import 'package:thumbhash_ffi/src/exception.dart';
import 'package:thumbhash_ffi/src/ffi/thumbhash_ffi_bindings.g.dart'
    as bindings;

/// Whether the codec is backed by native code.
const isNativeCodec = true;

/// Encodes an RGBA image to a ThumbHash. The arguments must be validated.
Uint8List encodeRgba(int width, int height, Uint8List rgba) {
  final hash = Uint8List(thumbhashMaxHashLength);
  // Typed data is passed to leaf calls without copying.
  final length = bindings.thumbhash_encode(
    width,
    height,
    rgba.address,
    hash.address,
  );
  _check(length, 'Could not encode the image');

  return hash.sublist(0, length);
}

/// Decodes a ThumbHash to an RGBA image. The size must be validated.
Uint8List decodeRgba(
  Uint8List hash,
  int width,
  int height, {
  required bool premultiplied,
}) {
  final rgba = Uint8List(width * height * 4);
  final result = bindings.thumbhash_decode(
    hash.address,
    hash.length,
    width,
    height,
    premultiplied ? bindings.THUMBHASH_DECODE_PREMULTIPLIED : 0,
    rgba.address,
  );
  _check(result, 'Could not decode the ThumbHash');

  return rgba;
}

void _check(int result, String message) {
  if (result >= 0) {
    return;
  }

  final reason = switch (result) {
    bindings.THUMBHASH_ERROR_INVALID_ARGUMENT => 'invalid argument',
    bindings.THUMBHASH_ERROR_INVALID_HASH => 'invalid hash',
    bindings.THUMBHASH_ERROR_OUT_OF_MEMORY => 'out of memory',
    _ => 'error code $result',
  };
  throw ThumbhashFFIException('$message: $reason.');
}
