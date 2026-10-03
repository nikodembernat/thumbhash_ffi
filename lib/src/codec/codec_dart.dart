import 'dart:math' as math;
import 'dart:typed_data';

import 'package:thumbhash_ffi/src/hash_header.dart';

/// Whether the codec is backed by native code.
const isNativeCodec = false;

/// Encodes an RGBA image to a ThumbHash. The arguments must be validated.
///
/// A pure Dart port of `thumbhash_encode` from `src/thumbhash_ffi.c`, used
/// where `dart:ffi` is unavailable.
Uint8List encodeRgba(int w, int h, Uint8List rgba) {
  final n = w * h;

  // Determine the average color.
  var avgR = 0.0, avgG = 0.0, avgB = 0.0, avgA = 0.0;
  for (var i = 0; i < n * 4; i += 4) {
    final alpha = rgba[i + 3] / 255;
    avgR += alpha / 255 * rgba[i];
    avgG += alpha / 255 * rgba[i + 1];
    avgB += alpha / 255 * rgba[i + 2];
    avgA += alpha;
  }
  if (avgA > 0) {
    avgR /= avgA;
    avgG /= avgA;
    avgB /= avgA;
  }

  final hasAlpha = avgA < n;
  // Use fewer luminance bits if there's alpha.
  final lLimit = hasAlpha ? 5 : 7;
  final maxSide = math.max(w, h);
  final lx = math.max(1, (lLimit * w / maxSide).round());
  final ly = math.max(1, (lLimit * h / maxSide).round());

  // Convert the image from RGBA to LPQA (composite atop the average color).
  final l = Float64List(n); // luminance
  final p = Float64List(n); // yellow - blue
  final q = Float64List(n); // red - green
  final a = Float64List(n); // alpha
  for (var i = 0; i < n; i++) {
    final alpha = rgba[i * 4 + 3] / 255;
    final r = avgR * (1 - alpha) + alpha / 255 * rgba[i * 4];
    final g = avgG * (1 - alpha) + alpha / 255 * rgba[i * 4 + 1];
    final b = avgB * (1 - alpha) + alpha / 255 * rgba[i * 4 + 2];
    l[i] = (r + g + b) / 3;
    p[i] = (r + g) / 2 - b;
    q[i] = r - g;
    a[i] = alpha;
  }

  // Encode using the DCT into DC (constant) and normalized AC (varying) terms.
  final lNx = math.max(lx, 3);
  final lNy = math.max(ly, 3);
  final minComponents = hasAlpha ? 5 : 3;
  final cosX = _cosTable(w, math.max(lNx, minComponents));
  final cosY = _cosTable(h, math.max(lNy, minComponents));
  final rowSums = Float64List(w);
  final lChannel = _encodeChannel(l, w, h, lNx, lNy, cosX, cosY, rowSums);
  final pChannel = _encodeChannel(p, w, h, 3, 3, cosX, cosY, rowSums);
  final qChannel = _encodeChannel(q, w, h, 3, 3, cosX, cosY, rowSums);
  final aChannel = hasAlpha
      ? _encodeChannel(a, w, h, 5, 5, cosX, cosY, rowSums)
      : null;

  // Write the constants.
  final isLandscape = w > h;
  final header24 =
      _quantize(63 * lChannel.dc, 63) |
      (_quantize(31.5 + 31.5 * pChannel.dc, 63) << 6) |
      (_quantize(31.5 + 31.5 * qChannel.dc, 63) << 12) |
      (_quantize(31 * lChannel.scale, 31) << 18) |
      (hasAlpha ? 1 << 23 : 0);
  final header16 =
      (isLandscape ? ly : lx) |
      (_quantize(63 * pChannel.scale, 63) << 3) |
      (_quantize(63 * qChannel.scale, 63) << 9) |
      (isLandscape ? 1 << 15 : 0);

  final nibbles =
      lChannel.ac.length +
      pChannel.ac.length +
      qChannel.ac.length +
      (aChannel?.ac.length ?? 0);
  final acStart = hasAlpha ? 6 : 5;
  final hash = Uint8List(acStart + (nibbles + 1) ~/ 2)
    ..[0] = header24 & 255
    ..[1] = (header24 >> 8) & 255
    ..[2] = header24 >> 16
    ..[3] = header16 & 255
    ..[4] = header16 >> 8;
  if (aChannel != null) {
    hash[5] =
        _quantize(15 * aChannel.dc, 15) |
        (_quantize(15 * aChannel.scale, 15) << 4);
  }

  // Write the varying factors.
  var index = acStart * 2;
  for (final channel in [lChannel, pChannel, qChannel, ?aChannel]) {
    for (final f in channel.ac) {
      hash[index >> 1] |= _quantize(15 * f, 15) << ((index & 1) << 2);
      index++;
    }
  }

  return hash;
}

