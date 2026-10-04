// A C implementation of ThumbHash, ported from the reference Rust
// implementation by Evan Wallace:
// https://github.com/evanw/thumbhash/tree/main/rust
//
// The arithmetic follows the reference implementation (single precision
// floats, same order of operations, same quantization), but it is several
// times faster: both the forward and the inverse DCT are evaluated separably
// with cached cosine tables, in loops over contiguous memory that the
// compiler vectorizes, and per-pixel divisions are looked up.

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

#if defined(_MSC_VER)
#define THREAD_LOCAL __declspec(thread)
#define RESTRICT __restrict
#else
#define THREAD_LOCAL _Thread_local
#define RESTRICT restrict
#endif

// The reference implementation computes the DCT basis functions with the
// factors multiplied in a different order when encoding and when decoding,
// which rounds differently. Both orders are kept, for identical results.
typedef enum { ENCODE_ORDER, DECODE_ORDER } cos_order;

// The largest axis whose basis functions are cached.
#define MAX_CACHED_SIZE THUMBHASH_MAX_ENCODE_SIZE

typedef struct {
  int32_t n;  // 0 if the entry is empty.
  cos_order order;
  float table[MAX_COMPONENTS * MAX_CACHED_SIZE];
} cos_entry;

// Computing the basis functions takes up to a third of the time of a call,
// and consecutive calls usually have the same sizes. Each thread caches the
// tables of the last few sizes it used (~11 KB).
#define COS_CACHE_SIZE 4
static THREAD_LOCAL cos_entry cos_cache[COS_CACHE_SIZE];
static THREAD_LOCAL uint32_t cos_cache_next;

// Fills `table[c * n + i]` with cos(pi / n * c * (i + 0.5)) for
// c in [0, MAX_COMPONENTS) and i in [0, n).
static void fill_cos_table(float *table, int32_t n, cos_order order) {
  for (int32_t c = 0; c < MAX_COMPONENTS; c++) {
    for (int32_t i = 0; i < n; i++) {
      table[c * n + i] =
          order == ENCODE_ORDER
              ? cosf(THUMBHASH_PI / (float)n * (float)c * ((float)i + 0.5f))
              : cosf(THUMBHASH_PI / (float)n * ((float)i + 0.5f) * (float)c);
    }
  }
}

// Returns the cache entry for an axis of `n` <= MAX_CACHED_SIZE pixels,
// filling it if needed without evicting `keep`.
static const cos_entry *cos_entry_for(int32_t n, cos_order order,
                                      const cos_entry *keep) {
  for (int32_t i = 0; i < COS_CACHE_SIZE; i++) {
    if (cos_cache[i].n == n && cos_cache[i].order == order) {
      return &cos_cache[i];
    }
  }
  cos_entry *entry = &cos_cache[cos_cache_next++ % COS_CACHE_SIZE];
  if (entry == keep) entry = &cos_cache[cos_cache_next++ % COS_CACHE_SIZE];
  fill_cos_table(entry->table, n, order);
  entry->n = n;
  entry->order = order;
  return entry;
}

