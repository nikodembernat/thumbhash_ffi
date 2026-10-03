import 'package:flutter/widgets.dart';
import 'package:thumbhash_ffi/src/flutter/thumb_hash_image.dart';
import 'package:thumbhash_ffi/src/thumb_hash.dart';

/// Shows the placeholder of a [ThumbHash] and, optionally, cross-fades to
/// the actual [image] once it has loaded.
///
/// ```dart
/// AspectRatio(
///   aspectRatio: hash.aspectRatio,
///   child: ThumbHashPlaceholder(hash: hash, image: NetworkImage(url)),
/// )
/// ```
///
/// The widget fills its constraints, so give it a size. The average color of
/// the hash is shown until the placeholder is decoded.
class ThumbHashPlaceholder extends StatelessWidget {
  /// Creates a widget that shows [hash] until [image] has loaded.
  const ThumbHashPlaceholder({
    super.key,
    required this.hash,
    this.image,
    this.fit = BoxFit.cover,
    this.alignment = Alignment.center,
    this.fadeDuration = const Duration(milliseconds: 300),
    this.fadeCurve = Curves.easeOut,
    this.errorBuilder,
    this.semanticLabel,
  });

  /// The hash of the placeholder.
  final ThumbHash hash;

  /// The image to show once it has loaded.
  final ImageProvider? image;

  /// How to inscribe the placeholder and the [image] into the layout.
  final BoxFit fit;

  /// How to align the placeholder and the [image] within the layout.
  final AlignmentGeometry alignment;

  /// How long the cross-fade from the placeholder to the [image] lasts.
  final Duration fadeDuration;

  /// The curve of the cross-fade from the placeholder to the [image].
  final Curve fadeCurve;

  /// Builds the widget shown if the [image] fails to load.
  ///
  /// If null, the placeholder stays visible.
  final ImageErrorWidgetBuilder? errorBuilder;

  /// A semantic description of the [image].
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final image = this.image;
    final placeholder = ColoredBox(
      color: hash.averageColor,
      child: Image(
        image: ThumbHashImage(hash),
        fit: fit,
        alignment: alignment,
        width: double.infinity,
        height: double.infinity,
        gaplessPlayback: true,
        excludeFromSemantics: true,
      ),
    );

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