/// Decodes a ThumbHash to an RGBA image. The size must be validated.
///
/// A pure Dart port of `thumbhash_decode` from `src/thumbhash_ffi.c`, used
/// where `dart:ffi` is unavailable.
Uint8List decodeRgba(
  Uint8List hash,
  int width,
  int height, {
  required bool premultiplied,
}) {
  final header = HashHeader.parse(hash);
  final HashHeader(:lx, :ly, :hasAlpha) = header;

  // Read the varying factors (boost saturation by 1.25x to compensate for
  // quantization).
  var index = header.acStart * 2;
  Float64List readAc(int nx, int ny, double scale) {
    final ac = Float64List(nx * ny);
    for (var cy = 0; cy < ny; cy++) {
      for (var cx = cy > 0 ? 0 : 1; cx * ny < nx * (ny - cy); cx++) {
        final bits = (hash[index >> 1] >> ((index & 1) << 2)) & 15;
        index++;
        ac[cy * nx + cx] = (bits / 7.5 - 1) * scale;
      }
    }

    return ac;
  }

  final lAc = readAc(lx, ly, header.lScale);
  final pAc = readAc(3, 3, header.pScale * 1.25);
  final qAc = readAc(3, 3, header.qScale * 1.25);
  final aAc = hasAlpha ? readAc(5, 5, header.aScale) : null;

  // Precompute the horizontal basis functions for every column.
  final nx = math.max(lx, hasAlpha ? 5 : 3);
  final ny = math.max(ly, hasAlpha ? 5 : 3);
  final cosX = Float64List(nx * width);
  for (var x = 0; x < width; x++) {
    for (var cx = 0; cx < nx; cx++) {
      cosX[x * nx + cx] = math.cos(math.pi / width * (x + 0.5) * cx);
    }
  }

  final rgba = Uint8List(width * height * 4);
  final cosY2 = Float64List(ny);
  final lRow = Float64List(lx);
  final pRow = Float64List(3);
  final qRow = Float64List(3);
  final aRow = Float64List(5);
  var out = 0;
  for (var y = 0; y < height; y++) {
    for (var cy = 0; cy < ny; cy++) {
      cosY2[cy] = 2 * math.cos(math.pi / height * (y + 0.5) * cy);
    }
    _collapseRows(lAc, lx, ly, cosY2, lRow);
    _collapseRows(pAc, 3, 3, cosY2, pRow);
    _collapseRows(qAc, 3, 3, cosY2, qRow);
    if (aAc != null) {
      _collapseRows(aAc, 5, 5, cosY2, aRow);
    }

    for (var x = 0; x < width; x++) {
      final fx = x * nx;
      var l = header.lDc;
      for (var cx = 0; cx < lx; cx++) {
        l += lRow[cx] * cosX[fx + cx];
      }
      final p =
          header.pDc +
          pRow[0] * cosX[fx] +
          pRow[1] * cosX[fx + 1] +
          pRow[2] * cosX[fx + 2];
      final q =
          header.qDc +
          qRow[0] * cosX[fx] +
          qRow[1] * cosX[fx + 1] +
          qRow[2] * cosX[fx + 2];
      var a = header.aDc;
      if (hasAlpha) {
        a +=
            aRow[0] * cosX[fx] +
            aRow[1] * cosX[fx + 1] +
            aRow[2] * cosX[fx + 2] +
            aRow[3] * cosX[fx + 3] +
            aRow[4] * cosX[fx + 4];
      }

      // Convert to RGB.
      final b = l - 2 / 3 * p;
      final r = (3 * l - b + q) / 2;
      final g = r - q;
      final alpha = _clamp01(a);
      final factor = premultiplied ? alpha * 255 : 255;
      rgba[out] = (_clamp01(r) * factor).toInt();
      rgba[out + 1] = (_clamp01(g) * factor).toInt();
      rgba[out + 2] = (_clamp01(b) * factor).toInt();
      rgba[out + 3] = (alpha * 255).toInt();
      out += 4;
    }
  }

  return rgba;
}

typedef _EncodedChannel = ({double dc, double scale, List<double> ac});

_EncodedChannel _encodeChannel(
  Float64List channel,
  int w,
  int h,
  int nx,
  int ny,
  Float64List cosX,
  Float64List cosY,
  Float64List rowSums,
) {
  final area = w * h;
  var dc = 0.0;
  var scale = 0.0;
  final ac = <double>[];
  for (var cy = 0; cy < ny; cy++) {
    // Collapse the rows with the vertical basis function first...
    rowSums.fillRange(0, w, 0);
    for (var y = 0; y < h; y++) {
      final f = cosY[cy * h + y];
      final row = y * w;
      for (var x = 0; x < w; x++) {
        rowSums[x] += channel[row + x] * f;
      }
    }

    // ...then apply each horizontal basis function to the collapsed row.
    for (var cx = 0; cx * ny < nx * (ny - cy); cx++) {
      var f = 0.0;
      for (var x = 0; x < w; x++) {
        f += rowSums[x] * cosX[cx * w + x];
      }
      f /= area;
      if (cx > 0 || cy > 0) {
        ac.add(f);
        scale = math.max(scale, f.abs());
      } else {
        dc = f;
      }
    }
  }

  if (scale > 0) {
    for (var i = 0; i < ac.length; i++) {
      ac[i] = 0.5 + 0.5 / scale * ac[i];
    }
  }

  return (dc: dc, scale: scale, ac: ac);
}

void _collapseRows(
  Float64List ac,
  int nx,
  int ny,
  Float64List cosY2,
  Float64List out,
) {
  out.fillRange(0, nx, 0);
  for (var cy = 0; cy < ny; cy++) {
    final f = cosY2[cy];
    for (var cx = 0; cx < nx; cx++) {
      out[cx] += ac[cy * nx + cx] * f;
    }
  }
}

/// Fills `table[c * n + i]` with cos(pi / n * c * (i + 0.5)).
Float64List _cosTable(int n, int components) {
  final table = Float64List(n * components);
  for (var c = 0; c < components; c++) {
    for (var i = 0; i < n; i++) {
      table[c * n + i] = math.cos(math.pi / n * c * (i + 0.5));
    }
  }

  return table;
}

/// Rounds half away from zero and saturates to [0, max].
int _quantize(double v, int max) => v.round().clamp(0, max);

double _clamp01(double v) => v < 0 ? 0 : (v > 1 ? 1 : v);
