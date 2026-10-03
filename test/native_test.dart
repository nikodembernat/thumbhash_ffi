@TestOn('vm')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:thumbhash_ffi/thumbhash_ffi.dart';

import 'src/c_constants.dart';

void main() {
  test('uses the native codec', () {
    expect(ThumbHash.isNative, isTrue);
  });

  test('Dart constants match the Rust crate', () {
    expect(cConstants, (
      maxHashLength: ThumbHash.maxLength,
      maxEncodeSize: ThumbHash.maxEncodeSize,
    ));
  });
}
