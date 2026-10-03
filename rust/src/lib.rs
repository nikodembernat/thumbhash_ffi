//! A C ABI for the reference implementation of ThumbHash
//! (<https://github.com/evanw/thumbhash>), called from Dart through `dart:ffi`.
//!
//! The functions validate their arguments and never unwind across the FFI
//! boundary: invalid input and unexpected panics turn into error codes.

use std::panic::catch_unwind;
use std::slice;

/// The maximum number of bytes in a ThumbHash.
pub const THUMBHASH_MAX_HASH_LENGTH: usize = 25;

/// The maximum width and height of an image that can be encoded.
pub const THUMBHASH_MAX_ENCODE_SIZE: u32 = 100;

/// The maximum number of bytes of a decoded image (at most 32x32 RGBA).
pub const THUMBHASH_MAX_DECODED_LENGTH: usize = 32 * 32 * 4;

/// The call succeeded.
pub const THUMBHASH_OK: i32 = 0;

/// One of the arguments is out of range, or a pointer is null.
pub const THUMBHASH_ERROR_INVALID_ARGUMENT: i32 = -1;

/// The hash is malformed or too short.
pub const THUMBHASH_ERROR_INVALID_HASH: i32 = -2;

/// The implementation panicked.
pub const THUMBHASH_ERROR_PANIC: i32 = -3;

/// # Safety
///
/// `data` must be null or point to `length` readable bytes.
unsafe fn bytes<'a>(data: *const u8, length: usize) -> Option<&'a [u8]> {
    if data.is_null() {
        None
    } else {
        Some(slice::from_raw_parts(data, length))
    }
}

/// Encodes an RGBA image to a ThumbHash. RGB must not be premultiplied by A.
///
/// `width` and `height` must be in range [1, THUMBHASH_MAX_ENCODE_SIZE] and
/// `rgba` must hold exactly `width * height * 4` bytes, row by row. `hash`
/// must have room for THUMBHASH_MAX_HASH_LENGTH bytes.
///
/// Returns the number of bytes written to `hash`, or a negative error code.
///
/// # Safety
///
/// `rgba` must point to `rgba_length` readable bytes and `hash` to
/// THUMBHASH_MAX_HASH_LENGTH writable bytes.
#[no_mangle]
pub unsafe extern "C" fn thumbhash_encode(
    width: u32,
    height: u32,
    rgba: *const u8,
    rgba_length: usize,
    hash: *mut u8,
) -> i32 {
    let size_ok = |s: u32| (1..=THUMBHASH_MAX_ENCODE_SIZE).contains(&s);
    if !size_ok(width) || !size_ok(height) || hash.is_null() {
        return THUMBHASH_ERROR_INVALID_ARGUMENT;
    }
    let (w, h) = (width as usize, height as usize);
    let Some(rgba) = bytes(rgba, rgba_length).filter(|p| p.len() == w * h * 4) else {
        return THUMBHASH_ERROR_INVALID_ARGUMENT;
    };
    let Ok(encoded) = catch_unwind(|| thumbhash::rgba_to_thumb_hash(w, h, rgba)) else {
        return THUMBHASH_ERROR_PANIC;
    };
    if encoded.len() > THUMBHASH_MAX_HASH_LENGTH {
        return THUMBHASH_ERROR_PANIC;
    }
    slice::from_raw_parts_mut(hash, encoded.len()).copy_from_slice(&encoded);
    encoded.len() as i32
}

/// Decodes a ThumbHash to an RGBA image, whose larger side is 32 pixels.
///
/// Writes the pixels to `rgba`, row by row, and the size of the image to
/// `size` (width, then height). RGB is premultiplied by A if `premultiplied`
/// is true.
///
/// Returns THUMBHASH_OK, or a negative error code.
///
/// # Safety
///
/// `hash` must point to `hash_length` readable bytes, `rgba` to
/// THUMBHASH_MAX_DECODED_LENGTH writable bytes and `size` to 2 writable
/// integers.
#[no_mangle]
pub unsafe extern "C" fn thumbhash_decode(
    hash: *const u8,
    hash_length: usize,
    premultiplied: bool,
    rgba: *mut u8,
    size: *mut u32,
) -> i32 {
    let Some(hash) = bytes(hash, hash_length) else {
        return THUMBHASH_ERROR_INVALID_ARGUMENT;
    };
    if rgba.is_null() || size.is_null() {
        return THUMBHASH_ERROR_INVALID_ARGUMENT;
    }
    let (w, h, mut pixels) = match catch_unwind(|| thumbhash::thumb_hash_to_rgba(hash)) {
        Ok(Ok(decoded)) => decoded,
        Ok(Err(())) => return THUMBHASH_ERROR_INVALID_HASH,
        Err(_) => return THUMBHASH_ERROR_PANIC,
    };
    // Malformed headers can produce empty images.
    if w == 0 || h == 0 || pixels.len() > THUMBHASH_MAX_DECODED_LENGTH {
        return THUMBHASH_ERROR_INVALID_HASH;
    }
    if premultiplied {
        for pixel in pixels.chunks_exact_mut(4) {
            let a = u16::from(pixel[3]);
            for c in &mut pixel[..3] {
                *c = ((u16::from(*c) * a + 127) / 255) as u8;
            }
        }
    }
    slice::from_raw_parts_mut(rgba, pixels.len()).copy_from_slice(&pixels);
    slice::from_raw_parts_mut(size, 2).copy_from_slice(&[w as u32, h as u32]);
    THUMBHASH_OK
}

