/// The constants defined by the Rust crate in `rust/src/lib.rs`, or null on
/// the web.
library;

export 'c_constants_web.dart' if (dart.library.ffi) 'c_constants_native.dart';
