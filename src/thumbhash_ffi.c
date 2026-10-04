// A C implementation of ThumbHash, ported from the reference Rust
// implementation by Evan Wallace:
// https://github.com/evanw/thumbhash/tree/main/rust
//
// The arithmetic follows the reference implementation (single precision
// floats, same quantization), but both the forward and the inverse DCT are
// evaluated separably with precomputed cosine tables, which is several times
// faster than evaluating every basis function for every pixel.

#include "thumbhash_ffi.h"

#include <math.h>
#include <stdbool.h>
#include <stdlib.h>

// Do not fuse multiplications and additions into FMA instructions (which
// clang does by default on ARM): the reference implementation rounds after
// every operation, and so should results on every platform.
#if defined(__clang__)
#pragma STDC FP_CONTRACT OFF
#endif

#define THUMBHASH_PI 3.14159265358979323846f

// The largest number of DCT components along a single axis.
#define MAX_COMPONENTS 7

// Upper bounds for the number of AC coefficients per channel.
#define MAX_L_AC (MAX_COMPONENTS * MAX_COMPONENTS)
#define PQ_AC 5
#define A_AC 14

static inline int32_t max_i32(int32_t a, int32_t b) { return a > b ? a : b; }

static inline float clamp01(float v) {
  return v < 0.0f ? 0.0f : (v > 1.0f ? 1.0f : v);
}

// Rounds half away from zero (like Rust's `f32::round`) and saturates to
// [0, max], which keeps every quantized value inside its bit field.
static inline uint32_t quantize(float v, uint32_t max) {
  float r = roundf(v);
  if (!(r > 0.0f)) return 0;
  if (r >= (float)max) return max;
  return (uint32_t)r;
}

// Fills `table[c * n + i]` with cos(pi / n * c * (i + 0.5)) for
// c in [0, components) and i in [0, n).
static void fill_cos_table(float *table, int32_t n, int32_t components) {
  for (int32_t c = 0; c < components; c++) {
    for (int32_t i = 0; i < n; i++) {
      table[c * n + i] =
          cosf(THUMBHASH_PI / (float)n * (float)c * ((float)i + 0.5f));
    }
  }
}

// ---------------------------------------------------------------------------
// Encoding
// ---------------------------------------------------------------------------

typedef struct {
  float dc;
  float scale;
  int32_t ac_count;
  float ac[MAX_L_AC];
} encoded_channel;

// Encodes `channel` using the DCT into DC (constant) and normalized AC
// (varying) terms. Only the components with `cx * ny < nx * (ny - cy)` are
// kept, which is a triangle in the frequency domain.
//
// `row_sums` must have room for `w` floats.
static void encode_channel(const float *channel, int32_t w, int32_t h,
                           int32_t nx, int32_t ny, const float *cos_x,
                           const float *cos_y, float *row_sums,
                           encoded_channel *out) {
  const float inv_area = 1.0f / (float)(w * h);
  out->dc = 0.0f;
  out->scale = 0.0f;
  out->ac_count = 0;

  for (int32_t cy = 0; cy < ny; cy++) {
    // Collapse the rows with the vertical basis function first...
    const float *fy = cos_y + cy * h;
    for (int32_t x = 0; x < w; x++) row_sums[x] = 0.0f;
    for (int32_t y = 0; y < h; y++) {
      const float *row = channel + y * w;
      const float f = fy[y];
      for (int32_t x = 0; x < w; x++) row_sums[x] += row[x] * f;
    }

    // ...then apply each horizontal basis function to the collapsed row.
    for (int32_t cx = 0; cx * ny < nx * (ny - cy); cx++) {
      const float *fx = cos_x + cx * w;
      float f = 0.0f;
      for (int32_t x = 0; x < w; x++) f += row_sums[x] * fx[x];
      f *= inv_area;
      if (cx > 0 || cy > 0) {
        out->ac[out->ac_count++] = f;
        const float magnitude = fabsf(f);
        if (magnitude > out->scale) out->scale = magnitude;
      } else {
        out->dc = f;
      }
    }
  }

  if (out->scale > 0.0f) {
    const float factor = 0.5f / out->scale;
    for (int32_t i = 0; i < out->ac_count; i++) {
      out->ac[i] = 0.5f + factor * out->ac[i];
    }
  }
}

