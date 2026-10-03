import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:thumbhash_ffi/src/codec/codec_dart.dart' as dart_codec;
import 'package:thumbhash_ffi/thumbhash_ffi.dart';

import 'src/matchers.dart';
import 'src/patterns.dart';
import 'src/reference_fixtures.dart';

typedef _Codec = ({
  String name,
  int maxHashDifferences,
  Uint8List Function(int width, int height, Uint8List rgba) encode,
  Uint8List Function(Uint8List hash, int width, int height, bool premultiplied)
  decode,
});

/// How many hash values may be off by one compared to the reference.
///
/// The C implementation uses single precision floats like the reference, but
/// sums in a different order, and `cosf` differs slightly between platforms. The Dart implementation uses double precision:
/// degenerate images (e.g. 1 pixel wide) have many coefficients that are
/// exactly 0.5 after normalization, where the rounding direction depends on
/// the sign of the floating point error of `cos(pi / 2)`.
const _maxSinglePrecisionDifferences = 6;
const _maxDoublePrecisionDifferences = 16;

void main() {
  final codecs = <_Codec>[
    (
      name: ThumbhashFFI.isNative ? 'native codec' : 'web codec',
      maxHashDifferences: ThumbhashFFI.isNative
          ? _maxSinglePrecisionDifferences
          : _maxDoublePrecisionDifferences,
      encode: ThumbhashFFI.encodeRgba,
      decode: (hash, width, height, premultiplied) => ThumbhashFFI.decodeRgba(
        hash,
        width: width,
        height: height,
        premultiplied: premultiplied,
      ).rgba,
    ),
    // The Dart port runs on the web; test it everywhere.
    if (ThumbhashFFI.isNative)
      (
        name: 'Dart codec',
        maxHashDifferences: _maxDoublePrecisionDifferences,
        encode: dart_codec.encodeRgba,
        decode: (hash, width, height, premultiplied) => dart_codec.decodeRgba(
          hash,
          width,
          height,
          premultiplied: premultiplied,
        ),
      ),
  ];

  test('patterns match the reference generator', () {
    for (final fixture in referenceFixtures) {
      final rgba = patternRgba(fixture.name);
      expect(rgba.length, fixture.width * fixture.height * 4);
      expect(fnv1a(rgba), fixture.inputChecksum, reason: fixture.name);
    }
  });

  for (final codec in codecs) {
    group(codec.name, () {
      for (final fixture in referenceFixtures) {
        test('encodes ${fixture.name} like the reference', () {
          final hash = codec.encode(
            fixture.width,
            fixture.height,
            patternRgba(fixture.name),
          );
          expectHashClose(
            hash,
            base64Decode(fixture.hashBase64),
            maxDifferences: codec.maxHashDifferences,
          );
        });

        test('decodes ${fixture.name} like the reference', () {
          final rgba = codec.decode(
            base64Decode(fixture.hashBase64),
            fixture.decodedWidth,
            fixture.decodedHeight,
            false,
          );
          expectBytesClose(rgba, base64Decode(fixture.decodedBase64));
        });

        test('decodes ${fixture.name} premultiplied', () {
          final hash = base64Decode(fixture.hashBase64);
          final (width, height) = (fixture.decodedWidth, fixture.decodedHeight);
          final straight = codec.decode(hash, width, height, false);
          final premultiplied = codec.decode(hash, width, height, true);
          final expected = Uint8List.fromList([
            for (var i = 0; i < straight.length; i++)
              if (i % 4 == 3)
                straight[i]
              else
                straight[i] * straight[i - i % 4 + 3] ~/ 255,
          ]);
          // Both are rounded down from the exact values.
          expectBytesClose(premultiplied, expected, tolerance: 2);
        });
      }
    });
  }

  group('ThumbhashFFI', () {
    for (final fixture in referenceFixtures) {
      final hash = base64Decode(fixture.hashBase64);

      test('inspects ${fixture.name} like the reference', () {
        expect(ThumbhashFFI.isValid(hash), isTrue);
        expect(
          ThumbhashFFI.approximateAspectRatio(hash),
          closeTo(fixture.aspectRatio, 1e-6),
        );
        expect(ThumbhashFFI.decodedSize(hash), (
          width: fixture.decodedWidth,
          height: fixture.decodedHeight,
        ));

        final color = ThumbhashFFI.averageColor(hash);
        final (r, g, b, a) = fixture.averageRgba;
        expect(color.r, closeTo(r, 1e-6));
        expect(color.g, closeTo(g, 1e-6));
        expect(color.b, closeTo(b, 1e-6));
        expect(color.a, closeTo(a, 1e-6));
      });
    }

    test('decodes at the default size', () {
      for (final fixture in referenceFixtures) {
        final image = ThumbhashFFI.decodeRgba(base64Decode(fixture.hashBase64));
        expect(image.width, fixture.decodedWidth);
        expect(image.height, fixture.decodedHeight);
        expect(image.premultiplied, isFalse);
        expect(image.rgba.length, image.width * image.height * 4);
      }
    });

    test('decodes at a custom size', () {
      final flower = referenceFixtures.last;
      expect(flower.name, 'flower');
      final hash = base64Decode(flower.hashBase64);
      final ratio = ThumbhashFFI.approximateAspectRatio(hash);

      final both = ThumbhashFFI.decodeRgba(hash, width: 300, height: 200);
      expect((both.width, both.height), (300, 200));
      expect(both.rgba.length, 300 * 200 * 4);

      final byWidth = ThumbhashFFI.decodeRgba(hash, width: 100);
      expect((byWidth.width, byWidth.height), (100, (100 / ratio).round()));

      final byHeight = ThumbhashFFI.decodeRgba(hash, height: 70);
      expect((byHeight.width, byHeight.height), ((70 * ratio).round(), 70));

      // Rendering at the default size explicitly yields the same pixels.
      final defaultSize = ThumbhashFFI.decodedSize(hash);
      expect(
        ThumbhashFFI.decodeRgba(
          hash,
          width: defaultSize.width,
          height: defaultSize.height,
        ).rgba,
        ThumbhashFFI.decodeRgba(hash).rgba,
      );
    });

    test('a larger rendering is a smooth upscale of the default one', () {
      final hash = base64Decode(referenceFixtures.first.hashBase64);
      final small = ThumbhashFFI.decodeRgba(hash, width: 32, height: 32);
      final large = ThumbhashFFI.decodeRgba(hash, width: 64, height: 64);
      // Pixel (x, y) of the small image is centered between pixels (2x, 2y)
      // and (2x + 1, 2y + 1) of the large one.
      for (var y = 0; y < 32; y++) {
        for (var x = 0; x < 32; x++) {
          for (var c = 0; c < 4; c++) {
            final value = small.rgba[(y * 32 + x) * 4 + c];
            final neighbor = large.rgba[(2 * y * 64 + 2 * x) * 4 + c];
            expect((value - neighbor).abs(), lessThanOrEqualTo(12));
          }
        }
      }
    });

    test('round trips through encoding', () {
      for (final fixture in referenceFixtures) {
        final hash = base64Decode(fixture.hashBase64);
        final decoded = ThumbhashFFI.decodeRgba(hash);
        final reencoded = ThumbhashFFI.encodeRgba(
          decoded.width,
          decoded.height,
          decoded.rgba,
        );
        expect(ThumbhashFFI.isValid(reencoded), isTrue);
        expect(
          ThumbhashFFI.approximateAspectRatio(reencoded),
          ThumbhashFFI.approximateAspectRatio(hash),
          reason: fixture.name,
        );
      }
    });

    test('hashes are at most maxHashLength bytes long', () {
      for (final fixture in referenceFixtures) {
        final hash = ThumbhashFFI.encodeRgba(
          fixture.width,
          fixture.height,
          patternRgba(fixture.name),
        );
        expect(hash.length, lessThanOrEqualTo(ThumbhashFFI.maxHashLength));
      }
    });

    test('accepts views into larger buffers', () {
      final fixture = referenceFixtures.first;
      final rgba = patternRgba(fixture.name);
      final buffer = Uint8List(rgba.length + 16)..setAll(8, rgba);
      final view = Uint8List.sublistView(buffer, 8, 8 + rgba.length);
      expect(
        ThumbhashFFI.encodeRgba(fixture.width, fixture.height, view),
        ThumbhashFFI.encodeRgba(fixture.width, fixture.height, rgba),
      );

      final hash = base64Decode(fixture.hashBase64);
      final hashBuffer = Uint8List(hash.length + 3)..setAll(3, hash);
      expect(
        ThumbhashFFI.decodeRgba(Uint8List.sublistView(hashBuffer, 3)).rgba,
        ThumbhashFFI.decodeRgba(hash).rgba,
      );
    });

    test('rejects invalid encoding arguments', () {
      expect(
        () => ThumbhashFFI.encodeRgba(0, 1, Uint8List(0)),
        throwsRangeError,
      );
      expect(
        () => ThumbhashFFI.encodeRgba(101, 1, Uint8List(101 * 4)),
        throwsRangeError,
      );
      expect(
        () => ThumbhashFFI.encodeRgba(1, 101, Uint8List(101 * 4)),
        throwsRangeError,
      );
      expect(
        () => ThumbhashFFI.encodeRgba(2, 2, Uint8List(15)),
        throwsArgumentError,
      );
    });

    test('rejects invalid decoding sizes', () {
      final hash = base64Decode(referenceFixtures.first.hashBase64);
      expect(
        () => ThumbhashFFI.decodeRgba(hash, width: 0, height: 10),
        throwsRangeError,
      );
      expect(
        () => ThumbhashFFI.decodeRgba(hash, width: 10, height: 4097),
        throwsRangeError,
      );
    });

    test('rejects invalid hashes', () {
      final valid = base64Decode(referenceFixtures.first.hashBase64);
      final invalid = <String, Uint8List>{
        'empty': Uint8List(0),
        'too short': Uint8List(4),
        'truncated': valid.sublist(0, valid.length - 1),
        'zero luminance components': Uint8List.fromList(valid)..[3] &= ~7,
        'truncated alpha': Uint8List.fromList([0, 0, 0x80, 3, 0]),
      };
      for (final MapEntry(key: name, value: hash) in invalid.entries) {
        expect(ThumbhashFFI.isValid(hash), isFalse, reason: name);
        for (final operation in <void Function()>[
          () => ThumbhashFFI.decodeRgba(hash),
          () => ThumbhashFFI.decodeRgba(hash, width: 8, height: 8),
          () => ThumbhashFFI.approximateAspectRatio(hash),
          () => ThumbhashFFI.averageColor(hash),
          () => ThumbhashFFI.decodedSize(hash),
        ]) {
          expect(
            operation,
            throwsA(isA<ThumbhashFFIException>()),
            reason: name,
          );
        }
      }
    });

    test('ignores trailing bytes', () {
      final hash = base64Decode(referenceFixtures.first.hashBase64);
      final padded = Uint8List(hash.length + 4)..setAll(0, hash);
      expect(ThumbhashFFI.isValid(padded), isTrue);
      expect(
        ThumbhashFFI.decodeRgba(padded).rgba,
        ThumbhashFFI.decodeRgba(hash).rgba,
      );
    });
  });
}
