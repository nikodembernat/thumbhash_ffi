import 'dart:ffi';
import 'dart:typed_data';

import 'package:thumbhash_ffi/src/ffi/thumbhash_ffi_bindings.g.dart'
    as bindings;
import 'package:thumbhash_ffi/src/hash_header.dart';

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
    hash.address,
  );
  _check(length);

  return hash.sublist(0, length);
}

/// Decodes a valid ThumbHash with the given [header] to an RGBA image of
/// `header.decodedSize`.
Uint8List decodeRgba(
  Uint8List hash,
  HashHeader header, {
  required bool premultiplied,
}) {
  final (:width, :height) = header.decodedSize;
  final rgba = Uint8List(width * height * 4);
  _check(
    bindings.thumbhash_decode(
      hash.address,
      hash.length,
      width,
      height,
      premultiplied ? bindings.THUMBHASH_DECODE_PREMULTIPLIED : 0,
      rgba.address,
    ),
  );

  return rgba;
}

/// Hashes are validated before they reach the native code, so any error is
/// a bug.
void _check(int result) {
  if (result < 0) {
    throw StateError(switch (result) {
      bindings.THUMBHASH_ERROR_INVALID_ARGUMENT => 'Invalid argument.',
      bindings.THUMBHASH_ERROR_INVALID_HASH => 'Invalid ThumbHash.',
      bindings.THUMBHASH_ERROR_OUT_OF_MEMORY => 'Out of memory.',
      _ => 'Unknown ThumbHash error $result.',
    });
  }
}