typedef struct {
  uint8_t *hash;
  int32_t length;
  bool is_odd;
} nibble_writer;

static void write_ac(nibble_writer *writer, const encoded_channel *channel) {
  for (int32_t i = 0; i < channel->ac_count; i++) {
    const uint8_t u = (uint8_t)quantize(15.0f * channel->ac[i], 15);
    if (writer->is_odd) {
      writer->hash[writer->length - 1] |= (uint8_t)(u << 4);
    } else {
      writer->hash[writer->length++] = u;
    }
    writer->is_odd = !writer->is_odd;
  }
}

int32_t thumbhash_encode(int32_t w, int32_t h, const uint8_t *rgba,
                         uint8_t *hash) {
  if (rgba == NULL || hash == NULL || w < 1 || h < 1 ||
      w > THUMBHASH_MAX_ENCODE_SIZE || h > THUMBHASH_MAX_ENCODE_SIZE) {
    return THUMBHASH_ERROR_INVALID_ARGUMENT;
  }
  const int32_t n = w * h;

  // Determine the average color.
  float avg_r = 0.0f, avg_g = 0.0f, avg_b = 0.0f, avg_a = 0.0f;
  for (int32_t i = 0; i < n; i++) {
    const uint8_t *px = rgba + i * 4;
    const float alpha = (float)px[3] / 255.0f;
    avg_r += alpha / 255.0f * (float)px[0];
    avg_g += alpha / 255.0f * (float)px[1];
    avg_b += alpha / 255.0f * (float)px[2];
    avg_a += alpha;
  }
  if (avg_a > 0.0f) {
    avg_r /= avg_a;
    avg_g /= avg_a;
    avg_b /= avg_a;
  }

  const bool has_alpha = avg_a < (float)n;
  // Use fewer luminance bits if there's alpha.
  const int32_t l_limit = has_alpha ? 5 : 7;
  const int32_t max_side = max_i32(w, h);
  const int32_t lx =
      max_i32(1, (int32_t)roundf((float)(l_limit * w) / (float)max_side));
  const int32_t ly =
      max_i32(1, (int32_t)roundf((float)(l_limit * h) / (float)max_side));

  // One allocation for the LPQA channels, the cosine tables and a scratch
  // row: at most 4 * 100 * 100 + 7 * 100 * 2 + 100 floats (~163 KB), which
  // is too much for the stack of some threads.
  float *buffer = (float *)malloc(
      sizeof(float) * (size_t)(4 * n + MAX_COMPONENTS * (w + h) + w));
  if (buffer == NULL) return THUMBHASH_ERROR_OUT_OF_MEMORY;
  float *l = buffer;   // luminance
  float *p = l + n;    // yellow - blue
  float *q = p + n;    // red - green
  float *a = q + n;    // alpha
  float *cos_x = a + n;
  float *cos_y = cos_x + MAX_COMPONENTS * w;
  float *row_sums = cos_y + MAX_COMPONENTS * h;

  // Convert the image from RGBA to LPQA (composite atop the average color).
  for (int32_t i = 0; i < n; i++) {
    const uint8_t *px = rgba + i * 4;
    const float alpha = (float)px[3] / 255.0f;
    const float r = avg_r * (1.0f - alpha) + alpha / 255.0f * (float)px[0];
    const float g = avg_g * (1.0f - alpha) + alpha / 255.0f * (float)px[1];
    const float b = avg_b * (1.0f - alpha) + alpha / 255.0f * (float)px[2];
    l[i] = (r + g + b) / 3.0f;
    p[i] = (r + g) / 2.0f - b;
    q[i] = r - g;
    a[i] = alpha;
  }

  // Encode using the DCT into DC (constant) and normalized AC (varying) terms.
  const int32_t l_nx = max_i32(lx, 3);
  const int32_t l_ny = max_i32(ly, 3);
  const int32_t min_components = has_alpha ? 5 : 3;
  fill_cos_table(cos_x, w, max_i32(l_nx, min_components));
  fill_cos_table(cos_y, h, max_i32(l_ny, min_components));

  encoded_channel l_ch, p_ch, q_ch, a_ch;
  encode_channel(l, w, h, l_nx, l_ny, cos_x, cos_y, row_sums, &l_ch);
  encode_channel(p, w, h, 3, 3, cos_x, cos_y, row_sums, &p_ch);
  encode_channel(q, w, h, 3, 3, cos_x, cos_y, row_sums, &q_ch);
  if (has_alpha) {
    encode_channel(a, w, h, 5, 5, cos_x, cos_y, row_sums, &a_ch);
  }
  free(buffer);

  // Write the constants.
  const bool is_landscape = w > h;
  const uint32_t header24 = quantize(63.0f * l_ch.dc, 63) |
                            (quantize(31.5f + 31.5f * p_ch.dc, 63) << 6) |
                            (quantize(31.5f + 31.5f * q_ch.dc, 63) << 12) |
                            (quantize(31.0f * l_ch.scale, 31) << 18) |
                            (has_alpha ? 1u << 23 : 0u);
  const uint32_t header16 = (uint32_t)(is_landscape ? ly : lx) |
                            (quantize(63.0f * p_ch.scale, 63) << 3) |
                            (quantize(63.0f * q_ch.scale, 63) << 9) |
                            (is_landscape ? 1u << 15 : 0u);

  nibble_writer writer = {hash, 0, false};
  hash[writer.length++] = (uint8_t)(header24 & 255);
  hash[writer.length++] = (uint8_t)((header24 >> 8) & 255);
  hash[writer.length++] = (uint8_t)(header24 >> 16);
  hash[writer.length++] = (uint8_t)(header16 & 255);
  hash[writer.length++] = (uint8_t)(header16 >> 8);
  if (has_alpha) {
    hash[writer.length++] = (uint8_t)(quantize(15.0f * a_ch.dc, 15) |
                                      (quantize(15.0f * a_ch.scale, 15) << 4));
  }

  // Write the varying factors.
  write_ac(&writer, &l_ch);
  write_ac(&writer, &p_ch);
  write_ac(&writer, &q_ch);
  if (has_alpha) write_ac(&writer, &a_ch);
  return writer.length;
}

