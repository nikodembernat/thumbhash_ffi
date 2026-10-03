import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:thumbhash_ffi/src/thumbhash_ffi.dart';
import 'package:thumbhash_ffi/src/widgets/thumbhash_ffi_image.dart';

/// Displays a ThumbHash placeholder and, optionally, cross-fades to the
/// actual [image] once it has loaded.
///
/// ```dart
/// ThumbhashFfi(
///   hash: base64Decode('k0oGLQaSVsN0BVhX2oq2Z5SQUQcZ'),
///   image: NetworkImage(url),
/// )
/// ```
///
/// The widget expands to fill its constraints, so give it a size, e.g. with
/// a [SizedBox] or an [AspectRatio] (see [ThumbhashFFI.approximateAspectRatio]).
/// The average color of the hash is shown until the placeholder is decoded.
class ThumbhashFfi extends StatelessWidget {
  /// Creates a widget that displays the ThumbHash [hash].
  const ThumbhashFfi({
    super.key,
    required this.hash,
    this.image,
    this.fit = BoxFit.cover,
    this.alignment = Alignment.center,
    this.decodingWidth,
    this.decodingHeight,
    this.fadeDuration = const Duration(milliseconds: 300),
    this.fadeCurve = Curves.easeOut,
    this.errorBuilder,
    this.semanticLabel,
  });

  /// The ThumbHash to display as a placeholder.
  final Uint8List hash;

  /// The image to fade in over the placeholder once it has loaded.
  final ImageProvider? image;

  /// How to inscribe the placeholder and the [image] into the layout.
  final BoxFit fit;

  /// How to align the placeholder and the [image] within the layout.
  final AlignmentGeometry alignment;

  /// The width of the decoded placeholder, see [ThumbhashFFI.decode].
  final int? decodingWidth;

  /// The height of the decoded placeholder, see [ThumbhashFFI.decode].
  final int? decodingHeight;

  /// How long the cross-fade from the placeholder to the [image] lasts.
  final Duration fadeDuration;

  /// The curve of the cross-fade from the placeholder to the [image].
  final Curve fadeCurve;

  /// Builds the widget shown instead of the [image] if it fails to load.
  ///
  /// If null, the placeholder stays visible.
  final ImageErrorWidgetBuilder? errorBuilder;

  /// A semantic description of the [image].
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final image = this.image;
    final placeholder = ThumbhashFFI.isValid(hash)
        ? ColoredBox(
            color: ThumbhashFFI.averageColor(hash),
            child: Image(
              image: ThumbhashFfiImage(
                hash,
                decodingWidth: decodingWidth,
                decodingHeight: decodingHeight,
              ),
              fit: fit,
              alignment: alignment,
              gaplessPlayback: true,
              excludeFromSemantics: true,
            ),
          )
        : const SizedBox.expand();

    return Semantics(
      image: true,
      label: semanticLabel,
      child: image == null
          ? placeholder
          : Image(
              image: image,
              fit: fit,
              alignment: alignment,
              width: double.infinity,
              height: double.infinity,
              excludeFromSemantics: true,
              errorBuilder:
                  errorBuilder ?? (context, error, stackTrace) => placeholder,
              frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
                if (wasSynchronouslyLoaded) {
                  return child;
                }

                // Cross-fade, so that the placeholder does not show through
                // transparent images.
                final loaded = frame != null;
                return Stack(
                  alignment: Alignment.center,
                  fit: StackFit.expand,
                  children: [
                    AnimatedOpacity(
                      opacity: loaded ? 0 : 1,
                      duration: fadeDuration,
                      curve: fadeCurve,
                      child: placeholder,
                    ),
                    AnimatedOpacity(
                      opacity: loaded ? 1 : 0,
                      duration: fadeDuration,
                      curve: fadeCurve,
                      child: child,
                    ),
                  ],
                );
              },
            ),
    );
  }
}
