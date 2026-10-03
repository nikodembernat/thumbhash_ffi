## 1.0.0

* Initial release.
* C implementation of ThumbHash, ported from the reference Rust
  implementation, compiled with build hooks for Android, iOS, Linux, macOS
  and Windows.
* Pure Dart implementation for the web.
* `ThumbhashFFI` to encode `ImageProvider`s, `ui.Image`s and RGBA pixels, and
  to decode hashes to `ui.Image`s or RGBA pixels at any size.
* `ThumbhashFfiImage`, `ThumbhashTheImage` and the `ThumbhashFfi` widget.