/// Extracts the average color from a ThumbHash.
///
/// Writes red, green, blue and alpha, each in range [0, 1], to `rgba`. RGB is
/// not premultiplied by A.
///
/// Returns THUMBHASH_OK, or a negative error code.
///
/// # Safety
///
/// `hash` must point to `hash_length` readable bytes and `rgba` to 4
/// writable floats.
#[no_mangle]
pub unsafe extern "C" fn thumbhash_average_rgba(
    hash: *const u8,
    hash_length: usize,
    rgba: *mut f32,
) -> i32 {
    let Some(hash) = bytes(hash, hash_length) else {
        return THUMBHASH_ERROR_INVALID_ARGUMENT;
    };
    if rgba.is_null() {
        return THUMBHASH_ERROR_INVALID_ARGUMENT;
    }
    // The upstream function reads the alpha byte without checking the length.
    let has_alpha = hash.len() > 2 && hash[2] & 0x80 != 0;
    if has_alpha && hash.len() < 6 {
        return THUMBHASH_ERROR_INVALID_HASH;
    }
    match catch_unwind(|| thumbhash::thumb_hash_to_average_rgba(hash)) {
        Ok(Ok((r, g, b, a))) => {
            slice::from_raw_parts_mut(rgba, 4).copy_from_slice(&[r, g, b, a]);
            THUMBHASH_OK
        }
        Ok(Err(())) => THUMBHASH_ERROR_INVALID_HASH,
        Err(_) => THUMBHASH_ERROR_PANIC,
    }
}

