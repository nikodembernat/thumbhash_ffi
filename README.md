# thumbhash_ffi

[![CI](https://github.com/nikodembernat/thumbhash_ffi/actions/workflows/ci.yml/badge.svg)](https://github.com/nikodembernat/thumbhash_ffi/actions/workflows/ci.yml)

[ThumbHash](https://evanw.github.io/thumbhash/) image placeholders for
Flutter, using the
[reference Rust implementation](https://github.com/evanw/thumbhash/tree/main/rust)
through `dart:ffi`.

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
  your app besides Rust.

## Requirements

The Rust crate is compiled when your app is built, so
[install rustup](https://rustup.rs). The pinned Rust version and the targets
for all platforms are installed automatically on the first build.

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

## How it works

`rust/` contains a small crate that exposes the
[`thumbhash`](https://crates.io/crates/thumbhash) crate through a C ABI. It
validates its input and never lets a panic cross the FFI boundary. The build
hook in `hook/build.dart` compiles the crate for the target platform with
[`native_toolchain_rust`](https://pub.dev/packages/native_toolchain_rust) and
bundles it with the app. The Dart bindings in
`lib/src/ffi/thumbhash_ffi_bindings.g.dart` are generated by
[`ffigen`](https://pub.dev/packages/ffigen) from the header that
[`cbindgen`](https://github.com/mozilla/cbindgen) generates, and they are
resolved with `@Native`, without any platform-specific loading code. Typed data
is passed to the native code without copying, through leaf calls.

On iOS and macOS, the library is embedded as a framework by the Flutter tool,
which works with Swift Package Manager and does not need CocoaPods.

## Development

```sh
flutter test                   # native (Rust) and Dart codecs
flutter test --platform chrome # web codec

cd rust && cargo test          # the C ABI of the Rust crate

# After changing rust/src/lib.rs, regenerate the header and the bindings:
(cd rust && cbindgen --config cbindgen.toml --output thumbhash_ffi.h)
dart run ffigen

cd example
flutter test integration_test  # on a device, a simulator or the desktop
```

The test fixtures in `test/src/reference_fixtures.dart` are generated with the
`thumbhash` crate:

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
