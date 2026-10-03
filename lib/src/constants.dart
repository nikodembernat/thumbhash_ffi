/// The maximum number of bytes in a ThumbHash.
const thumbhashMaxHashLength = 25;

/// The maximum width and height of an image that can be encoded.
///
/// Larger images must be downscaled first, which is what
/// `ThumbhashFFI.encode` does automatically.
const thumbhashMaxEncodeSize = 100;

/// The maximum width and height of an image that can be decoded.
const thumbhashMaxDecodeSize = 4096;
