## 0.1.0

* Initial release.
* C port of the reference ThumbHash implementation, compiled with build hooks
  for Android, iOS, Linux, macOS and Windows, and an equivalent pure Dart
  implementation on the web.
* `ThumbHash`, an immutable, validated value type to encode `ImageProvider`s,
  `ui.Image`s and RGBA pixels, decode to `ui.Image`s or RGBA pixels, and read
  the average color and aspect ratio.
* `ThumbHashPlaceholder`, `ThumbHashImage` and `ThumbHashPreviewImage`.
