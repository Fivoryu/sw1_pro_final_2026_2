import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

/// Local photo quality validation of the guided capture (F14.2).
///
/// These are documented heuristics on the photo's pixels, not an AI model:
/// size, average brightness and the variance of the Laplacian as a blur
/// measure. The thresholds were chosen by hand and are not calibrated
/// against a set of real listing photos.
class PhotoQualityRules {
  const PhotoQualityRules({
    this.minShortSide = 720,
    this.minBrightness = 50,
    this.maxBrightness = 220,
    this.minSharpness = 25,
  });

  /// Shorter side of the original photo, in pixels.
  final int minShortSide;

  /// Mean luma (0–255) below which the photo is too dark.
  final double minBrightness;

  /// Mean luma (0–255) above which the photo is overexposed.
  final double maxBrightness;

  /// Variance of the Laplacian below which the photo is blurry, measured on
  /// the photo scaled down to [analysisSide] pixels on its longer side.
  final double minSharpness;

  static const int analysisSide = 640;
}

/// What the validation measured on one photo.
class PhotoMeasurements {
  const PhotoMeasurements({
    required this.width,
    required this.height,
    required this.brightness,
    required this.sharpness,
  });

  /// Size of the original photo.
  final int width;
  final int height;

  /// Mean luma, 0–255.
  final double brightness;

  /// Variance of the 4-neighbour Laplacian on the scaled-down luma.
  final double sharpness;
}

/// Reads [bytes] and measures them; throws [PhotoAnalysisFailure] when the
/// photo cannot be decoded on this device.
typedef PhotoAnalyzer = Future<PhotoMeasurements> Function(Uint8List bytes);

class PhotoAnalysisFailure implements Exception {
  const PhotoAnalysisFailure();
}

/// Why a photo does not pass [rules]; empty when it passes.
List<String> assessPhoto(
  PhotoMeasurements measured, [
  PhotoQualityRules rules = const PhotoQualityRules(),
]) {
  final reasons = <String>[];
  final shortSide = math.min(measured.width, measured.height);
  if (shortSide < rules.minShortSide) {
    reasons.add(
      'La foto es muy chica (${measured.width}×${measured.height} px). '
      'Usá la cámara del teléfono: hace falta al menos '
      '${rules.minShortSide} px en el lado menor.',
    );
  }
  if (measured.brightness < rules.minBrightness) {
    reasons.add(
      'La foto está muy oscura. Encendé las luces o abrí las cortinas.',
    );
  } else if (measured.brightness > rules.maxBrightness) {
    reasons.add(
      'La foto está sobreexpuesta. Evitá apuntar a una ventana o a una luz directa.',
    );
  }
  if (measured.sharpness < rules.minSharpness) {
    reasons.add(
      'La foto está movida o desenfocada. Sostené el teléfono firme y repetila.',
    );
  }
  return reasons;
}

/// Mean luma and Laplacian variance of a grayscale image of [width]×[height]
/// stored row by row in [luma].
({double brightness, double sharpness}) measureLuma(
  int width,
  int height,
  Uint8List luma,
) {
  if (width <= 0 || height <= 0 || luma.length < width * height) {
    throw ArgumentError('luma does not match the size');
  }
  var sum = 0;
  for (var i = 0; i < width * height; i++) {
    sum += luma[i];
  }
  final brightness = sum / (width * height);
  if (width < 3 || height < 3) return (brightness: brightness, sharpness: 0);

  var count = 0;
  var mean = 0.0;
  var m2 = 0.0;
  for (var y = 1; y < height - 1; y++) {
    for (var x = 1; x < width - 1; x++) {
      final i = y * width + x;
      final laplacian =
          luma[i - width] +
          luma[i + width] +
          luma[i - 1] +
          luma[i + 1] -
          4 * luma[i];
      count++;
      final delta = laplacian - mean;
      mean += delta / count;
      m2 += delta * (laplacian - mean);
    }
  }
  return (brightness: brightness, sharpness: m2 / count);
}

/// Decodes [bytes] with the platform codecs, scaled down for speed, and
/// measures them. HEIC/HEIF decoding depends on the device.
Future<PhotoMeasurements> analyzePhotoBytes(Uint8List bytes) async {
  try {
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    final descriptor = await ui.ImageDescriptor.encoded(buffer);
    final width = descriptor.width;
    final height = descriptor.height;
    final longer = math.max(width, height);
    final scale = longer > PhotoQualityRules.analysisSide
        ? PhotoQualityRules.analysisSide / longer
        : 1.0;
    final codec = await descriptor.instantiateCodec(
      targetWidth: math.max(1, (width * scale).round()),
      targetHeight: math.max(1, (height * scale).round()),
    );
    final frame = await codec.getNextFrame();
    final image = frame.image;
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    final scaledWidth = image.width;
    final scaledHeight = image.height;
    image.dispose();
    codec.dispose();
    descriptor.dispose();
    buffer.dispose();
    if (data == null) throw const PhotoAnalysisFailure();
    final rgba = data.buffer.asUint8List(
      data.offsetInBytes,
      data.lengthInBytes,
    );
    final luma = Uint8List(scaledWidth * scaledHeight);
    for (var i = 0; i < luma.length; i++) {
      final p = i * 4;
      // ITU-R BT.601 luma, in integer arithmetic.
      luma[i] = (299 * rgba[p] + 587 * rgba[p + 1] + 114 * rgba[p + 2]) ~/ 1000;
    }
    final measured = measureLuma(scaledWidth, scaledHeight, luma);
    return PhotoMeasurements(
      width: width,
      height: height,
      brightness: measured.brightness,
      sharpness: measured.sharpness,
    );
  } on PhotoAnalysisFailure {
    rethrow;
  } catch (_) {
    throw const PhotoAnalysisFailure();
  }
}
