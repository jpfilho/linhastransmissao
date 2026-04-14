import 'package:uuid/uuid.dart';
import '../../features/torres/models/torre.dart';
import '../../features/fotos/models/foto.dart';
import '../../features/anomalias/models/anomalia.dart';
import '../models/linha.dart';
import '../models/campanha.dart';
import '../data/kml_raw_data.dart';

const _uuid = Uuid();

class MockData {
  static List<Linha> linhas = [];
  static List<Torre> _torres = [];
  static List<Foto> _fotos = [];
  static List<Anomalia> _anomalias = [];
  static List<Campanha> _campanhas = [];
  static bool _initialized = false;

  static void initialize() {
    if (_initialized) return;

    _campanhas = [
      Campanha(
        id: _uuid.v4(), nome: 'Campanha Mar/2026',
        descricao: 'Inspeção aérea trimestral',
        dataInicio: DateTime(2026, 3, 1), dataFim: DateTime(2026, 3, 15),
        status: 'concluida',
      ),
      Campanha(
        id: _uuid.v4(), nome: 'Campanha Dez/2025',
        descricao: 'Inspeção pós-chuvas',
        dataInicio: DateTime(2025, 12, 1), dataFim: DateTime(2025, 12, 20),
        status: 'concluida',
      ),
      Campanha(
        id: _uuid.v4(), nome: 'Campanha Jun/2025',
        descricao: 'Inspeção semestral',
        dataInicio: DateTime(2025, 6, 10), dataFim: DateTime(2025, 6, 25),
        status: 'concluida',
      ),
    ];

    // Load real data from pre-processed KML
    _loadFromKmlData();
    _generatePhotosAndAnomalias();
    _initialized = true;
  }

  /// Load real transmission line and tower data from the pre-processed KML file.
  static void _loadFromKmlData() {
    linhas = [];
    _torres = [];

    for (int i = 0; i < KmlRawData.lineNames.length; i++) {
      final lineName = KmlRawData.lineNames[i];
      final lineId = 'line_${i.toString().padLeft(3, '0')}';
      final towerData = KmlRawData.towers[lineName] ?? [];

      linhas.add(Linha(
        id: lineId,
        nome: lineName,
        codigo: lineName,
        regional: 'DONTT',
        tensao: '500kV',
        extensaoKm: towerData.length * 0.4,
        totalTorres: towerData.length,
      ));

      for (int j = 0; j < towerData.length; j++) {
        final td = towerData[j];
        final towerId = td[0] as String;
        final lat = (td[1] as num).toDouble();
        final lon = (td[2] as num).toDouble();
        final alt = (td[3] as num).toDouble();
        final torreId = '${lineId}_t${j.toString().padLeft(3, '0')}';

        _torres.add(Torre(
          id: torreId,
          linhaId: lineId,
          codigoTorre: '$lineName $towerId',
          descricao: 'Torre $towerId - $lineName',
          latitude: lat,
          longitude: lon,
          altitude: alt,
          tipo: 'Suspensão',
          criticidadeAtual: 'baixa',
          linhaNome: lineName,
          totalFotos: 0,
          totalAnomalias: 0,
        ));
      }
    }
  }

  /// Generate sample photos and anomalies for a subset of towers.
  static void _generatePhotosAndAnomalias() {
    _fotos = [];
    _anomalias = [];

    // Pick a small sample of towers for demo photos
    final sampleTowers = <Torre>[];
    for (final linha in linhas) {
      final lineTowers = _torres.where((t) => t.linhaId == linha.id).toList();
      if (lineTowers.length > 5) {
        sampleTowers.addAll(lineTowers.take(3));
        sampleTowers.addAll(lineTowers.skip(lineTowers.length - 2));
      } else {
        sampleTowers.addAll(lineTowers);
      }
    }

    for (int i = 0; i < sampleTowers.length; i++) {
      final torre = sampleTowers[i];
      final numFotos = 2 + (i % 3);
      for (int j = 0; j < numFotos; j++) {
        _fotos.add(Foto(
          id: '${torre.id}_f$j',
          campanhaId: _campanhas[j % _campanhas.length].id,
          linhaId: torre.linhaId,
          torreId: torre.id,
          nomeArquivo: 'IMG_${torre.codigoTorre.replaceAll(' ', '_')}_${j + 1}.jpg',
          caminhoStorage: 'fotos-inspecao/${torre.codigoTorre.replaceAll(' ', '_')}/IMG_${j + 1}.jpg',
          latitude: torre.latitude + (j * 0.0005),
          longitude: torre.longitude + (j * 0.0005),
          altitude: (torre.altitude ?? 100) + 50,
          dataHoraCaptura: DateTime(2026, 3, 10 + j, 8 + j, 30),
          azimute: (45.0 * j) % 360,
          distanciaTorreM: 15.0 + j * 8.0,
          statusAssociacao: 'associada',
          qualidadeImagem: 0.5 + (j % 3) * 0.2,
          statusAvaliacao: j % 2 == 0 ? 'avaliada' : 'nao_avaliada',
          torreCodigo: torre.codigoTorre,
          linhaNome: torre.linhaNome ?? '',
          campanhaNome: _campanhas[j % _campanhas.length].nome,
        ));
      }
    }
  }

