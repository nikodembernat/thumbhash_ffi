/// Fast ThumbHash image placeholder encoder and decoder for Flutter.
///
/// The codec is written in C and bound with `dart:ffi` through build hooks.
/// On the web, an equivalent pure Dart implementation is used.
///
/// * [ThumbhashFFI] encodes images to hashes and decodes hashes to images.
/// * [ThumbhashFfiImage] is an [ImageProvider] that decodes a hash.
/// * [ThumbhashFfi] is a widget that shows a hash while an image loads.
/// * [ThumbhashTheImage] is an [ImageProvider] that shows the ThumbHash of
///   another image.
library;

import 'package:flutter/painting.dart';
import 'package:thumbhash_ffi/src/thumbhash_ffi.dart';
import 'package:thumbhash_ffi/src/widgets/thumbhash_ffi_image.dart';
import 'package:thumbhash_ffi/src/widgets/thumbhash_ffi_widget.dart';
import 'package:thumbhash_ffi/src/widgets/thumbhash_the_image.dart';

export 'src/exception.dart';
export 'src/thumbhash_ffi.dart';
export 'src/thumbhash_rgba.dart';
export 'src/widgets/thumbhash_ffi_image.dart';
export 'src/widgets/thumbhash_ffi_widget.dart';
export 'src/widgets/thumbhash_the_image.dart';
