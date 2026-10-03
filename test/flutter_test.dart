import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thumbhash_ffi/thumbhash_ffi.dart';

import 'src/matchers.dart';
import 'src/reference_fixtures.dart';

final _flower = referenceFixtures.singleWhere((f) => f.name == 'flower');
final _flowerHash = base64Decode(_flower.hashBase64);
final _alphaHash = base64Decode(
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

void main() {
  group('ThumbhashFFI', () {
    testWidgets('encodes a ui.Image', (tester) async {
      await tester.runAsync(() async {
        final image = await _imageFromPixels(
          base64Decode(flowerRgbaBase64),
          flowerWidth,
          flowerHeight,
        );
        addTearDown(image.dispose);

        expectHashClose(
          await ThumbhashFFI.encodeImage(image),
          _flowerHash,
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

        final hash = await ThumbhashFFI.encodeImage(image);
        expect(ThumbhashFFI.isValid(hash), isTrue);
        expect(ThumbhashFFI.approximateAspectRatio(hash), closeTo(1.6, 0.2));
        final color = ThumbhashFFI.averageColor(hash);
        expect(color.r, closeTo(200 / 255, 0.05));
        expect(color.g, closeTo(0.5, 0.05));
        expect(color.b, closeTo(40 / 255, 0.05));
        expect(color.a, 1);
      });
    });

    testWidgets('encodes an ImageProvider', (tester) async {
      await tester.runAsync(() async {
        final image = await _imageFromPixels(
          base64Decode(flowerRgbaBase64),
          flowerWidth,
          flowerHeight,
        );
        final png = await image.toByteData(format: ui.ImageByteFormat.png);
        image.dispose();

        final hash = await ThumbhashFFI.encode(
          MemoryImage(png!.buffer.asUint8List()),
        );
        expectHashClose(hash, _flowerHash, maxDifferences: 16);
      });
    });

    testWidgets('fails to encode a broken ImageProvider', (tester) async {
      await tester.runAsync(() async {
        await expectLater(
          ThumbhashFFI.encode(MemoryImage(Uint8List.fromList([1, 2, 3]))),
          throwsA(isA<ThumbhashFFIException>()),
        );
      });
    });

    testWidgets('decodes to a ui.Image', (tester) async {
      await tester.runAsync(() async {
        final image = await ThumbhashFFI.decode(_flowerHash);
        addTearDown(image.dispose);
        expect((image.width, image.height), (23, 32));

        // ui.Image pixels are premultiplied.
        expectBytesClose(
          await _readPixels(image),
          ThumbhashFFI.decodeRgba(_flowerHash, premultiplied: true).rgba,
        );
      });
    });

    testWidgets('decodes a hash with alpha to a ui.Image', (tester) async {
      await tester.runAsync(() async {
        final image = await ThumbhashFFI.decode(_alphaHash);
        addTearDown(image.dispose);

        expectBytesClose(
          await _readPixels(image),
          ThumbhashFFI.decodeRgba(_alphaHash, premultiplied: true).rgba,
        );
      });
    });

    testWidgets('decodes large images in the background', (tester) async {
      await tester.runAsync(() async {
        final image = await ThumbhashFFI.decode(_flowerHash, width: 600);
        addTearDown(image.dispose);
        expect((image.width, image.height), (600, 840));
        expectBytesClose(
          await _readPixels(image),
          ThumbhashFFI.decodeRgba(
            _flowerHash,
            width: 600,
            premultiplied: true,
          ).rgba,
        );
      });
    });

    test('fails to decode an invalid hash', () async {
      await expectLater(
        ThumbhashFFI.decode(Uint8List(3)),
        throwsA(isA<ThumbhashFFIException>()),
      );
    });
  });

  group('ThumbhashFfiImage', () {
    test('compares hashes by value', () {
      expect(
        ThumbhashFfiImage(_flowerHash),
        ThumbhashFfiImage(Uint8List.fromList(_flowerHash)),
      );
      expect(
        ThumbhashFfiImage(_flowerHash).hashCode,
        ThumbhashFfiImage(Uint8List.fromList(_flowerHash)).hashCode,
      );
      expect(
        ThumbhashFfiImage.fromBase64(_flower.hashBase64),
        ThumbhashFfiImage(_flowerHash),
      );
      expect(
        ThumbhashFfiImage(_flowerHash),
        isNot(ThumbhashFfiImage(_alphaHash)),
      );
      expect(
        ThumbhashFfiImage(_flowerHash),
        isNot(ThumbhashFfiImage(_flowerHash, decodingWidth: 64)),
      );
    });

    testWidgets('renders the placeholder', (tester) async {
      final provider = ThumbhashFfiImage(_flowerHash, decodingHeight: 64);
      await _precache(tester, provider);
      await tester.pumpWidget(Image(image: provider));

      final image = tester.widget<RawImage>(find.byType(RawImage)).image!;
      expect((image.width, image.height), (46, 64));
    });
  });

  group('ThumbhashTheImage', () {
    testWidgets('renders the placeholder of an image', (tester) async {
      final png = await tester.runAsync(() async {
        final image = await _imageFromPixels(
          base64Decode(flowerRgbaBase64),
          flowerWidth,
          flowerHeight,
        );
        final png = await image.toByteData(format: ui.ImageByteFormat.png);
        image.dispose();
        return png!.buffer.asUint8List();
      });

      final provider = ThumbhashTheImage(MemoryImage(png!));
      await _precache(tester, provider);
      await tester.pumpWidget(Image(image: provider));

      final rendered = tester.widget<RawImage>(find.byType(RawImage)).image!;
      expect((rendered.width, rendered.height), (23, 32));
    });
  });

  group('ThumbhashFfi', () {
    testWidgets('shows the average color and the placeholder', (tester) async {
      // Decoding is asynchronous, keep it out of the fake async zone.
      await _precache(tester, ThumbhashFfiImage(_flowerHash));
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: SizedBox(
              width: 230,
              height: 320,
              child: ThumbhashFfi(hash: _flowerHash, semanticLabel: 'A flower'),
            ),
          ),
        ),
      );

      expect(
        tester.widget<ColoredBox>(find.byType(ColoredBox)).color,
        ThumbhashFFI.averageColor(_flowerHash),
      );
      expect(find.bySemanticsLabel('A flower'), findsOneWidget);
      expect(
        tester.widget<Image>(find.byType(Image)).image,
        ThumbhashFfiImage(_flowerHash),
      );
    });

    testWidgets('fades in the image', (tester) async {
      await _precache(tester, ThumbhashFfiImage(_flowerHash));
      final image = await tester.runAsync(
        () => _imageFromPixels(Uint8List(4 * 4 * 4), 4, 4),
      );
      final provider = _ControlledImage();

      await tester.pumpWidget(
        SizedBox(
          width: 100,
          height: 100,
          child: ThumbhashFfi(hash: _flowerHash, image: provider),
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
      await _precache(tester, ThumbhashFfiImage(_flowerHash));
      final provider = _ControlledImage();
      await tester.pumpWidget(
        SizedBox(
          width: 100,
          height: 100,
          child: ThumbhashFfi(hash: _flowerHash, image: provider),
        ),
      );

      provider.completer.completeError(Exception('Network error'));
      await tester.pumpAndSettle();
      expect(find.byType(AnimatedOpacity), findsNothing);
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is Image && widget.image == ThumbhashFfiImage(_flowerHash),
        ),
        findsOneWidget,
      );
    });

    testWidgets('shows nothing for an invalid hash', (tester) async {
      await tester.pumpWidget(ThumbhashFfi(hash: Uint8List(2)));

      expect(find.byType(Image), findsNothing);
      expect(tester.takeException(), isNull);
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