// ---------------------------------------------------------------------------
// Decoding
// ---------------------------------------------------------------------------

typedef struct {
  float l_dc, p_dc, q_dc, a_dc;
  float l_scale, p_scale, q_scale, a_scale;
  bool has_alpha;
  bool is_landscape;
  int32_t l_min;  // The stored (smaller) luminance component count.
  int32_t lx, ly;
  int32_t ac_start;
  int32_t length;  // The number of bytes the hash should have.
} header;

static int32_t ac_count(int32_t nx, int32_t ny) {
  int32_t count = 0;
  for (int32_t cy = 0; cy < ny; cy++) {
    for (int32_t cx = cy > 0 ? 0 : 1; cx * ny < nx * (ny - cy); cx++) count++;
  }
  return count;
}

static int32_t read_header(const uint8_t *hash, int32_t hash_length,
                           header *out) {
  if (hash == NULL || hash_length < 5) return THUMBHASH_ERROR_INVALID_HASH;
  const uint32_t header24 = (uint32_t)hash[0] | ((uint32_t)hash[1] << 8) |
                            ((uint32_t)hash[2] << 16);
  const uint32_t header16 = (uint32_t)hash[3] | ((uint32_t)hash[4] << 8);
  out->l_dc = (float)(header24 & 63) / 63.0f;
  out->p_dc = (float)((header24 >> 6) & 63) / 31.5f - 1.0f;
  out->q_dc = (float)((header24 >> 12) & 63) / 31.5f - 1.0f;
  out->l_scale = (float)((header24 >> 18) & 31) / 31.0f;
  out->has_alpha = (header24 >> 23) != 0;
  out->p_scale = (float)((header16 >> 3) & 63) / 63.0f;
  out->q_scale = (float)((header16 >> 9) & 63) / 63.0f;
  out->is_landscape = (header16 >> 15) != 0;
  out->l_min = (int32_t)(header16 & 7);
  if (out->l_min == 0) return THUMBHASH_ERROR_INVALID_HASH;

  const int32_t l_max = out->has_alpha ? 5 : 7;
  out->lx = max_i32(3, out->is_landscape ? l_max : out->l_min);
  out->ly = max_i32(3, out->is_landscape ? out->l_min : l_max);
  out->ac_start = out->has_alpha ? 6 : 5;
  if (hash_length < out->ac_start) return THUMBHASH_ERROR_INVALID_HASH;
  if (out->has_alpha) {
    out->a_dc = (float)(hash[5] & 15) / 15.0f;
    out->a_scale = (float)(hash[5] >> 4) / 15.0f;
  } else {
    out->a_dc = 1.0f;
    out->a_scale = 1.0f;
  }

  const int32_t nibbles = ac_count(out->lx, out->ly) + 2 * PQ_AC +
                          (out->has_alpha ? A_AC : 0);
  out->length = out->ac_start + (nibbles + 1) / 2;
  return hash_length < out->length ? THUMBHASH_ERROR_INVALID_HASH : 0;
}