// Returns the basis functions for both axes of an image whose sides are at
// most MAX_CACHED_SIZE pixels.
static void cos_tables(int32_t w, int32_t h, cos_order order,
                       const float **cos_x, const float **cos_y) {
  const cos_entry *x = cos_entry_for(w, order, NULL);
  const cos_entry *y = cos_entry_for(h, order, x);
  *cos_x = x->table;
  *cos_y = y->table;
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

// Accumulates one row of a channel into the vertical sums of the DCT:
// `sums[cy * w + x] += row[x] * cos_y[cy * h + y]` for each cy.
static inline void accumulate_row(const float *RESTRICT row, int32_t w,
                                  int32_t h, int32_t y, int32_t ny,
                                  const float *RESTRICT cos_y,
                                  float *RESTRICT sums) {
  for (int32_t cy = 0; cy < ny; cy++) {
    const float f = cos_y[cy * h + y];
    float *RESTRICT sum = sums + cy * w;
    for (int32_t x = 0; x < w; x++) sum[x] += row[x] * f;
  }
}

// Finishes the DCT of a channel from its vertical sums: DC (constant) and
// normalized AC (varying) terms. Only the components with
// `cx * ny < nx * (ny - cy)` are kept, which is a triangle in the frequency
// domain.
static void encode_channel(const float *sums, int32_t w, int32_t h, int32_t nx,
                           int32_t ny, const float *cos_x,
                           encoded_channel *out) {
  const float inv_area = 1.0f / (float)(w * h);
  out->dc = 0.0f;
  out->scale = 0.0f;
  out->ac_count = 0;

  for (int32_t cy = 0; cy < ny; cy++) {
    const float *sum = sums + cy * w;
    int32_t count = 0;
    while (count * ny < nx * (ny - cy)) count++;

    // Each coefficient is a sum over the columns. Accumulate all of them in
    // the same pass, so that the additions of different coefficients overlap
    // instead of waiting for each other.
    float f[MAX_COMPONENTS] = {0};
    for (int32_t x = 0; x < w; x++) {
      const float v = sum[x];
      for (int32_t cx = 0; cx < count; cx++) f[cx] += v * cos_x[cx * w + x];
    }

    for (int32_t cx = 0; cx < count; cx++) {
      f[cx] *= inv_area;
      if (cx > 0 || cy > 0) {
        out->ac[out->ac_count++] = f[cx];
        const float magnitude = fabsf(f[cx]);
        if (magnitude > out->scale) out->scale = magnitude;
      } else {
        out->dc = f[cx];
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

  // Divisions are slow, so look up the per-pixel factors of the reference
  // implementation, computed exactly like it does: alpha = a / 255,
  // weight = alpha / 255 and inverse = 1 - alpha.
  float alpha_of[256], weight_of[256], inverse_of[256];
  for (int32_t i = 0; i < 256; i++) {
    alpha_of[i] = (float)i / 255.0f;
    weight_of[i] = alpha_of[i] / 255.0f;
    inverse_of[i] = 1.0f - alpha_of[i];
  }

  // Determine the average color. Transparent pixels are composited atop it,
  // so it does not matter for opaque images (it is multiplied by zero): skip
  // it for them, after a quick check that vectorizes. Otherwise, sum like
  // the reference, one pixel after the other.
  uint32_t sum_a = 0;
  for (int32_t i = 0; i < n; i++) sum_a += rgba[i * 4 + 3];
  const bool has_alpha = sum_a < 255u * (uint32_t)n;
  float avg_r = 0.0f, avg_g = 0.0f, avg_b = 0.0f;
  if (has_alpha) {
    float avg_a = 0.0f;
    for (int32_t i = 0; i < n; i++) {
      const uint8_t *px = rgba + i * 4;
      const float weight = weight_of[px[3]];
      avg_r += weight * (float)px[0];
      avg_g += weight * (float)px[1];
      avg_b += weight * (float)px[2];
      avg_a += alpha_of[px[3]];
    }
    if (avg_a > 0.0f) {
      avg_r /= avg_a;
      avg_g /= avg_a;
      avg_b /= avg_a;
    }
  }

  // Use fewer luminance bits if there's alpha.
  const int32_t l_limit = has_alpha ? 5 : 7;
  const int32_t max_side = max_i32(w, h);
  const int32_t lx =
      max_i32(1, (int32_t)roundf((float)(l_limit * w) / (float)max_side));
  const int32_t ly =
      max_i32(1, (int32_t)roundf((float)(l_limit * h) / (float)max_side));
  const int32_t l_nx = max_i32(lx, 3);
  const int32_t l_ny = max_i32(ly, 3);
  const int32_t a_n = has_alpha ? 5 : 0;

  // One row of each LPQA channel and the vertical sums of the DCT:
  // (4 + 7 + 3 + 3 + 5) * 100 floats at most (~9 KB).
  float buffer[(4 + MAX_COMPONENTS + 3 + 3 + 5) * THUMBHASH_MAX_ENCODE_SIZE];
  float *l_row = buffer;     // luminance
  float *p_row = l_row + w;  // yellow - blue
  float *q_row = p_row + w;  // red - green
  float *a_row = q_row + w;  // alpha
  float *l_sums = a_row + w;
  float *p_sums = l_sums + l_ny * w;
  float *q_sums = p_sums + 3 * w;
  float *a_sums = q_sums + 3 * w;
  for (float *sum = l_sums; sum < a_sums + a_n * w; sum++) *sum = 0.0f;

  const float *cos_x, *cos_y;
  cos_tables(w, h, ENCODE_ORDER, &cos_x, &cos_y);

  // Convert the image from RGBA to LPQA (composite atop the average color)
  // row by row, and collapse the rows with the vertical basis functions...
  for (int32_t y = 0; y < h; y++) {
    const uint8_t *px = rgba + y * w * 4;
    for (int32_t x = 0; x < w; x++, px += 4) {
      const float weight = weight_of[px[3]];
      const float inverse = inverse_of[px[3]];
      const float r = avg_r * inverse + weight * (float)px[0];
      const float g = avg_g * inverse + weight * (float)px[1];
      const float b = avg_b * inverse + weight * (float)px[2];
      l_row[x] = (r + g + b) / 3.0f;
      p_row[x] = (r + g) / 2.0f - b;
      q_row[x] = r - g;
      a_row[x] = alpha_of[px[3]];
    }
    accumulate_row(l_row, w, h, y, l_ny, cos_y, l_sums);
    accumulate_row(p_row, w, h, y, 3, cos_y, p_sums);
    accumulate_row(q_row, w, h, y, 3, cos_y, q_sums);
    accumulate_row(a_row, w, h, y, a_n, cos_y, a_sums);
  }

  // ...then apply the horizontal basis functions.
  encoded_channel l_ch, p_ch, q_ch, a_ch;
  encode_channel(l_sums, w, h, l_nx, l_ny, cos_x, &l_ch);
  encode_channel(p_sums, w, h, 3, 3, cos_x, &p_ch);
  encode_channel(q_sums, w, h, 3, 3, cos_x, &q_ch);
  if (has_alpha) encode_channel(a_sums, w, h, 5, 5, cos_x, &a_ch);

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
  const uint32_t header24 =
      (uint32_t)hash[0] | ((uint32_t)hash[1] << 8) | ((uint32_t)hash[2] << 16);
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

  const int32_t nibbles =
      ac_count(out->lx, out->ly) + 2 * PQ_AC + (out->has_alpha ? A_AC : 0);
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

// Adds `sum(coefficients[c] * cos_x[c * w + x])` over c to `out[x]`, in
// order of increasing c, for every column x of a row.
static inline void apply_columns(const float *RESTRICT coefficients,
                                 int32_t count, const float *RESTRICT cos_x,
                                 int32_t w, float *RESTRICT out) {
  for (int32_t c = 0; c < count; c++) {
    const float f = coefficients[c];
    const float *RESTRICT fx = cos_x + c * w;
    for (int32_t x = 0; x < w; x++) out[x] += f * fx[x];
  }
}

static inline void fill(float *out, int32_t n, float value) {
  for (int32_t i = 0; i < n; i++) out[i] = value;
}

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

  // The basis functions for every column (`cos_x[cx * w + x]`) and row, and
  // one row of each LPQA channel. Rows are computed a channel and a
  // component at a time, so that the inner loops run over contiguous
  // columns and vectorize.
  const bool cached = width <= MAX_CACHED_SIZE && height <= MAX_CACHED_SIZE;
  const size_t buffer_size =
      (size_t)(7 * width) +
      (cached ? 0 : (size_t)(MAX_COMPONENTS * (width + height)));
  float stack_buffer[7 * 64];
  float *buffer = buffer_size <= sizeof stack_buffer / sizeof(float)
                      ? stack_buffer
                      : (float *)malloc(sizeof(float) * buffer_size);
  if (buffer == NULL) return THUMBHASH_ERROR_OUT_OF_MEMORY;
  float *l = buffer;
  float *p = l + width;
  float *q = p + width;
  float *a = q + width;
  float *r = a + width;
  float *g = r + width;
  float *b = g + width;
  const float *cos_x, *cos_y;
  if (cached) {
    cos_tables(width, height, DECODE_ORDER, &cos_x, &cos_y);
  } else {
    float *tables = b + width;
    fill_cos_table(tables, width, DECODE_ORDER);
    fill_cos_table(tables + MAX_COMPONENTS * width, height, DECODE_ORDER);
    cos_x = tables;
    cos_y = tables + MAX_COMPONENTS * width;
  }

  const bool premultiply = (flags & THUMBHASH_DECODE_PREMULTIPLIED) != 0;
  const int32_t ny = max_i32(hd.ly, hd.has_alpha ? 5 : 3);
  float cos_y2[MAX_COMPONENTS];
  float l_row[MAX_COMPONENTS], p_row[3], q_row[3], a_row[5];
  uint8_t *out = rgba;
  for (int32_t y = 0; y < height; y++) {
    for (int32_t cy = 0; cy < ny; cy++) {
      cos_y2[cy] = 2.0f * cos_y[cy * height + y];
    }
    collapse_rows(l_ac, hd.lx, hd.ly, cos_y2, l_row);
    collapse_rows(p_ac, 3, 3, cos_y2, p_row);
    collapse_rows(q_ac, 3, 3, cos_y2, q_row);

    fill(l, width, hd.l_dc);
    fill(p, width, hd.p_dc);
    fill(q, width, hd.q_dc);
    apply_columns(l_row, hd.lx, cos_x, width, l);
    apply_columns(p_row, 3, cos_x, width, p);
    apply_columns(q_row, 3, cos_x, width, q);
    if (hd.has_alpha) {
      // The alpha terms are summed before adding the DC.
      collapse_rows(a_ac, 5, 5, cos_y2, a_row);
      fill(a, width, 0.0f);
      apply_columns(a_row, 5, cos_x, width, a);
      for (int32_t x = 0; x < width; x++) {
        a[x] = clamp01(hd.a_dc + a[x]) * 255.0f;
      }
    } else {
      fill(a, width, clamp01(hd.a_dc) * 255.0f);
    }

    // Convert to RGB, in a loop that vectorizes...
    for (int32_t x = 0; x < width; x++) {
      const float bx = l[x] - 2.0f / 3.0f * p[x];
      const float rx = (3.0f * l[x] - bx + q[x]) / 2.0f;
      const float gx = rx - q[x];
      r[x] = clamp01(rx) * 255.0f;
      g[x] = clamp01(gx) * 255.0f;
      b[x] = clamp01(bx) * 255.0f;
    }
    // ...then interleave the bytes.
    for (int32_t x = 0; x < width; x++, out += 4) {
      out[0] = (uint8_t)r[x];
      out[1] = (uint8_t)g[x];
      out[2] = (uint8_t)b[x];
      out[3] = (uint8_t)a[x];
    }
  }

  if (premultiply) {
    // Premultiply the bytes (rounding to nearest), so that both outputs
    // agree, like the Dart implementation.
    const int32_t n = width * height * 4;
    for (int32_t i = 0; i < n; i += 4) {
      const uint32_t alpha = rgba[i + 3];
      rgba[i] = (uint8_t)(((uint32_t)rgba[i] * alpha + 127) / 255);
      rgba[i + 1] = (uint8_t)(((uint32_t)rgba[i + 1] * alpha + 127) / 255);
      rgba[i + 2] = (uint8_t)(((uint32_t)rgba[i + 2] * alpha + 127) / 255);
    }
  }

  if (buffer != stack_buffer) free(buffer);
  return 0;
}
