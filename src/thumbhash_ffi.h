// A C implementation of ThumbHash, a very compact representation of an image
// placeholder.
//
// Ported from the reference Rust implementation by Evan Wallace:
// https://github.com/evanw/thumbhash/tree/main/rust

#ifndef THUMBHASH_FFI_H_
#define THUMBHASH_FFI_H_

#include <stdint.h>

#if defined(_WIN32)
#define THUMBHASH_EXPORT __declspec(dllexport)
#else
#define THUMBHASH_EXPORT \
  __attribute__((visibility("default"))) __attribute__((used))
#endif

#ifdef __cplusplus
extern "C" {
#endif

// The maximum number of bytes in a ThumbHash.
#define THUMBHASH_MAX_HASH_LENGTH 25

// The maximum width and height of an image that can be encoded.
#define THUMBHASH_MAX_ENCODE_SIZE 100

// The maximum width and height of an image that can be decoded.
#define THUMBHASH_MAX_DECODE_SIZE 4096

// One of the arguments is out of range (or a pointer is NULL).
#define THUMBHASH_ERROR_INVALID_ARGUMENT -1

// The hash is malformed or too short.
#define THUMBHASH_ERROR_INVALID_HASH -2

// Memory allocation failed.
#define THUMBHASH_ERROR_OUT_OF_MEMORY -3

// Flag for `thumbhash_decode`: output RGB premultiplied by alpha.
#define THUMBHASH_DECODE_PREMULTIPLIED 1

// Encodes an RGBA image to a ThumbHash. RGB must not be premultiplied by A.
//
// `width` and `height` must be in range [1, THUMBHASH_MAX_ENCODE_SIZE].
// `rgba` holds the pixels row-by-row and must have `width * height * 4`
// bytes. `hash` must have room for THUMBHASH_MAX_HASH_LENGTH bytes.
//
// Returns the number of bytes written to `hash`, or a negative error code.
THUMBHASH_EXPORT int32_t thumbhash_encode(int32_t width, int32_t height,
                                          const uint8_t *rgba, uint8_t *hash);

// Decodes a ThumbHash to an RGBA image of an arbitrary size.
//
// The reference implementation renders placeholders whose larger side is
// 32px, see `thumbhash_decoded_size`. `width` and `height` must be in range
// [1, THUMBHASH_MAX_DECODE_SIZE] and `rgba` must have room for
// `width * height * 4` bytes. Unless `flags` contains
// THUMBHASH_DECODE_PREMULTIPLIED, RGB is not premultiplied by A.
//
// Returns 0 on success, or a negative error code.
THUMBHASH_EXPORT int32_t thumbhash_decode(const uint8_t *hash,
                                          int32_t hash_length, int32_t width,
                                          int32_t height, uint32_t flags,
                                          uint8_t *rgba);

// Computes the size of the placeholder rendered by the reference
// implementation, based on the approximate aspect ratio stored in the hash.
//
// Returns 0 on success, or a negative error code.
THUMBHASH_EXPORT int32_t thumbhash_decoded_size(const uint8_t *hash,
                                                int32_t hash_length,
                                                int32_t *width,
                                                int32_t *height);

#ifdef __cplusplus
}
#endif

#endif  // THUMBHASH_FFI_H_
