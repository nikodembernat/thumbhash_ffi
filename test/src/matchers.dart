import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:thumbhash_ffi/src/hash_header.dart';

/// Expects [actual] to be [expected], up to rounding differences.
///
/// The reference implementation evaluates the DCT in a different order (and
/// the web in double precision), so a quantized value that lands right at a
/// rounding boundary may differ by one step. Flags and sizes must match
/// exactly and at most [maxDifferences] values may differ, by one step.
///
/// The AC coefficients of a channel whose scale is zero are not compared:
/// they are normalized rounding noise that does not affect the placeholder.
void expectHashClose(
  Uint8List actual,
  Uint8List expected, {
  required int maxDifferences,
  String? reason,
}) {
  expect(actual.length, expected.length, reason: reason);

  final actualFields = _fields(actual);
  final expectedFields = _fields(expected);
  var differences = 0;
  for (var i = 0; i < expectedFields.length; i++) {
    final (name, value, exact) = expectedFields[i];
    final (_, actualValue, _) = actualFields[i];
    final difference = (actualValue - value).abs();
    expect(
      difference,
      exact ? 0 : lessThanOrEqualTo(1),
      reason: '${reason ?? ''} $name: $actualValue != $value',
    );
    differences += difference;
  }
  expect(differences, lessThanOrEqualTo(maxDifferences), reason: reason);
}

/// Splits [hash] into (name, value, exact) fields.
List<(String, int, bool)> _fields(Uint8List hash) {
  final header24 = hash[0] | (hash[1] << 8) | (hash[2] << 16);
  final header16 = hash[3] | (hash[4] << 8);
  final hasAlpha = (header24 >> 23) != 0;
  final isLandscape = (header16 >> 15) != 0;
  final lMin = header16 & 7;
  final lMax = hasAlpha ? 5 : 7;
  final lx = math.max(3, isLandscape ? lMax : lMin);
  final ly = math.max(3, isLandscape ? lMin : lMax);
  final lScale = (header24 >> 18) & 31;
  final pScale = (header16 >> 3) & 63;
  final qScale = (header16 >> 9) & 63;
  final aScale = hasAlpha ? hash[5] >> 4 : 0;

  final acStart = hasAlpha ? 6 : 5;
  var index = acStart * 2;
  Iterable<(String, int, bool)> ac(String channel, int count, int scale) sync* {
    for (var i = 0; i < count; i++, index++) {
      // A zero scale makes the coefficients irrelevant.
      if (scale > 0) {
        final nibble = (hash[index >> 1] >> ((index & 1) << 2)) & 15;
        yield ('$channel AC $i', nibble, false);
      }
    }
  }

  return [
    ('L DC', header24 & 63, false),
    ('P DC', (header24 >> 6) & 63, false),
    ('Q DC', (header24 >> 12) & 63, false),
    ('L scale', lScale, false),
    ('has alpha', header24 >> 23, true),
    ('L components', lMin, true),
    ('P scale', pScale, false),
    ('Q scale', qScale, false),
    ('is landscape', header16 >> 15, true),
    if (hasAlpha) ...[
      ('A DC', hash[5] & 15, false),
      ('A scale', aScale, false),
    ],
    ...ac('L', acCount(lx, ly), lScale),
    ...ac('P', 5, pScale),
    ...ac('Q', 5, qScale),
    if (hasAlpha) ...ac('A', 14, aScale),
  ];
}

/// Expects every byte of [actual] to be within [tolerance] of [expected].
void expectBytesClose(
  Uint8List actual,
  Uint8List expected, {
  int tolerance = 1,
  String? reason,
}) {
  expect(actual.length, expected.length, reason: reason);
  var maxDifference = 0;
  var firstIndex = -1;
  for (var i = 0; i < expected.length; i++) {
    final difference = (actual[i] - expected[i]).abs();
    if (difference > maxDifference) {
      maxDifference = difference;
      firstIndex = i;
    }
  }
  expect(
    maxDifference,
    lessThanOrEqualTo(tolerance),
    reason:
        '${reason ?? ''} byte $firstIndex: '
        '${firstIndex < 0 ? '' : '${actual[firstIndex]} != ${expected[firstIndex]}'}',
  );
}
