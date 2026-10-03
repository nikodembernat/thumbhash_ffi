@TestOn('browser')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:thumbhash_ffi/thumbhash_ffi.dart';

void main() {
  test('uses the Dart codec', () {
    expect(ThumbHash.isNative, isFalse);
  });
}
