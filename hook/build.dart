import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:native_toolchain_c/native_toolchain_c.dart';

/// Compiles `src/thumbhash_ffi.c` into a dynamic library for the target
/// platform and bundles it with the app as a code asset.
///
/// The asset name matches the library containing the `@Native` bindings, so
/// they resolve without any platform specific loading code.
Future<void> main(List<String> args) async {
  await build(args, (input, output) async {
    if (!input.config.buildCodeAssets) {
      return;
    }

    final targetOS = input.config.code.targetOS;
    await CBuilder.library(
      name: input.packageName,
      assetName: 'src/ffi/thumbhash_ffi_bindings.g.dart',
      sources: ['src/thumbhash_ffi.c'],
      includes: ['src'],
      // `cosf` and `roundf` live in libm on Linux and Android. On Apple
      // platforms libm is part of libSystem and on Windows of the CRT.
      libraries: [if (targetOS == OS.linux || targetOS == OS.android) 'm'],
    ).run(input: input, output: output);
  });
}
