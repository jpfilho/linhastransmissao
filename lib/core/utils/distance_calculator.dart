import 'dart:math';

class DistanceCalculator {
  static const double _earthRadiusM = 6371000;

  /// Calcula distância entre dois pontos usando Haversine (retorna metros)
  static double haversine(
    double lat1, double lng1,
    double lat2, double lng2,
  ) {
    final dLat = _toRadians(lat2 - lat1);
    final dLng = _toRadians(lng2 - lng1);
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_toRadians(lat1)) * cos(_toRadians(lat2)) *
        sin(dLng / 2) * sin(dLng / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return _earthRadiusM * c;
  }

  static double _toRadians(double degrees) => degrees * pi / 180;

  /// Encontra a torre mais próxima e retorna (index, distância)
  static MapEntry<int, double>? findNearestTower(
    double photoLat, double photoLng,
    List<Map<String, double>> towers,
  ) {
    if (towers.isEmpty) return null;

    int nearestIndex = 0;
    double nearestDistance = double.infinity;

    for (int i = 0; i < towers.length; i++) {
      final d = haversine(
        photoLat, photoLng,
        towers[i]['lat']!, towers[i]['lng']!,
      );
      if (d < nearestDistance) {
        nearestDistance = d;
        nearestIndex = i;
      }
    }

    return MapEntry(nearestIndex, nearestDistance);
  }

  /// Verifica se há ambiguidade (segunda torre muito próxima)
  static bool isAmbiguous(
    double photoLat, double photoLng,
    List<Map<String, double>> towers, {
    double threshold = 0.2,
  }) {
    if (towers.length < 2) return false;

    final distances = towers
        .map((t) => haversine(photoLat, photoLng, t['lat']!, t['lng']!))
        .toList()
      ..sort();

    return (distances[1] - distances[0]) < distances[0] * threshold;
  }
}