  static List<Torre> get torres => _torres;
  static List<Foto> get fotos => _fotos;
  static List<Anomalia> get anomalias => _anomalias;
  static List<Campanha> get campanhas => _campanhas;

  // Dashboard stats
  static Map<String, dynamic> get dashboardStats => {
    'total_linhas': linhas.length,
    'total_torres': _torres.length,
    'total_fotos': _fotos.length,
    'fotos_sem_associacao': _fotos.where((f) => f.statusAssociacao == 'pendente' || f.statusAssociacao == 'sem_gps').length,
    'fotos_sem_avaliacao': _fotos.where((f) => f.statusAvaliacao == 'nao_avaliada').length,
    'torres_criticas': _torres.where((t) => t.criticidadeAtual == 'alta' || t.criticidadeAtual == 'critica').length,
    'anomalias_abertas': _anomalias.where((a) => a.status != 'resolvida').length,
    'campanhas_ativas': _campanhas.where((c) => c.status == 'em_andamento').length,
  };

  static Map<String, int> get anomaliasPorTipo {
    final map = <String, int>{};
    for (final a in _anomalias) {
      map[a.tipo] = (map[a.tipo] ?? 0) + 1;
    }
    return map;
  }

  static Map<String, int> get fotosPorCampanha {
    final map = <String, int>{};
    for (final c in _campanhas) {
      map[c.nome] = _fotos.where((f) => f.campanhaId == c.id).length;
    }
    return map;
  }

  static Map<String, int> get criticidadeDistribuicao {
    final map = <String, int>{'baixa': 0, 'media': 0, 'alta': 0, 'critica': 0};
    for (final t in _torres) {
      map[t.criticidadeAtual] = (map[t.criticidadeAtual] ?? 0) + 1;
    }
    return map;
  }

  static List<Torre> getTorresByLinha(String linhaId) =>
      _torres.where((t) => t.linhaId == linhaId).toList();

  static List<Foto> getFotosByTorre(String torreId) =>
      _fotos.where((f) => f.torreId == torreId).toList();

  static List<Anomalia> getAnomaliasByTorre(String torreId) =>
      _anomalias.where((a) => a.torreId == torreId).toList();

  static Torre? getTorreById(String id) {
    try {
      return _torres.firstWhere((t) => t.id == id);
    } catch (_) {
      return null;
    }
  }

  static Foto? getFotoById(String id) {
    try {
      return _fotos.firstWhere((f) => f.id == id);
    } catch (_) {
      return null;
    }
  }

  static Linha? getLinhaById(String id) {
    try {
      return linhas.firstWhere((l) => l.id == id);
    } catch (_) {
      return null;
    }
  }

  /// Add imported photos to the data store and update tower photo counts.
  static void addImportedPhotos(List<Foto> photos) {
    _fotos.addAll(photos);

    // Update tower totalFotos counts
    for (final foto in photos) {
      if (foto.torreId != null) {
        final tIdx = _torres.indexWhere((t) => t.id == foto.torreId);
        if (tIdx >= 0) {
          final torre = _torres[tIdx];
          _torres[tIdx] = Torre(
            id: torre.id,
            linhaId: torre.linhaId,
            codigoTorre: torre.codigoTorre,
            descricao: torre.descricao,
            latitude: torre.latitude,
            longitude: torre.longitude,
            altitude: torre.altitude,
            tipo: torre.tipo,
            criticidadeAtual: torre.criticidadeAtual,
            linhaNome: torre.linhaNome,
            totalFotos: (torre.totalFotos ?? 0) + 1,
            totalAnomalias: torre.totalAnomalias,
          );
        }
      }
    }
  }

  /// Add a new campaign.
  static Campanha addCampanha(String nome, String descricao) {
    final campanha = Campanha(
      id: _uuid.v4(),
      nome: nome,
      descricao: descricao,
      dataInicio: DateTime.now(),
      dataFim: DateTime.now(),
      status: 'em_andamento',
    );
    _campanhas.add(campanha);
    return campanha;
  }
}
