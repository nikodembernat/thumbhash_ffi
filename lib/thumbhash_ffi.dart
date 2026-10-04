/// ThumbHash image placeholders for Flutter.
///
/// * [ThumbHash] encodes images to hashes and decodes hashes.
/// * [ThumbHashPlaceholder] shows a hash while an image loads.
/// * [ThumbHashImage] is an [ImageProvider] that decodes a hash.
/// * [ThumbHashPreviewImage] is an [ImageProvider] that shows the ThumbHash
///   placeholder of another image.
///
/// The codec is a C port of the reference implementation, bound with
/// `dart:ffi` through build hooks. On the web, an equivalent Dart
/// implementation is used.
library;

import 'package:flutter/painting.dart';
import 'package:thumbhash_ffi/src/flutter/thumb_hash_image.dart';
import 'package:thumbhash_ffi/src/flutter/thumb_hash_placeholder.dart';
import 'package:thumbhash_ffi/src/flutter/thumb_hash_preview_image.dart';
import 'package:thumbhash_ffi/src/thumb_hash.dart';

export 'src/flutter/thumb_hash_image.dart';
export 'src/flutter/thumb_hash_placeholder.dart';
export 'src/flutter/thumb_hash_preview_image.dart';
export 'src/thumb_hash.dart';
