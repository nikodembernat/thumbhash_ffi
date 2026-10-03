import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:thumbhash_ffi/thumbhash_ffi.dart';

void main() {
  runApp(const ThumbhashExampleApp());
}

/// The images shown by the example.
const exampleAssets = [
  'assets/flower.jpg',
  'assets/sunset.png',
  'assets/orb.png',
];

class ThumbhashExampleApp extends StatelessWidget {
  const ThumbhashExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'thumbhash_ffi',
      theme: ThemeData(colorSchemeSeed: Colors.deepPurple),
      darkTheme: ThemeData(
        colorSchemeSeed: Colors.deepPurple,
        brightness: Brightness.dark,
      ),
      home: const ExamplePage(),
    );
  }
}

class ExamplePage extends StatelessWidget {
  const ExamplePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('thumbhash_ffi'),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Center(
              child: Text(
                ThumbhashFFI.isNative ? 'Native codec' : 'Dart codec',
                key: const Key('codec'),
              ),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          for (final asset in exampleAssets) ...[
            ExampleCard(key: ValueKey(asset), asset: asset),
            const SizedBox(height: 16),
          ],
        ],
      ),
    );
  }
}

/// Encodes an asset to a ThumbHash and shows the placeholder next to the
/// original, as well as the placeholder fading into the original.
class ExampleCard extends StatefulWidget {
  const ExampleCard({super.key, required this.asset});

  final String asset;

  @override
  State<ExampleCard> createState() => _ExampleCardState();
}

class _ExampleCardState extends State<ExampleCard> {
  late final Future<_EncodeResult> _result = _encode();

  /// Changes to replay the fade in animation.
  var _loadCount = 0;

  Future<_EncodeResult> _encode() async {
    final stopwatch = Stopwatch()..start();
    final hash = await ThumbhashFFI.encode(AssetImage(widget.asset));
    return _EncodeResult(hash, stopwatch.elapsed);
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: FutureBuilder(
        future: _result,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Could not encode ${widget.asset}: ${snapshot.error}',
              ),
            );
          }
          final result = snapshot.data;
          if (result == null) {
            return const SizedBox(
              height: 200,
              child: Center(child: CircularProgressIndicator()),
            );
          }

          final hash = result.hash;
          final aspectRatio = ThumbhashFFI.approximateAspectRatio(hash);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: _Labeled(
                      label: 'Original',
                      child: AspectRatio(
                        aspectRatio: aspectRatio,
                        child: Image.asset(widget.asset, fit: BoxFit.cover),
                      ),
                    ),
                  ),
                  Expanded(
                    child: _Labeled(
                      label: 'ThumbHash',
                      child: AspectRatio(
                        aspectRatio: aspectRatio,
                        child: Image(
                          key: Key('placeholder ${widget.asset}'),
                          image: ThumbhashFfiImage(hash),
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: _Labeled(
                      label: 'Fade in',
                      child: AspectRatio(
                        aspectRatio: aspectRatio,
                        child: ThumbhashFfi(
                          key: ValueKey(_loadCount),
                          hash: hash,
                          image: _SlowImage(
                            AssetImage(widget.asset),
                            loadCount: _loadCount,
                          ),
                          fadeDuration: const Duration(milliseconds: 600),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              ListTile(
                title: SelectableText(
                  base64Encode(hash),
                  key: Key('hash ${widget.asset}'),
                  style: textTheme.bodyMedium?.copyWith(
                    fontFamily: 'monospace',
                  ),
                ),
                subtitle: Text(
                  '${hash.length} bytes, loaded and encoded in '
                  '${result.elapsed.inMilliseconds} ms',
                ),
                leading: CircleAvatar(
                  backgroundColor: ThumbhashFFI.averageColor(hash),
                ),
                trailing: IconButton(
                  tooltip: 'Replay',
                  icon: const Icon(Icons.replay),
                  onPressed: () => setState(() => _loadCount++),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _EncodeResult {
  const _EncodeResult(this.hash, this.elapsed);

  final Uint8List hash;
  final Duration elapsed;
}

class _Labeled extends StatelessWidget {
  const _Labeled({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Column(
        children: [
          child,
          const SizedBox(height: 4),
          Text(label, style: Theme.of(context).textTheme.labelMedium),
        ],
      ),
    );
  }
}

/// Simulates a slow network by delaying [image] by a second.
class _SlowImage extends ImageProvider<_SlowImage> {
  const _SlowImage(this.image, {required this.loadCount});

  final ImageProvider image;

  /// Part of the key, so that every replay loads the image again.
  final int loadCount;

  @override
  Future<_SlowImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(_SlowImage key, ImageDecoderCallback decode) {
    final completer = Completer<ImageInfo>();
    Future<void>.delayed(const Duration(seconds: 1), () {
      final stream = image.resolve(ImageConfiguration.empty);
      late final ImageStreamListener listener;
      listener = ImageStreamListener(
        (info, _) {
          stream.removeListener(listener);
          completer.complete(info);
        },
        onError: (error, stackTrace) {
          stream.removeListener(listener);
          completer.completeError(error, stackTrace);
        },
      );
      stream.addListener(listener);
    });
    return OneFrameImageStreamCompleter(completer.future);
  }

  @override
  bool operator ==(Object other) =>
      other is _SlowImage &&
      other.image == image &&
      other.loadCount == loadCount;

  @override
  int get hashCode => Object.hash(image, loadCount);
}
