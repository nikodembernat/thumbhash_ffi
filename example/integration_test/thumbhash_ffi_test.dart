import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:thumbhash_ffi/thumbhash_ffi.dart';
import 'package:thumbhash_ffi_example/main.dart';

/// The ThumbHash of `assets/flower.jpg`, computed by the reference
/// implementation.
const _flowerHash = 'k0oGLQaSVsN0BVhX2oq2Z5SQUQcZ';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  test('uses the native codec everywhere but on the web', () {
    expect(ThumbhashFFI.isNative, !kIsWeb);
  });

  test('encodes and decodes RGBA pixels', () {
    final reference = base64Decode(_flowerHash);
    final decoded = ThumbhashFFI.decodeRgba(reference);
    expect((decoded.width, decoded.height), (23, 32));

    final hash = ThumbhashFFI.encodeRgba(
      decoded.width,
      decoded.height,
      decoded.rgba,
    );
    expect(ThumbhashFFI.isValid(hash), isTrue);
    expect(ThumbhashFFI.approximateAspectRatio(hash), closeTo(5 / 7, 1e-6));
  });

  test('encodes assets', () async {
    final hashes = {
      for (final asset in exampleAssets)
        asset: await ThumbhashFFI.encode(AssetImage(asset)),
    };

    for (final hash in hashes.values) {
      expect(ThumbhashFFI.isValid(hash), isTrue);
      expect(hash.length, lessThanOrEqualTo(ThumbhashFFI.maxHashLength));
    }

    // Image decoders differ slightly between platforms, so the hash of the
    // JPEG photo may not exactly match the reference.
    final flower = hashes['assets/flower.jpg']!;
    final reference = base64Decode(_flowerHash);
    expect(
      ThumbhashFFI.approximateAspectRatio(flower),
      ThumbhashFFI.approximateAspectRatio(reference),
    );
    _expectColorClose(
      ThumbhashFFI.averageColor(flower),
      ThumbhashFFI.averageColor(reference),
    );

    // 16:9 landscape.
    expect(
      ThumbhashFFI.approximateAspectRatio(hashes['assets/sunset.png']!),
      closeTo(16 / 9, 0.1),
    );

    // The orb is surrounded by transparency.
    final orb = ThumbhashFFI.averageColor(hashes['assets/orb.png']!);
    expect(orb.a, inInclusiveRange(0.3, 0.8));
  });

  test('decodes to images', () async {
    final hash = base64Decode(_flowerHash);

    final small = await ThumbhashFFI.decode(hash);
    expect((small.width, small.height), (23, 32));
    small.dispose();

    final large = await ThumbhashFFI.decode(hash, width: 700, height: 1000);
    expect((large.width, large.height), (700, 1000));
    final pixels = await large.toByteData();
    expect(pixels!.lengthInBytes, 700 * 1000 * 4);
    large.dispose();
  });

  testWidgets('shows placeholders', (tester) async {
    await tester.pumpWidget(const ThumbhashExampleApp());
    expect(
      find.text(ThumbhashFFI.isNative ? 'Native codec' : 'Dart codec'),
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
