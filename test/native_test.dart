@TestOn('vm')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:thumbhash_ffi/thumbhash_ffi.dart';

import 'src/c_constants.dart';

void main() {
  test('uses the native codec', () {
    expect(ThumbhashFFI.isNative, isTrue);
  });

  test('Dart constants match the C header', () {
    expect(cConstants, (
      maxHashLength: ThumbhashFFI.maxHashLength,
      maxEncodeSize: ThumbhashFFI.maxEncodeSize,
      maxDecodeSize: ThumbhashFFI.maxDecodeSize,
    ));
  });
}
