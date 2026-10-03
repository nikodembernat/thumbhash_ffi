/// ThumbHash image placeholders for Flutter.
///
/// * [ThumbHash] encodes images to hashes and decodes hashes.
/// * [ThumbHashPlaceholder] shows a hash while an image loads.
/// * [ThumbHashImage] is an [ImageProvider] that decodes a hash.
/// * [ThumbHashPreviewImage] is an [ImageProvider] that shows the ThumbHash
///   placeholder of another image.
///
/// Uses the reference Rust implementation through `dart:ffi`, and an
/// equivalent Dart implementation on the web.
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