int32_t thumbhash_decoded_size(const uint8_t *hash, int32_t hash_length,
                               int32_t *width, int32_t *height) {
  if (width == NULL || height == NULL) return THUMBHASH_ERROR_INVALID_ARGUMENT;
  header hd;
  const int32_t result = read_header(hash, hash_length, &hd);
  if (result != 0) return result;
  const int32_t l_max = hd.has_alpha ? 5 : 7;
  const float lx = (float)(hd.is_landscape ? l_max : hd.l_min);
  const float ly = (float)(hd.is_landscape ? hd.l_min : l_max);
  const float ratio = lx / ly;
  if (ratio > 1.0f) {
    *width = 32;
    *height = (int32_t)roundf(32.0f / ratio);
  } else {
    *width = (int32_t)roundf(32.0f * ratio);
    *height = 32;
  }
  return 0;
}

typedef struct {
  const uint8_t *hash;
  int32_t index;  // Index of the next nibble.
} nibble_reader;

// Reads the AC coefficients of a channel (boosted by `scale`) into a dense
// `ny` x `nx` matrix, leaving the DC and the dropped components at zero.
static void read_ac(nibble_reader *reader, int32_t nx, int32_t ny, float scale,
                    float *ac) {
  for (int32_t i = 0; i < nx * ny; i++) ac[i] = 0.0f;
  for (int32_t cy = 0; cy < ny; cy++) {
    for (int32_t cx = cy > 0 ? 0 : 1; cx * ny < nx * (ny - cy); cx++) {
      const uint8_t byte = reader->hash[reader->index >> 1];
      const uint8_t bits = (reader->index & 1) ? byte >> 4 : byte & 15;
      reader->index++;
      ac[cy * nx + cx] = ((float)bits / 7.5f - 1.0f) * scale;
    }
  }
}

// Collapses the vertical basis functions for one row: for each cx,
// out[cx] = sum over cy of ac[cy][cx] * 2 * cos_y[cy].
static inline void collapse_rows(const float *ac, int32_t nx, int32_t ny,
                                 const float *cos_y2, float *out) {
  for (int32_t cx = 0; cx < nx; cx++) out[cx] = 0.0f;
  for (int32_t cy = 0; cy < ny; cy++) {
    const float f = cos_y2[cy];
    for (int32_t cx = 0; cx < nx; cx++) out[cx] += ac[cy * nx + cx] * f;
  }
}

static inline uint8_t to_byte(float v) { return (uint8_t)(clamp01(v) * 255.0f); }

