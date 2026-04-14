import 'dart:io';
import 'package:xml/xml.dart';
import '../../features/torres/models/torre.dart';
import '../models/linha.dart';

/// Service responsible for parsing the KML file and extracting
/// real transmission line and tower data.
class KmlDataService {
  /// Parses a KML file and returns extracted lines and towers.
  static Future<KmlParseResult> parseKmlFile(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw Exception('KML file not found: $filePath');
    }

    final content = await file.readAsString();
    return parseKmlContent(content);
  }

  /// Parses KML content string and returns extracted lines and towers.
  static KmlParseResult parseKmlContent(String content) {
    final document = XmlDocument.parse(content);

    // Find all Placemark elements
    final placemarks = document.findAllElements('Placemark');

    // Group by line name (first word of description)
    final Map<String, List<_RawTower>> lineGroups = {};

    for (final pm in placemarks) {
      // Only process placemarks that have Point coordinates
      final pointElem = pm.findElements('Point').firstOrNull;
      if (pointElem == null) continue;

      final coordsElem = pointElem.findElements('coordinates').firstOrNull;
      if (coordsElem == null) continue;

      final descElem = pm.findElements('description').firstOrNull;
      if (descElem == null) continue;

      final nameElem = pm.findElements('name').firstOrNull;

      final description = descElem.innerText.trim();
      final coordsText = coordsElem.innerText.trim();

      // Parse line name and tower ID from description
      // Format: "LINENAME TOWER-ID" (e.g., "BEATSAU1 100-1")
      final parts = description.split(RegExp(r'\s+'));
      final lineName = parts[0];
      final towerId = parts.length >= 2 ? parts.sublist(1).join(' ') : (nameElem?.innerText.trim() ?? '');

      // Parse coordinates: "lon,lat,alt"
      final coordParts = coordsText.split(',');
      if (coordParts.length < 2) continue;

      final lon = double.tryParse(coordParts[0].trim());
      final lat = double.tryParse(coordParts[1].trim());
      final alt = coordParts.length > 2 ? double.tryParse(coordParts[2].trim()) : 0.0;

      if (lon == null || lat == null) continue;

      lineGroups.putIfAbsent(lineName, () => []);

      // Only add unique towers (by tower ID within the same line)
      final existing = lineGroups[lineName]!.any((t) => t.towerId == towerId);
      if (!existing) {
        lineGroups[lineName]!.add(_RawTower(
          towerId: towerId,
          latitude: lat,
          longitude: lon,
          altitude: alt ?? 0.0,
        ));
      }
    }

    // Convert to Linha and Torre models
    final linhas = <Linha>[];
    final torres = <Torre>[];
    final sortedKeys = lineGroups.keys.toList()..sort();

    for (int i = 0; i < sortedKeys.length; i++) {
      final lineName = sortedKeys[i];
      final rawTowers = lineGroups[lineName]!;
      final lineId = 'line_${i.toString().padLeft(3, '0')}';

      final extensao = rawTowers.length * 0.4; // Approximate km

      linhas.add(Linha(
        id: lineId,
        nome: lineName,
        codigo: lineName,
        regional: 'DONTT',
        tensao: '500kV',
        extensaoKm: extensao,
        totalTorres: rawTowers.length,
      ));

      // Sort towers by towerId for consistent ordering
      rawTowers.sort((a, b) => _naturalCompare(a.towerId, b.towerId));

      for (int j = 0; j < rawTowers.length; j++) {
        final rt = rawTowers[j];
        final torreId = '${lineId}_t${j.toString().padLeft(3, '0')}';

        torres.add(Torre(
          id: torreId,
          linhaId: lineId,
          codigoTorre: '$lineName ${ rt.towerId}',
          descricao: 'Torre ${rt.towerId} - $lineName',
          latitude: rt.latitude,
          longitude: rt.longitude,
          altitude: rt.altitude,
          tipo: 'Suspensão',
          criticidadeAtual: 'baixa',
          linhaNome: lineName,
          totalFotos: 0,
          totalAnomalias: 0,
        ));
      }
    }

    return KmlParseResult(
      linhas: linhas,
      torres: torres,
      totalPlacemarks: placemarks.length,
    );
  }

  /// Natural sort comparison for tower IDs like "1-1", "2-1", "10-1"
  static int _naturalCompare(String a, String b) {
    // Split by non-digit characters
    final aParts = a.split(RegExp(r'[-\s]'));
    final bParts = b.split(RegExp(r'[-\s]'));

    for (int i = 0; i < aParts.length && i < bParts.length; i++) {
      final aNum = int.tryParse(aParts[i]);
      final bNum = int.tryParse(bParts[i]);

      if (aNum != null && bNum != null) {
        if (aNum != bNum) return aNum.compareTo(bNum);
      } else {
        final cmp = aParts[i].compareTo(bParts[i]);
        if (cmp != 0) return cmp;
      }
    }
    return aParts.length.compareTo(bParts.length);
  }
}

class _RawTower {
  final String towerId;
  final double latitude;
  final double longitude;
  final double altitude;

  _RawTower({
    required this.towerId,
    required this.latitude,
    required this.longitude,
    required this.altitude,
  });
}

class KmlParseResult {
  final List<Linha> linhas;
  final List<Torre> torres;
  final int totalPlacemarks;

  KmlParseResult({
    required this.linhas,
    required this.torres,
    required this.totalPlacemarks,
  });
}
