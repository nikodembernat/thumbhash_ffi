/// The constants defined in `src/thumbhash_ffi.h`, or null on the web.
library;

export 'c_constants_web.dart' if (dart.library.ffi) 'c_constants_native.dart';