int32_t thumbhash_decode(const uint8_t *hash, int32_t hash_length,
                         int32_t width, int32_t height, uint32_t flags,
                         uint8_t *rgba) {
  if (rgba == NULL || width < 1 || height < 1 ||
      width > THUMBHASH_MAX_DECODE_SIZE || height > THUMBHASH_MAX_DECODE_SIZE) {
    return THUMBHASH_ERROR_INVALID_ARGUMENT;
  }
  header hd;
  const int32_t result = read_header(hash, hash_length, &hd);
  if (result != 0) return result;

  // Read the varying factors (boost saturation by 1.25x to compensate for
  // quantization).
  float l_ac[MAX_L_AC], p_ac[9], q_ac[9], a_ac[25];
  nibble_reader reader = {hash + hd.ac_start, 0};
  read_ac(&reader, hd.lx, hd.ly, hd.l_scale, l_ac);
  read_ac(&reader, 3, 3, hd.p_scale * 1.25f, p_ac);
  read_ac(&reader, 3, 3, hd.q_scale * 1.25f, q_ac);
  if (hd.has_alpha) read_ac(&reader, 5, 5, hd.a_scale, a_ac);

  // Precompute the horizontal basis functions for every column.
  const int32_t nx = max_i32(hd.lx, hd.has_alpha ? 5 : 3);
  const int32_t ny = max_i32(hd.ly, hd.has_alpha ? 5 : 3);
  float *cos_x = (float *)malloc(sizeof(float) * (size_t)(nx * width));
  if (cos_x == NULL) return THUMBHASH_ERROR_OUT_OF_MEMORY;
  for (int32_t x = 0; x < width; x++) {
    for (int32_t cx = 0; cx < nx; cx++) {
      cos_x[x * nx + cx] =
          cosf(THUMBHASH_PI / (float)width * ((float)x + 0.5f) * (float)cx);
    }
  }

  const bool premultiply = (flags & THUMBHASH_DECODE_PREMULTIPLIED) != 0;
  float cos_y2[MAX_COMPONENTS];
  float l_row[MAX_COMPONENTS], p_row[3], q_row[3], a_row[5];
  uint8_t *out = rgba;
  for (int32_t y = 0; y < height; y++) {
    for (int32_t cy = 0; cy < ny; cy++) {
      cos_y2[cy] =
          2.0f * cosf(THUMBHASH_PI / (float)height * ((float)y + 0.5f) *
                      (float)cy);
    }
    collapse_rows(l_ac, hd.lx, hd.ly, cos_y2, l_row);
    collapse_rows(p_ac, 3, 3, cos_y2, p_row);
    collapse_rows(q_ac, 3, 3, cos_y2, q_row);
    if (hd.has_alpha) collapse_rows(a_ac, 5, 5, cos_y2, a_row);

    for (int32_t x = 0; x < width; x++) {
      const float *fx = cos_x + x * nx;
      float l = hd.l_dc;
      for (int32_t cx = 0; cx < hd.lx; cx++) l += l_row[cx] * fx[cx];
      const float p = hd.p_dc + p_row[0] * fx[0] + p_row[1] * fx[1] +
                      p_row[2] * fx[2];
      const float q = hd.q_dc + q_row[0] * fx[0] + q_row[1] * fx[1] +
                      q_row[2] * fx[2];
      float a = hd.a_dc;
      if (hd.has_alpha) {
        a += a_row[0] * fx[0] + a_row[1] * fx[1] + a_row[2] * fx[2] +
             a_row[3] * fx[3] + a_row[4] * fx[4];
      }

      // Convert to RGB.
      const float b = l - 2.0f / 3.0f * p;
      const float r = (3.0f * l - b + q) / 2.0f;
      const float g = r - q;
      out[0] = to_byte(r);
      out[1] = to_byte(g);
      out[2] = to_byte(b);
      out[3] = to_byte(a);
      if (premultiply) {
        // Premultiply the bytes (rounding to nearest), so that both outputs
        // agree, like the Dart implementation.
        const uint32_t alpha = out[3];
        for (int c = 0; c < 3; c++) {
          out[c] = (uint8_t)(((uint32_t)out[c] * alpha + 127) / 255);
        }
      }
      out += 4;
    }
  }

  free(cos_x);
  return 0;
}
