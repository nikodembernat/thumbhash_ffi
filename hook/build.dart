import 'package:hooks/hooks.dart';
import 'package:native_toolchain_rust/native_toolchain_rust.dart';

/// Compiles the Rust crate in `rust/` (a C ABI for the reference ThumbHash
/// implementation) for the target platform and bundles it with the app as a
/// code asset.
///
/// The asset name matches the library containing the `@Native` bindings, so
/// they resolve without any platform specific loading code.
Future<void> main(List<String> args) async {
  await build(args, (input, output) async {
    await const RustBuilder(
      assetName: 'src/ffi/thumbhash_ffi_bindings.g.dart',
    ).run(input: input, output: output);
  });
}
