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

## Usage

```yaml
dependencies:
  thumbhash_ffi: ^0.1.0
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

## Performance

Verified against the reference Rust implementation and available Dart implementations. 
In comparison with the reference Rust implementation, this package is 30
times (encoding) and 8 times (decoding) faster, and 3–9 times faster than pure Dart implementations. 

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

- [ThumbHash](https://github.com/evanw/thumbhash) by Evan Wallace.
- [blurhash_ffi](https://pub.dev/packages/blurhash_ffi), whose API this
  package is heavily based on.
- The flower photo in `example/assets` and `test/assets` comes from the
  ThumbHash repository.
