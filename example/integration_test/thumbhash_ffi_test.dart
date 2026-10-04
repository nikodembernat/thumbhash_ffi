import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:thumbhash_ffi/thumbhash_ffi.dart';
import 'package:thumbhash_ffi_example/main.dart';

/// The ThumbHash of `assets/flower.jpg`, computed by the reference
/// implementation.
const _flowerHash = 'k0oGLQaSVsN0BVhX2oq2Z5SQUQcZ';

/// The hash of the decoded [_flowerHash] placeholder and the average color of
/// [_flowerHash], computed by the reference implementation.
const _flowerRoundTripHash = 'k0oGNQiSVqN2BnhnqYq3Z5SAUQcY';
const _flowerAverageColor = Color.from(
  alpha: 1,
  red: 0.484127,
  green: 0.34126982,
  blue: 0.07936506,
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final reference = ThumbHash.fromBase64(_flowerHash);

  test('uses the native codec everywhere but on the web', () {
    expect(ThumbHash.isNative, !kIsWeb);
  });

  test('encodes and decodes RGBA pixels', () {
    final pixels = reference.toPixels();
    expect((pixels.width, pixels.height), (23, 32));

    final hash = ThumbHash.encodeRgba(pixels.width, pixels.height, pixels.rgba);
    expect(hash.aspectRatio, closeTo(5 / 7, 1e-6));
  });

  test('matches the reference implementation', () {
    final pixels = reference.toPixels();
    final roundTrip = ThumbHash.encodeRgba(
      pixels.width,
      pixels.height,
      pixels.rgba,
    );
    final expected = ThumbHash.fromBase64(_flowerRoundTripHash);
    expect(roundTrip.bytes.length, expected.bytes.length);
    expect(roundTrip.aspectRatio, expected.aspectRatio);
    _expectColorClose(roundTrip.averageColor, expected.averageColor);
    _expectColorClose(reference.averageColor, _flowerAverageColor);
  });

  test('encodes assets', () async {
    final hashes = {
      for (final asset in exampleAssets)
        asset: await ThumbHash.encode(AssetImage(asset)),
    };

    for (final hash in hashes.values) {
      expect(hash.bytes.length, lessThanOrEqualTo(ThumbHash.maxLength));
    }

    // Image decoders differ slightly between platforms, so the hash of the
    // JPEG photo may not exactly match the reference.
    final flower = hashes['assets/flower.jpg']!;
    expect(flower.aspectRatio, reference.aspectRatio);
    _expectColorClose(flower.averageColor, reference.averageColor);

    // 16:9 landscape.
    expect(hashes['assets/sunset.png']!.aspectRatio, closeTo(16 / 9, 0.1));

    // The orb is surrounded by transparency.
    final orb = hashes['assets/orb.png']!;
    expect(orb.hasAlpha, isTrue);
    expect(orb.averageColor.a, inInclusiveRange(0.3, 0.8));
  });

  test('decodes to images', () async {
    final image = await reference.toImage();
    expect((image.width, image.height), (23, 32));
    final pixels = await image.toByteData();
    expect(pixels!.lengthInBytes, 23 * 32 * 4);
    image.dispose();
  });

  testWidgets('shows placeholders', (tester) async {
    await tester.pumpWidget(const ThumbhashExampleApp());
    expect(
      find.text(ThumbHash.isNative ? 'Native codec' : 'Dart codec'),
      findsOneWidget,
    );

    for (final asset in exampleAssets) {
      await tester.scrollUntilVisible(
        find.byKey(ValueKey(asset)),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await _pumpUntilFound(tester, find.byKey(Key('placeholder $asset')));
      await _pumpUntilFound(tester, find.byKey(Key('hash $asset')));
    }

    // Let the fade in animations finish.
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}

void _expectColorClose(Color actual, Color expected) {
  expect(actual.r, closeTo(expected.r, 0.05));
  expect(actual.g, closeTo(expected.g, 0.05));
  expect(actual.b, closeTo(expected.b, 0.05));
  expect(actual.a, closeTo(expected.a, 0.05));
}

Future<void> _pumpUntilFound(WidgetTester tester, Finder finder) async {
  final timeout = DateTime.now().add(const Duration(seconds: 30));
  while (finder.evaluate().isEmpty) {
    if (DateTime.now().isAfter(timeout)) {
      fail('Timed out waiting for $finder');
    }
    await tester.pump(const Duration(milliseconds: 50));
  }
}
