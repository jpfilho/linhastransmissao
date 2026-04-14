import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

class KmzParseResult {
  final List<ParsedLine> lines;
  final List<ParsedTower> towers;
  final List<String> errors;
  final List<String> warnings;

  KmzParseResult({
    required this.lines,
    required this.towers,
    this.errors = const [],
    this.warnings = const [],
  });

  int get totalElements => lines.length + towers.length;
  bool get hasErrors => errors.isNotEmpty;
}

class ParsedLine {
  final String name;
  final String? description;
  final String? code;
  final List<List<double>> coordinates; // [[lng, lat, alt], ...]
  final Map<String, String> attributes;

  ParsedLine({
    required this.name,
    this.description,
    this.code,
    required this.coordinates,
    this.attributes = const {},
  });
}

class ParsedTower {
  final String name;
  final String? description;
  final String? code;
  final double latitude;
  final double longitude;
  final double? altitude;
  final Map<String, String> attributes;

  ParsedTower({
    required this.name,
    this.description,
    this.code,
    required this.latitude,
    required this.longitude,
    this.altitude,
    this.attributes = const {},
  });
}

class KmzParser {
  /// Parse KMZ file bytes
  static KmzParseResult parseKmz(Uint8List bytes) {

    try {
      // Descompactar KMZ (que é um ZIP)
      final archive = ZipDecoder().decodeBytes(bytes);

      // Encontrar arquivo KML
      ArchiveFile? kmlFile;
      for (final file in archive.files) {
        if (file.name.toLowerCase().endsWith('.kml')) {
          kmlFile = file;
          break;
        }
      }

      if (kmlFile == null) {
        return KmzParseResult(
          lines: [],
          towers: [],
          errors: ['Nenhum arquivo KML encontrado dentro do KMZ'],
        );
      }

      final kmlContent = String.fromCharCodes(kmlFile.content as List<int>);
      return parseKml(kmlContent);
    } catch (e) {
      return KmzParseResult(
        lines: [],
        towers: [],
        errors: ['Erro ao descompactar KMZ: $e'],
      );
    }
  }

  /// Parse KML string
  static KmzParseResult parseKml(String kmlContent) {
    final lines = <ParsedLine>[];
    final towers = <ParsedTower>[];
    final errors = <String>[];
    final warnings = <String>[];

    try {
      final document = XmlDocument.parse(kmlContent);
      final placemarks = document.findAllElements('Placemark');

      if (placemarks.isEmpty) {
        warnings.add('Nenhum Placemark encontrado no KML');
      }

      for (final placemark in placemarks) {
        try {
          _parsePlacemark(placemark, lines, towers, warnings);
        } catch (e) {
          final name = placemark.findElements('name').firstOrNull?.innerText ?? 'desconhecido';
          errors.add('Erro ao processar "$name": $e');
        }
      }

      if (towers.isEmpty && lines.isEmpty) {
        warnings.add('Nenhuma geometria válida encontrada no KML');
      }
    } catch (e) {
      errors.add('Erro ao interpretar arquivo KML: $e');
    }

    return KmzParseResult(
      lines: lines,
      towers: towers,
      errors: errors,
      warnings: warnings,
    );
  }

  static void _parsePlacemark(
    XmlElement placemark,
    List<ParsedLine> lines,
    List<ParsedTower> towers,
    List<String> warnings,
  ) {
    final name = placemark.findElements('name').firstOrNull?.innerText ?? 'Sem nome';
    final description = placemark.findElements('description').firstOrNull?.innerText;

    // Extrair atributos do ExtendedData
    final attributes = <String, String>{};
    final extData = placemark.findElements('ExtendedData').firstOrNull;
    if (extData != null) {
      for (final data in extData.findElements('Data')) {
        final key = data.getAttribute('name') ?? '';
        final value = data.findElements('value').firstOrNull?.innerText ?? '';
        if (key.isNotEmpty) attributes[key] = value;
      }
      // Also try SimpleData within SchemaData
      for (final schemaData in extData.findElements('SchemaData')) {
        for (final sd in schemaData.findElements('SimpleData')) {
          final key = sd.getAttribute('name') ?? '';
          final value = sd.innerText;
          if (key.isNotEmpty) attributes[key] = value;
        }
      }
    }

    // Verificar se é Point (torre) ou LineString (linha)
    final point = placemark.findElements('Point').firstOrNull;
    final lineString = placemark.findElements('LineString').firstOrNull;
    final multiGeometry = placemark.findElements('MultiGeometry').firstOrNull;

    if (point != null) {
      final coords = _parseCoordinates(
        point.findElements('coordinates').firstOrNull?.innerText ?? '',
      );
      if (coords.isNotEmpty) {
        towers.add(ParsedTower(
          name: name,
          description: description,
          code: attributes['codigo'] ?? attributes['code'] ?? attributes['id'] ?? name,
          latitude: coords[0][1],
          longitude: coords[0][0],
          altitude: coords[0].length > 2 ? coords[0][2] : null,
          attributes: attributes,
        ));
      } else {
        warnings.add('Torre "$name" sem coordenadas válidas');
      }
    } else if (lineString != null) {
      final coords = _parseCoordinates(
        lineString.findElements('coordinates').firstOrNull?.innerText ?? '',
      );
      if (coords.isNotEmpty) {
        lines.add(ParsedLine(
          name: name,
          description: description,
          code: attributes['codigo'] ?? attributes['code'] ?? name,
          coordinates: coords,
          attributes: attributes,
        ));
      } else {
        warnings.add('Linha "$name" sem coordenadas válidas');
      }
    } else if (multiGeometry != null) {
      // Processar geometrias múltiplas
      for (final p in multiGeometry.findElements('Point')) {
        final coords = _parseCoordinates(
          p.findElements('coordinates').firstOrNull?.innerText ?? '',
        );
        if (coords.isNotEmpty) {
          towers.add(ParsedTower(
            name: name,
            description: description,
            code: attributes['codigo'] ?? attributes['code'] ?? name,
            latitude: coords[0][1],
            longitude: coords[0][0],
            altitude: coords[0].length > 2 ? coords[0][2] : null,
            attributes: attributes,
          ));
        }
      }
      for (final ls in multiGeometry.findElements('LineString')) {
        final coords = _parseCoordinates(
          ls.findElements('coordinates').firstOrNull?.innerText ?? '',
        );
        if (coords.isNotEmpty) {
          lines.add(ParsedLine(
            name: name,
            description: description,
            code: attributes['codigo'] ?? attributes['code'] ?? name,
            coordinates: coords,
            attributes: attributes,
          ));
        }
      }
    } else {
      warnings.add('Placemark "$name" sem geometria reconhecida');
    }
  }

  /// Parse "lng,lat,alt lng,lat,alt ..." → [[lng, lat, alt], ...]
  static List<List<double>> _parseCoordinates(String coordString) {
    final coords = <List<double>>[];
    final trimmed = coordString.trim();
    if (trimmed.isEmpty) return coords;

    final tuples = trimmed.split(RegExp(r'\s+'));
    for (final tuple in tuples) {
      final parts = tuple.split(',');
      if (parts.length >= 2) {
        final lng = double.tryParse(parts[0].trim());
        final lat = double.tryParse(parts[1].trim());
        if (lng != null && lat != null) {
          final alt = parts.length > 2 ? double.tryParse(parts[2].trim()) : null;
          coords.add([lng, lat, ?alt]);
        }
      }
    }
    return coords;
  }
}
