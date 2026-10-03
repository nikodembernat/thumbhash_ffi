/// Thrown when a ThumbHash cannot be encoded or decoded.
class ThumbhashFFIException implements Exception {
  /// Creates a [ThumbhashFFIException].
  const ThumbhashFFIException(this.message, [this.cause]);

  /// A description of the failure.
  final String message;

  /// The underlying error, if any.
  final Object? cause;

  @override
  String toString() => switch (cause) {
    null => 'ThumbhashFFIException: $message',
    final cause => 'ThumbhashFFIException: $message ($cause)',
  };
}
