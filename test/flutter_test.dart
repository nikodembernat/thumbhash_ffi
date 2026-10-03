import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thumbhash_ffi/thumbhash_ffi.dart';

import 'src/matchers.dart';
import 'src/reference_fixtures.dart';

final _flower = ThumbHash.fromBase64(
  referenceFixtures.singleWhere((f) => f.name == 'flower').hashBase64,
);
final _alpha = ThumbHash.fromBase64(
  referenceFixtures.singleWhere((f) => f.name == 'circle_alpha').hashBase64,
);

Future<ui.Image> _imageFromPixels(Uint8List rgba, int width, int height) {
  final completer = Completer<ui.Image>();
  ui.decodeImageFromPixels(
    rgba,
    width,
    height,
    ui.PixelFormat.rgba8888,
    completer.complete,
  );

  return completer.future;
}

Future<Uint8List> _readPixels(ui.Image image) async {
  final data = await image.toByteData();

  return data!.buffer.asUint8List();
}

Future<Uint8List> _flowerPng() async {
  final image = await _imageFromPixels(
    base64Decode(flowerRgbaBase64),
    flowerWidth,
    flowerHeight,
  );
  final png = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();

  return png!.buffer.asUint8List();
}

void main() {
  group('ThumbHash', () {
    testWidgets('encodes a ui.Image', (tester) async {
      await tester.runAsync(() async {
        final image = await _imageFromPixels(
          base64Decode(flowerRgbaBase64),
          flowerWidth,
          flowerHeight,
        );
        addTearDown(image.dispose);

        expectHashClose(
          (await ThumbHash.encodeImage(image)).bytes,
          _flower.bytes,
          maxDifferences: 16,
        );
      });
    });

    testWidgets('downscales large images before encoding', (tester) async {
      await tester.runAsync(() async {
        const width = 400, height = 250;
        final rgba = Uint8List(width * height * 4);
        for (var i = 0; i < rgba.length; i += 4) {
          rgba
            ..[i] = 200
            ..[i + 1] = (i ~/ 4) % width * 255 ~/ width
            ..[i + 2] = 40
            ..[i + 3] = 255;
        }
        final image = await _imageFromPixels(rgba, width, height);
        addTearDown(image.dispose);

        final hash = await ThumbHash.encodeImage(image);
        expect(hash.aspectRatio, closeTo(1.6, 0.2));
        final color = hash.averageColor;
        expect(color.r, closeTo(200 / 255, 0.05));
        expect(color.g, closeTo(0.5, 0.05));
        expect(color.b, closeTo(40 / 255, 0.05));
        expect(color.a, 1);
      });
    });

    testWidgets('encodes an ImageProvider', (tester) async {
      await tester.runAsync(() async {
        final hash = await ThumbHash.encode(MemoryImage(await _flowerPng()));
        expectHashClose(hash.bytes, _flower.bytes, maxDifferences: 16);
      });
    });

    testWidgets('forwards the error of a broken ImageProvider', (tester) async {
      await tester.runAsync(() async {
        await expectLater(
          ThumbHash.encode(MemoryImage(Uint8List.fromList([1, 2, 3]))),
          throwsException,
        );
      });
    });

    testWidgets('decodes to a ui.Image', (tester) async {
      await tester.runAsync(() async {
        for (final hash in [_flower, _alpha]) {
          final image = await hash.toImage();
          addTearDown(image.dispose);
          final pixels = hash.toPixels(premultiplied: true);
          expect((image.width, image.height), (pixels.width, pixels.height));

          // ui.Image pixels are premultiplied.
          expectBytesClose(await _readPixels(image), pixels.rgba);
        }
      });
    });
  });

  group('ThumbHashImage', () {
    test('compares hashes by value', () {
      expect(
        ThumbHashImage(_flower),
        ThumbHashImage(ThumbHash.fromBytes(_flower.bytes)),
      );
      expect(
        ThumbHashImage(_flower).hashCode,
        ThumbHashImage(ThumbHash.fromBytes(_flower.bytes)).hashCode,
      );
      expect(ThumbHashImage(_flower), isNot(ThumbHashImage(_alpha)));
      expect(ThumbHashImage(_flower), isNot(ThumbHashImage(_flower, scale: 2)));
    });

    testWidgets('renders the placeholder', (tester) async {
      final provider = ThumbHashImage(_flower);
      await _precache(tester, provider);
      await tester.pumpWidget(Image(image: provider));

      final image = tester.widget<RawImage>(find.byType(RawImage)).image!;
      expect((image.width, image.height), (23, 32));
    });
  });

  group('ThumbHashPreviewImage', () {
    testWidgets('renders the placeholder of an image', (tester) async {
      final png = await tester.runAsync(_flowerPng);

      final provider = ThumbHashPreviewImage(MemoryImage(png!));
      await _precache(tester, provider);
      await tester.pumpWidget(Image(image: provider));

      final rendered = tester.widget<RawImage>(find.byType(RawImage)).image!;
      expect((rendered.width, rendered.height), (23, 32));
    });
  });

  group('ThumbHashPlaceholder', () {
    testWidgets('shows the average color and the placeholder', (tester) async {
      // Decoding is asynchronous, keep it out of the fake async zone.
      await _precache(tester, ThumbHashImage(_flower));
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: SizedBox(
              width: 230,
              height: 320,
              child: ThumbHashPlaceholder(
                hash: _flower,
                semanticLabel: 'A flower',
              ),
            ),
          ),
        ),
      );

      expect(
        tester.widget<ColoredBox>(find.byType(ColoredBox)).color,
        _flower.averageColor,
      );
      expect(find.bySemanticsLabel('A flower'), findsOneWidget);
      expect(
        tester.widget<Image>(find.byType(Image)).image,
        ThumbHashImage(_flower),
      );
    });

    testWidgets('cross-fades to the image', (tester) async {
      await _precache(tester, ThumbHashImage(_flower));
      final image = await tester.runAsync(
        () => _imageFromPixels(Uint8List(4 * 4 * 4), 4, 4),
      );
      final provider = _ControlledImage();

      await tester.pumpWidget(
        SizedBox(
          width: 100,
          height: 100,
          child: ThumbHashPlaceholder(hash: _flower, image: provider),
        ),
      );
      List<double> opacities() => [
        for (final widget in tester.widgetList<AnimatedOpacity>(
          find.byType(AnimatedOpacity),
        ))
          widget.opacity,
      ];

      // The placeholder is visible, the image is not.
      expect(find.byType(Image), findsNWidgets(2));
      expect(opacities(), [1, 0]);

      provider.completer.complete(ImageInfo(image: image!));
      await tester.pumpAndSettle();
      expect(opacities(), [0, 1]);
    });

    testWidgets('keeps the placeholder if the image fails', (tester) async {
      await _precache(tester, ThumbHashImage(_flower));
      final provider = _ControlledImage();
      await tester.pumpWidget(
        SizedBox(
          width: 100,
          height: 100,
          child: ThumbHashPlaceholder(hash: _flower, image: provider),
        ),
      );

      provider.completer.completeError(Exception('Network error'));
      await tester.pumpAndSettle();
      expect(find.byType(AnimatedOpacity), findsNothing);
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is Image && widget.image == ThumbHashImage(_flower),
        ),
        findsOneWidget,
      );
    });
  });
}

/// Loads [provider] outside of the fake async zone of [tester], so that it
/// is already in the image cache when a widget needs it.
Future<void> _precache(WidgetTester tester, ImageProvider provider) async {
  await tester.pumpWidget(const SizedBox());
  await tester.runAsync(
    () => precacheImage(
      provider,
      tester.element(find.byType(SizedBox)),
      onError: (error, stackTrace) => fail('Could not load the image: $error'),
    ),
  );
}

/// An image that loads when the test completes [completer].
class _ControlledImage extends ImageProvider<_ControlledImage> {
  final completer = Completer<ImageInfo>();

  @override
  Future<_ControlledImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(
    _ControlledImage key,
    ImageDecoderCallback decode,
  ) => OneFrameImageStreamCompleter(completer.future);
}
