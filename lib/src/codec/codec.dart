/// The ThumbHash codec backend: the C implementation on platforms that
/// support `dart:ffi`, and an equivalent pure Dart implementation on the web.
library;

export 'codec_dart.dart' if (dart.library.ffi) 'codec_native.dart';
