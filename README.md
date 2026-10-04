# thumbhash_ffi

[![CI](https://github.com/nikodembernat/thumbhash_ffi/actions/workflows/ci.yml/badge.svg)](https://github.com/nikodembernat/thumbhash_ffi/actions/workflows/ci.yml)

Fast [ThumbHash](https://evanw.github.io/thumbhash/) image placeholders for
Flutter. The codec is a C port of the
[reference Rust implementation](https://github.com/evanw/thumbhash/tree/main/rust),
bound with `dart:ffi`.

A ThumbHash stores a very compact (at most 25 bytes) representation of an
image that is rendered as a blurry placeholder while the actual image loads.
Compared to [BlurHash](https://blurha.sh), it encodes more detail in the same
space, preserves the aspect ratio and supports transparency.

## Features

- Encode any `ImageProvider` (network, asset, file, memory) or `ui.Image`.
  Images are decoded by the engine straight to at most 100x100 pixels, so even
  huge photos are cheap to encode.
- Show placeholders with the `ThumbHashPlaceholder` widget, which cross-fades
  to the actual image, or the `ThumbHashImage` image provider.
- Read the average color and the aspect ratio of a hash without decoding it.
- Supports Android, iOS, Linux, macOS, Windows and the web. On the web, where
  `dart:ffi` is not available, an equivalent pure Dart implementation is used.
- Built with [build hooks](https://docs.flutter.dev/platform-integration/bind-native-code):
  no platform-specific build files, no CocoaPods, and nothing to set up in
  your app.

## Usage

```yaml
dependencies:
  thumbhash_ffi: ^1.0.0
```

### Encoding

Compute the hash when an image is uploaded and store it next to the image,
usually as base64:

```dart
import 'package:thumbhash_ffi/thumbhash_ffi.dart';

final hash = await ThumbHash.encode(FileImage(file));
final String stored = hash.toBase64(); // e.g. k0oGLQaSVsN0BVhX2oq2Z5SQUQcZ
```

If you already have the pixels (RGBA, not premultiplied, at most 100x100),
encode them synchronously:

```dart
final hash = ThumbHash.encodeRgba(width, height, rgba);
```

### Displaying placeholders

```dart
final hash = ThumbHash.fromBase64(stored);

AspectRatio(
  aspectRatio: hash.aspectRatio,
  child: ThumbHashPlaceholder(
    hash: hash,
    image: NetworkImage('https://example.com/photo.jpg'),
  ),
)
```

`ThumbHashPlaceholder` shows the average color of the hash, then the decoded
placeholder, then cross-fades to the image once it has loaded. If the image
fails to load, the placeholder stays (or pass an `errorBuilder`).

`ThumbHashImage` is an `ImageProvider`, so it works anywhere an image does,
for example as the placeholder of a `FadeInImage`:

```dart
FadeInImage(
  placeholder: ThumbHashImage(hash),
  image: NetworkImage('https://example.com/photo.jpg'),
  fit: BoxFit.cover,
)
```

To see what the placeholder of any image looks like,
`ThumbHashPreviewImage` encodes and decodes it in one step:

```dart
Image(image: ThumbHashPreviewImage(AssetImage('assets/photo.jpg')))
```

### Decoding and inspecting

```dart
final ui.Image image = await hash.toImage();      // 32px on the larger side
final ThumbHashPixels pixels = hash.toPixels();   // raw RGBA, synchronously

final Color color = hash.averageColor;            // no decoding needed
final double aspectRatio = hash.aspectRatio;
final bool transparent = hash.hasAlpha;
```

`ThumbHash` is an immutable value: hashes with the same bytes are equal, so
they make good keys and `ThumbHashImage`s are cached correctly. The
constructors validate their input and throw a `FormatException` for malformed
hashes; `ThumbHash.isValid` checks bytes without throwing.

## Differences from blurhash_ffi

The API follows [`blurhash_ffi`](https://pub.dev/packages/blurhash_ffi), with
these changes:

- **A `ThumbHash` value type instead of raw strings or bytes.** It is
  validated once, when created, so decoding never fails, and it compares by
  value. Its methods replace the static `BlurhashFFI.encode`/`decode`.
- **Names that differ by more than case.** `BlurhashFFI` (the codec),
  `BlurhashFfi` (the widget) and `BlurhashFfiImage` are now `ThumbHash`,
  `ThumbHashPlaceholder` and `ThumbHashImage`. `BlurhashTheImage` is now
  `ThumbHashPreviewImage`.
- **The widget takes any `ImageProvider`** rather than a URL and HTTP headers,
  and cross-fades so that the placeholder doesn't show through transparent
  images.
- **No decode size parameters.** A ThumbHash knows its aspect ratio, so the
  placeholder is always decoded at the reference size and scaled by Flutter.
- **Standard exceptions.** Malformed hashes throw a `FormatException`, invalid
  arguments an `ArgumentError`, and image loading errors are forwarded as is,
  rather than everything being wrapped in an `Error` subclass.
- **No background isolate to manage.** Encoding a 100x100 image and decoding a
  placeholder take microseconds, so there is no `free()` to call.
- **No global logging configuration.**
- **Correct colors for transparent images**: pixels are read without
  premultiplied alpha, as ThumbHash expects.
- **Images are downscaled before encoding.** Full-size images aren't encoded,
  which would be slow without improving the result.

## Performance

On a 2.1 GHz x64 server core, in a release build, encoding a 100x100 image
takes about 35 µs and decoding a placeholder about 4–6 µs, so the
synchronous methods are safe to call on the UI isolate. That is about 30
times (encoding) and 8 times (decoding) faster than the reference Rust
implementation, and 3–9 times faster than pure Dart implementations. How:

- The forward and inverse DCT are evaluated separably, a channel and a
  component at a time, so the inner loops run over contiguous memory and
  the compiler vectorizes them.
- The cosine tables of the last few image sizes are cached per thread.
- Per-pixel divisions are replaced by lookup tables, and the average color
  (only needed for transparent images) is skipped for opaque ones.
- Typed data is passed to C without copying, through leaf calls, and the
  header of a `ThumbHash` (average color, aspect ratio) is parsed once.

The C code otherwise follows the reference implementation: single precision,
the same order of operations and the same quantization. Hashes match the
reference byte for byte in most cases; when an intermediate value lands right
on a rounding boundary, a coefficient may differ by one step, which is not
visible.

Turning a hash into a `ui.Image` is dominated by the engine (creating and
uploading the image), so `ThumbHashImage`s are cached by the image cache like
any other image.

## How it works

The C library in `src/` is compiled for the target platform by the build hook
in `hook/build.dart` with
[`native_toolchain_c`](https://pub.dev/packages/native_toolchain_c), and
bundled with the app as a code asset. The Dart bindings in
`lib/src/ffi/thumbhash_ffi_bindings.g.dart` are generated by
[`ffigen`](https://pub.dev/packages/ffigen) and resolved with `@Native`,
without any platform-specific loading code.

On iOS and macOS, the library is embedded as a framework by the Flutter tool,
which works with Swift Package Manager and does not need CocoaPods. Building
needs the toolchains Flutter requires anyway (Android NDK, Xcode, clang on
Linux, Visual Studio on Windows).

## Development

```sh
flutter test                   # native (C) and Dart codecs
flutter test --platform chrome # web codec
dart run ffigen                # regenerate the bindings after changing the header

cd example
flutter test integration_test  # on a device, a simulator or the desktop
```

The test fixtures in `test/src/reference_fixtures.dart` are generated with the
reference Rust implementation (the `thumbhash` crate):

```sh
cargo run --release --manifest-path tool/reference_generator/Cargo.toml \
  > test/src/reference_fixtures.dart && dart format test/src
```

## Credits

- [ThumbHash](https://github.com/evanw/thumbhash) by Evan Wallace (MIT).
- [blurhash_ffi](https://pub.dev/packages/blurhash_ffi), whose API this
  package is based on.
- The flower photo in `example/assets` and `test/assets` comes from the
  ThumbHash repository.
