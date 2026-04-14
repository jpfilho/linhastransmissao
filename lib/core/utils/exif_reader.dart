import 'dart:typed_data';
import 'package:exif/exif.dart';

class ExifData {
  final double? latitude;
  final double? longitude;
  final double? altitude;
  final DateTime? dateTime;
  final double? azimuth;
  final String? cameraModel;
  final int? imageWidth;
  final int? imageHeight;
  final Map<String, dynamic> raw;

  ExifData({
    this.latitude,
    this.longitude,
    this.altitude,
    this.dateTime,
    this.azimuth,
    this.cameraModel,
    this.imageWidth,
    this.imageHeight,
    this.raw = const {},
  });

  bool get hasGps => latitude != null && longitude != null;

  Map<String, dynamic> toJson() => {
    'latitude': latitude,
    'longitude': longitude,
    'altitude': altitude,
    'dateTime': dateTime?.toIso8601String(),
    'azimuth': azimuth,
    'cameraModel': cameraModel,
    'imageWidth': imageWidth,
    'imageHeight': imageHeight,
  };
}

class ExifReader {
  /// Extrai metadados EXIF de bytes de imagem
  static Future<ExifData> readFromBytes(Uint8List bytes) async {
    try {
      final data = await readExifFromBytes(bytes);
      if (data.isEmpty) return ExifData();

      return ExifData(
        latitude: _extractGpsCoordinate(data, 'GPS GPSLatitude', 'GPS GPSLatitudeRef'),
        longitude: _extractGpsCoordinate(data, 'GPS GPSLongitude', 'GPS GPSLongitudeRef'),
        altitude: _extractDouble(data, 'GPS GPSAltitude'),
        dateTime: _extractDateTime(data),
        azimuth: _extractDouble(data, 'GPS GPSImgDirection'),
        cameraModel: data['Image Model']?.toString(),
        imageWidth: _extractInt(data, 'EXIF ExifImageWidth'),
        imageHeight: _extractInt(data, 'EXIF ExifImageLength'),
        raw: {for (var e in data.entries) e.key: e.value.toString()},
      );
    } catch (e) {
      return ExifData();
    }
  }

  static double? _extractGpsCoordinate(
    Map<String, IfdTag> data,
    String coordKey,
    String refKey,
  ) {
    final coord = data[coordKey];
    final ref = data[refKey];
    if (coord == null) return null;

    try {
      final values = coord.values as IfdRatios;
      final degrees = values.ratios[0].numerator / values.ratios[0].denominator;
      final minutes = values.ratios[1].numerator / values.ratios[1].denominator;
      final seconds = values.ratios[2].numerator / values.ratios[2].denominator;

      double decimal = degrees + (minutes / 60) + (seconds / 3600);

      final refStr = ref?.toString().trim();
      if (refStr == 'S' || refStr == 'W') {
        decimal = -decimal;
      }

      return decimal;
    } catch (_) {
      return null;
    }
  }

  static double? _extractDouble(Map<String, IfdTag> data, String key) {
    final tag = data[key];
    if (tag == null) return null;
    try {
      final values = tag.values;
      if (values is IfdRatios && values.ratios.isNotEmpty) {
        return values.ratios[0].numerator / values.ratios[0].denominator;
      }
      return double.tryParse(tag.toString());
    } catch (_) {
      return null;
    }
  }

  static int? _extractInt(Map<String, IfdTag> data, String key) {
    final tag = data[key];
    if (tag == null) return null;
    try {
      return int.tryParse(tag.toString());
    } catch (_) {
      return null;
    }
  }

  static DateTime? _extractDateTime(Map<String, IfdTag> data) {
    final tag = data['EXIF DateTimeOriginal'] ??
                data['Image DateTime'] ??
                data['EXIF DateTimeDigitized'];
    if (tag == null) return null;
    try {
      // Format: "2024:01:15 14:30:00"
      final str = tag.toString().trim();
      final parts = str.split(' ');
      if (parts.length >= 2) {
        final dateParts = parts[0].replaceAll(':', '-');
        return DateTime.tryParse('${dateParts}T${parts[1]}');
      }
      return null;
    } catch (_) {
      return null;
    }
  }
}