/// Extracts the approximate aspect ratio (width / height) of the original
/// image.
///
/// Returns the ratio, or a negative error code.
///
/// # Safety
///
/// `hash` must point to `hash_length` readable bytes.
#[no_mangle]
pub unsafe extern "C" fn thumbhash_approximate_aspect_ratio(
    hash: *const u8,
    hash_length: usize,
) -> f32 {
    let Some(hash) = bytes(hash, hash_length) else {
        return THUMBHASH_ERROR_INVALID_ARGUMENT as f32;
    };
    let result = catch_unwind(|| thumbhash::thumb_hash_to_approximate_aspect_ratio(hash));
    match result {
        Ok(Ok(ratio)) if ratio.is_finite() && ratio > 0.0 => ratio,
        Ok(_) => THUMBHASH_ERROR_INVALID_HASH as f32,
        Err(_) => THUMBHASH_ERROR_PANIC as f32,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    // The thumbhash.js demo image "Field" (no alpha) and a hash with alpha.
    const OPAQUE: [u8; 23] = [
        0x1b, 0x08, 0x0e, 0x35, 0x86, 0x78, 0x68, 0x66, 0x8e, 0x79, 0x87, 0x87, 0x78, 0x88, 0x77,
        0x87, 0x0a, 0x78, 0x87, 0x87, 0x78, 0x77, 0x08,
    ];

    fn gradient(w: usize, h: usize, alpha: bool) -> Vec<u8> {
        let mut rgba = Vec::with_capacity(w * h * 4);
        for y in 0..h {
            for x in 0..w {
                let a = if alpha { (x * 255 / w) as u8 } else { 255 };
                rgba.extend_from_slice(&[(x * 2) as u8, (y * 2) as u8, 128, a]);
            }
        }
        rgba
    }

    fn encode(w: u32, h: u32, rgba: &[u8]) -> Result<Vec<u8>, i32> {
        let mut hash = [0u8; THUMBHASH_MAX_HASH_LENGTH];
        let n = unsafe { thumbhash_encode(w, h, rgba.as_ptr(), rgba.len(), hash.as_mut_ptr()) };
        if n < 0 {
            Err(n)
        } else {
            Ok(hash[..n as usize].to_vec())
        }
    }

    fn decode(hash: &[u8], premultiplied: bool) -> Result<(u32, u32, Vec<u8>), i32> {
        let mut rgba = [0u8; THUMBHASH_MAX_DECODED_LENGTH];
        let mut size = [0u32; 2];
        let code = unsafe {
            thumbhash_decode(
                hash.as_ptr(),
                hash.len(),
                premultiplied,
                rgba.as_mut_ptr(),
                size.as_mut_ptr(),
            )
        };
        if code != THUMBHASH_OK {
            return Err(code);
        }
        let n = (size[0] * size[1] * 4) as usize;
        Ok((size[0], size[1], rgba[..n].to_vec()))
    }

    #[test]
    fn encodes_like_the_crate() {
        for (w, h, alpha) in [
            (100, 75, false),
            (1, 1, false),
            (64, 100, true),
            (100, 1, true),
        ] {
            let rgba = gradient(w, h, alpha);
            assert_eq!(
                encode(w as u32, h as u32, &rgba).unwrap(),
                thumbhash::rgba_to_thumb_hash(w, h, &rgba)
            );
        }
    }

    #[test]
    fn rejects_invalid_images() {
        let rgba = gradient(10, 10, false);
        assert_eq!(encode(0, 10, &rgba), Err(THUMBHASH_ERROR_INVALID_ARGUMENT));
        assert_eq!(
            encode(101, 1, &gradient(101, 1, false)),
            Err(THUMBHASH_ERROR_INVALID_ARGUMENT)
        );
        assert_eq!(encode(10, 9, &rgba), Err(THUMBHASH_ERROR_INVALID_ARGUMENT));
        let null = unsafe { thumbhash_encode(1, 1, std::ptr::null(), 4, [0; 25].as_mut_ptr()) };
        assert_eq!(null, THUMBHASH_ERROR_INVALID_ARGUMENT);
    }

    #[test]
    fn decodes_like_the_crate() {
        let (w, h, rgba) = decode(&OPAQUE, false).unwrap();
        let expected = thumbhash::thumb_hash_to_rgba(&OPAQUE).unwrap();
        assert_eq!((w as usize, h as usize, rgba), expected);
    }

    #[test]
    fn premultiplies() {
        let hash = encode(64, 100, &gradient(64, 100, true)).unwrap();
        let (_, _, straight) = decode(&hash, false).unwrap();
        let (_, _, premultiplied) = decode(&hash, true).unwrap();
        for (s, p) in straight.chunks_exact(4).zip(premultiplied.chunks_exact(4)) {
            assert_eq!(s[3], p[3]);
            for c in 0..3 {
                let expected = (f32::from(s[c]) * f32::from(s[3]) / 255.0).round() as u8;
                assert_eq!(p[c], expected);
            }
        }
    }

    #[test]
    fn rejects_invalid_hashes() {
        for hash in [
            &[][..],
            &[0, 0, 0, 7][..],
            &OPAQUE[..10],
            &[0, 0, 0x80, 7, 0][..],
        ] {
            assert_eq!(decode(hash, false), Err(THUMBHASH_ERROR_INVALID_HASH));
        }
        // The average color only needs the header (and the alpha byte).
        for hash in [&[][..], &[0, 0, 0, 7][..], &[0, 0, 0x80, 7, 0][..]] {
            let mut rgba = [0f32; 4];
            let code =
                unsafe { thumbhash_average_rgba(hash.as_ptr(), hash.len(), rgba.as_mut_ptr()) };
            assert_eq!(code, THUMBHASH_ERROR_INVALID_HASH);
        }
        // A luminance component count of zero yields an empty image.
        let mut empty = OPAQUE;
        empty[3] &= !7;
        assert_eq!(decode(&empty, false), Err(THUMBHASH_ERROR_INVALID_HASH));
        let ratio = unsafe { thumbhash_approximate_aspect_ratio(empty.as_ptr(), empty.len()) };
        assert_eq!(ratio, THUMBHASH_ERROR_INVALID_HASH as f32);
    }

    #[test]
    fn inspects_like_the_crate() {
        let mut rgba = [0f32; 4];
        let code =
            unsafe { thumbhash_average_rgba(OPAQUE.as_ptr(), OPAQUE.len(), rgba.as_mut_ptr()) };
        assert_eq!(code, THUMBHASH_OK);
        let (r, g, b, a) = thumbhash::thumb_hash_to_average_rgba(&OPAQUE).unwrap();
        assert_eq!(rgba, [r, g, b, a]);
        let ratio = unsafe { thumbhash_approximate_aspect_ratio(OPAQUE.as_ptr(), OPAQUE.len()) };
        assert_eq!(
            ratio,
            thumbhash::thumb_hash_to_approximate_aspect_ratio(&OPAQUE).unwrap()
        );
    }
}
