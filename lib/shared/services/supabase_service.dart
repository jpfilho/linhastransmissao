import 'dart:typed_data';
import 'dart:convert';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../features/torres/models/torre.dart';
import '../../features/fotos/models/foto.dart';
import '../../features/anomalias/models/anomalia.dart';
import '../../core/utils/distance_calculator.dart';
import '../models/linha.dart';
import '../models/campanha.dart';
import '../models/chat_model.dart';

/// Service layer for Supabase database and storage operations.
class SupabaseService {
  static SupabaseClient get _client => Supabase.instance.client;
  /// Public access for views that need direct table queries.
  static SupabaseClient get client => Supabase.instance.client;

  // ═══════════════════════════════════════════════════════
  // LINHAS
  // ═══════════════════════════════════════════════════════

  static Future<List<Linha>> getLinhas() async {
    final data = await _client
        .from('linhas')
        .select()
        .order('nome');
    return data.map<Linha>((json) => Linha.fromJson(json)).toList();
  }

  static Future<Linha?> getLinhaById(String id) async {
    final data = await _client
        .from('linhas')
        .select()
        .eq('id', id)
        .maybeSingle();
    return data != null ? Linha.fromJson(data) : null;
  }

  // ═══════════════════════════════════════════════════════
  // TORRES
  // ═══════════════════════════════════════════════════════

  static Future<List<Torre>> getTorres({String? linhaId, int? limit}) async {
    // Supabase has a default 1000 row limit, so we paginate to get all towers
    final allData = <Map<String, dynamic>>[];
    const batchSize = 1000;
    int offset = 0;
    while (true) {
      var query = _client
          .from('torres')
          .select('*, linhas(nome)');
      if (linhaId != null) {
        query = query.eq('linha_id', linhaId);
      }
      final data = await query
          .order('codigo_torre')
          .range(offset, offset + batchSize - 1);
      allData.addAll(List<Map<String, dynamic>>.from(data));
      if (data.length < batchSize) break; // last page
      offset += batchSize;
      if (limit != null && allData.length >= limit) break;
    }
    final result = allData.map<Torre>((json) => Torre.fromJson(json)).toList();
    if (limit != null) return result.take(limit).toList();
    return result;
  }

  static Future<Torre?> getTorreById(String id) async {
    final data = await _client
        .from('torres')
        .select('*, linhas(nome)')
        .eq('id', id)
        .maybeSingle();
    return data != null ? Torre.fromJson(data) : null;
  }

  static Future<List<Torre>> getTorresByLinha(String linhaId) async {
    final data = await _client
        .from('torres')
        .select('*, linhas(nome)')
        .eq('linha_id', linhaId)
        .order('codigo_torre');
    return data.map<Torre>((json) => Torre.fromJson(json)).toList();
  }

  /// Import lines and towers from parsed KML data.
  /// Returns a map with 'linhas_created', 'torres_created', 'torres_updated' counts.
  static Future<Map<String, int>> importFromKml({
    required List<Map<String, dynamic>> parsedLines,
    required List<Map<String, dynamic>> parsedTowers,
  }) async {
    int linhasCreated = 0;
    int torresCreated = 0;
    int torresUpdated = 0;

    // 1. Get or create linhas
    final linhaCache = <String, String>{}; // code -> id
    final existingLinhas = await getLinhas();
    for (final l in existingLinhas) {
      linhaCache[l.nome] = l.id;
    }

    for (final lineData in parsedLines) {
      final name = lineData['name'] as String;
      if (!linhaCache.containsKey(name)) {
        final data = await _client.from('linhas').insert({
          'nome': name,
          'descricao': lineData['description'],
          'codigo': lineData['code'] ?? name,
        }).select().single();
        linhaCache[name] = data['id'];
        linhasCreated++;
      }
    }

    // 2. Determine the linha for each tower based on name prefix
    // Tower names usually follow pattern: "LINHA_CODE TOWER_NUMBER"
    // Try to match tower to the closest line name
    String? findLinhaId(String towerName) {
      // Try exact match on prefix
      for (final entry in linhaCache.entries) {
        if (towerName.startsWith(entry.key)) return entry.value;
      }
      // Try matching on first significant part
      final parts = towerName.split(RegExp(r'[\s\-_]'));
      if (parts.isNotEmpty) {
        for (final entry in linhaCache.entries) {
          if (entry.key.contains(parts[0])) return entry.value;
        }
      }
      return linhaCache.values.firstOrNull;
    }

    // 3. Upsert towers in batches
    for (int i = 0; i < parsedTowers.length; i += 50) {
      final batch = parsedTowers.skip(i).take(50).toList();
      for (final towerData in batch) {
        final name = towerData['name'] as String;
        final linhaId = findLinhaId(name);
        final torreJson = {
          'codigo_torre': name,
          'descricao': towerData['description'] ?? 'Torre $name',
          'latitude': towerData['latitude'],
          'longitude': towerData['longitude'],
          'altitude': towerData['altitude'],
          'tipo': towerData['tipo'] ?? 'Suspensão',
          'criticidade_atual': 'baixa',
          if (linhaId != null) 'linha_id': linhaId,
        };

        try {
          // Try to find existing torre by codigo_torre + linha_id
          final existing = await _client
              .from('torres')
              .select('id')
              .eq('codigo_torre', name)
              .limit(1)
              .maybeSingle();

          if (existing != null) {
            // Update existing
            await _client.from('torres').update({
              'latitude': towerData['latitude'],
              'longitude': towerData['longitude'],
              'altitude': towerData['altitude'],
              if (linhaId != null) 'linha_id': linhaId,
            }).eq('id', existing['id']);
            torresUpdated++;
          } else {
            // Insert new
            await _client.from('torres').insert(torreJson);
            torresCreated++;
          }
        } catch (e) {
          // Skip duplicates or errors, continue with next
          continue;
        }
      }
    }

    return {
      'linhas_created': linhasCreated,
      'torres_created': torresCreated,
      'torres_updated': torresUpdated,
    };
  }

  // ═══════════════════════════════════════════════════════
  // CAMPANHAS
  // ═══════════════════════════════════════════════════════

  static Future<List<Campanha>> getCampanhas() async {
    final data = await _client
        .from('campanhas')
        .select()
        .order('criado_em', ascending: false);
    return data.map<Campanha>((json) => Campanha.fromJson(json)).toList();
  }

  static Future<Campanha> createCampanha({
    required String nome,
    String? descricao,
    DateTime? dataInicio,
    DateTime? dataFim,
  }) async {
    final data = await _client.from('campanhas').insert({
      'nome': nome,
      'descricao': descricao,
      'data_inicio': dataInicio?.toIso8601String().split('T')[0],
      'data_fim': dataFim?.toIso8601String().split('T')[0],
      'status': 'em_andamento',
    }).select().single();
    return Campanha.fromJson(data);
  }

  // ═══════════════════════════════════════════════════════
  // FOTOS
  // ═══════════════════════════════════════════════════════

  static Future<List<String>> getLinhasIdsPorCampanha(String campanhaId) async {
    final Set<String> setIds = {};
    const batchSize = 1000;
    int offset = 0;

    while (true) {
      final data = await _client
          .from('fotos')
          .select('linha_id')
          .eq('campanha_id', campanhaId)
          .range(offset, offset + batchSize - 1);
      
      for (final e in data) {
        if (e['linha_id'] != null) {
          setIds.add(e['linha_id'] as String);
        }
      }

      if (data.length < batchSize) break;
      offset += batchSize;
    }

    return setIds.toList();
  }

  static Future<List<Foto>> getFotos({
    String? torreId,
    String? linhaId,
    String? campanhaId,
    int? limit,
  }) async {
    final allData = <Map<String, dynamic>>[];
    const batchSize = 1000;
    int offset = 0;

    while (true) {
      var query = _client
          .from('fotos')
          .select('*, torres(codigo_torre), linhas(nome), campanhas(nome)');
      
      if (torreId != null) query = query.eq('torre_id', torreId);
      if (linhaId != null) query = query.eq('linha_id', linhaId);
      if (campanhaId != null) query = query.eq('campanha_id', campanhaId);

      final data = await query
          .order('criado_em', ascending: false)
          .range(offset, offset + batchSize - 1);
          
      allData.addAll(List<Map<String, dynamic>>.from(data));
      
      if (data.length < batchSize) break;
      offset += batchSize;
      
      if (limit != null && allData.length >= limit) break;
    }

    final result = allData.map<Foto>((json) => Foto.fromJson(json)).toList();
    if (limit != null) return result.take(limit).toList();
    return result;
  }

  /// Lightweight query for map markers — no JOINs, only GPS fields.
  static Future<List<Foto>> getFotosForMap() async {
    final allData = <Map<String, dynamic>>[];
    const batchSize = 1000;
    int offset = 0;

    while (true) {
      final data = await _client
          .from('fotos')
          .select('id, latitude, longitude, status_associacao, caminho_storage, arquivo_editado_url, torre_id')
          .not('latitude', 'is', null)
          .not('longitude', 'is', null)
          .order('criado_em', ascending: false)
          .range(offset, offset + batchSize - 1);
          
      allData.addAll(List<Map<String, dynamic>>.from(data));
      
      if (data.length < batchSize) break;
      offset += batchSize;
    }

    return allData.map<Foto>((json) => Foto.fromJson(json)).toList();
  }

  static Future<String?> getEditedPhotoStateHistory(String editedStoragePath) async {
    try {
      final jsonPath = '$editedStoragePath.json';
      final bytes = await _client.storage.from('fotos-producao').download(jsonPath);
      return utf8.decode(bytes);
    } catch (_) {
      // It's normal for history to be missing if they saved without the new logic, or if no edits were made
      return null;
    }
  }

  static Future<void> saveEditedPhoto(String fotoId, String originalStoragePath, Uint8List editedBytes, {String? stateJson}) async {
    // Determine new filename
    final originalName = originalStoragePath.split('/').last; 
    final nameParts = originalName.split('.');
    final ext = nameParts.length > 1 ? nameParts.last : 'jpg';
    final nameWithoutExt = nameParts.length > 1 ? nameParts.sublist(0, nameParts.length - 1).join('.') : originalName;
    
    final pathParts = originalStoragePath.split('/');
    pathParts.removeLast();
    final folderPath = pathParts.join('/');
    
    final newFileName = '${nameWithoutExt}_edited_${DateTime.now().millisecondsSinceEpoch}.$ext';
    final newStoragePath = folderPath.isEmpty ? newFileName : '$folderPath/$newFileName';
    
    // Upload to photos bucket
    await _client.storage.from('fotos-producao').uploadBinary(newStoragePath, editedBytes);
    
    // Upload JSON metadata state history if present
    if (stateJson != null && stateJson.isNotEmpty) {
      final jsonPath = '$newStoragePath.json';
      await _client.storage.from('fotos-producao').uploadBinary(
        jsonPath, 
        utf8.encode(stateJson),
      );
    }
    
    // Update DB
    await _client.from('fotos').update({'arquivo_editado_url': newStoragePath}).eq('id', fotoId);
  }

  static Future<Foto?> getFotoById(String id) async {
    final data = await _client
        .from('fotos')
        .select('*, torres(codigo_torre), linhas(nome), campanhas(nome)')
        .eq('id', id)
        .maybeSingle();
    return data != null ? Foto.fromJson(data) : null;
  }

  static Future<List<Foto>> getFotosByTorre(String torreId) async {
    return getFotos(torreId: torreId);
  }

  /// Update the tower association of a photo.
  static Future<void> updateFotoAssociation({
    required String fotoId,
    required String torreId,
    String? linhaId,
    String? torreCodigo,
    String? linhaNome,
    double? distanciaM,
  }) async {
    final update = <String, dynamic>{
      'torre_id': torreId,
      'status_associacao': 'manual',
    };
    if (linhaId != null) update['linha_id'] = linhaId;
    if (distanciaM != null) update['distancia_torre_m'] = distanciaM;
    await _client.from('fotos').update(update).eq('id', fotoId);
  }

  /// Insert a photo record into the database.
  static Future<Foto> insertFoto(Foto foto) async {
    final data = await _client
        .from('fotos')
        .insert(foto.toJson())
        .select('*, torres(codigo_torre), linhas(nome), campanhas(nome)')
        .single();
    return Foto.fromJson(data);
  }

  /// Get filenames of photos existing in a specific campaign and line
  static Future<List<String>> getFotoFileNames(String campanhaId, String linhaId) async {
    final data = await _client
        .from('fotos')
        .select('nome_arquivo')
        .eq('campanha_id', campanhaId)
        .eq('linha_id', linhaId);
    return (data as List).map((row) => row['nome_arquivo'] as String).toList();
  }

  /// Delete photos by exact filenames matching campaign and line
  static Future<void> deleteFotosByNames(String campanhaId, String linhaId, List<String> fileNames) async {
    if (fileNames.isEmpty) return;
    
    // Supabase URL length limits typically restrict IN clauses. We batch if large.
    for (int i = 0; i < fileNames.length; i += 50) {
      final batch = fileNames.skip(i).take(50).toList();
      await _client
          .from('fotos')
          .delete()
          .eq('campanha_id', campanhaId)
          .eq('linha_id', linhaId)
          .inFilter('nome_arquivo', batch);
    }
  }

  /// Bulk insert photos and update tower photo counts.
  static Future<List<Foto>> insertFotos(List<Foto> fotos) async {
    if (fotos.isEmpty) return [];

    final data = await _client
        .from('fotos')
        .insert(fotos.map((f) => f.toJson()).toList())
        .select('*, torres(codigo_torre), linhas(nome), campanhas(nome)');

    // Update tower photo counts
    final torreIds = fotos
        .where((f) => f.torreId != null)
        .map((f) => f.torreId!)
        .toSet();
    for (final torreId in torreIds) {
      final count = fotos.where((f) => f.torreId == torreId).length;
      await _client.rpc('increment_torre_fotos', params: {
        'p_torre_id': torreId,
        'p_count': count,
      }).catchError((_) {
        // Fallback: increment manually if RPC doesn't exist
        return null;
      });
    }

    return data.map<Foto>((json) => Foto.fromJson(json)).toList();
  }

  // ═══════════════════════════════════════════════════════
  // ANOMALIAS
  // ═══════════════════════════════════════════════════════

  static Future<List<Anomalia>> getAnomalias({String? torreId}) async {
    var query = _client
        .from('anomalias')
        .select('*, torres(codigo_torre), fotos(nome_arquivo)');
    if (torreId != null) query = query.eq('torre_id', torreId);
    final data = await query.order('criado_em', ascending: false);
    return data.map<Anomalia>((json) => Anomalia.fromJson(json)).toList();
  }

  static Future<Anomalia> createAnomalia(Anomalia anomalia) async {
    final data = await _client
        .from('anomalias')
        .insert(anomalia.toJson())
        .select()
        .single();
    return Anomalia.fromJson(data);
  }

  // ═══════════════════════════════════════════════════════
  // STORAGE - Upload fotos
  // ═══════════════════════════════════════════════════════

  static const String _bucket = 'fotos-producao';

  /// Upload photo bytes to Supabase Storage.
  /// Returns the storage path.
  static Future<String> uploadFoto({
    required String fileName,
    required Uint8List bytes,
    String? linhaCode,
    String? campanhaNome,
  }) async {
    final folder = linhaCode ?? 'sem_linha';
    final path = campanhaNome != null 
        ? '${campanhaNome.replaceAll('/', '-')}/$folder/$fileName' 
        : '$folder/$fileName';

    await _client.storage.from(_bucket).uploadBinary(
      path,
      bytes,
      fileOptions: const FileOptions(upsert: true),
    );

    return path;
  }

  /// Get a public URL for a photo in storage.
  static String getPhotoUrl(String storagePath) {
    return _client.storage.from(_bucket).getPublicUrl(storagePath);
  }

  // ═══════════════════════════════════════════════════════
  // DASHBOARD STATS
  // ═══════════════════════════════════════════════════════

  static Future<Map<String, dynamic>> getDashboardStats() async {
    final linhasCount = await _client.from('linhas').select('id').count();
    final torresCount = await _client.from('torres').select('id').count();
    final fotosCount = await _client.from('fotos').select('id').count();
    final fotosPendentes = await _client.from('fotos').select('id')
        .or('status_associacao.eq.pendente,status_associacao.eq.sem_gps').count();
    final fotosNaoAvaliadas = await _client.from('fotos').select('id')
        .eq('status_avaliacao', 'nao_avaliada').count();
    final torresCriticas = await _client.from('torres').select('id')
        .or('criticidade_atual.eq.alta,criticidade_atual.eq.critica').count();
    final anomaliasAbertas = await _client.from('anomalias').select('id')
        .neq('status', 'resolvida').count();
    final campanhasAtivas = await _client.from('campanhas').select('id')
        .eq('status', 'em_andamento').count();

    return {
      'total_linhas': linhasCount.count,
      'total_torres': torresCount.count,
      'total_fotos': fotosCount.count,
      'fotos_sem_associacao': fotosPendentes.count,
      'fotos_sem_avaliacao': fotosNaoAvaliadas.count,
      'torres_criticas': torresCriticas.count,
      'anomalias_abertas': anomaliasAbertas.count,
      'campanhas_ativas': campanhasAtivas.count,
    };
  }

  // ═══════════════════════════════════════════════════════
  // CHART DATA
  // ═══════════════════════════════════════════════════════

  static Future<Map<String, int>> getCriticidadeDistribuicao() async {
    final result = <String, int>{'baixa': 0, 'media': 0, 'alta': 0, 'critica': 0};
    for (final key in result.keys.toList()) {
      final r = await _client.from('torres').select('id').eq('criticidade_atual', key).count();
      result[key] = r.count;
    }
    return result;
  }

  static Future<Map<String, int>> getAnomaliasPorTipo() async {
    final data = await _client.from('anomalias').select('tipo');
    final map = <String, int>{};
    for (final row in data) {
      final tipo = row['tipo'] as String;
      map[tipo] = (map[tipo] ?? 0) + 1;
    }
    return map;
  }

  static Future<Map<String, int>> getFotosPorCampanha() async {
    final campanhas = await getCampanhas();
    final map = <String, int>{};
    for (final c in campanhas) {
      final r = await _client.from('fotos').select('id').eq('campanha_id', c.id).count();
      map[c.nome] = r.count;
    }
    return map;
  }

  // ═══════════════════════════════════════════════════════
  // MANUTENÇÃO / REASOCIAÇÃO
  // ═══════════════════════════════════════════════════════

  /// Re-associate ALL photos with GPS to the nearest tower.
  /// Returns {associated, skipped, errors}.
  static Future<Map<String, int>> reAssociateAllPhotos({
    void Function(int current, int total)? onProgress,
  }) async {
    // 1. Get all towers with pagination
    final allTowers = await getTorres();
    if (allTowers.isEmpty) return {'associated': 0, 'skipped': 0, 'errors': 0};

    final towerCoords = allTowers
        .map((t) => {'lat': t.latitude, 'lng': t.longitude})
        .toList();

    // 2. Get all photos with GPS (paginated)
    final allPhotos = <Map<String, dynamic>>[];
    const batchSize = 1000;
    int offset = 0;
    while (true) {
      final data = await _client
          .from('fotos')
          .select('id, latitude, longitude, status_associacao')
          .not('latitude', 'is', null)
          .not('longitude', 'is', null)
          .range(offset, offset + batchSize - 1);
      allPhotos.addAll(List<Map<String, dynamic>>.from(data));
      if (data.length < batchSize) break;
      offset += batchSize;
    }

    int associated = 0;
    int skipped = 0;
    int errors = 0;

    // 3. For each photo, find nearest tower and update
    for (int i = 0; i < allPhotos.length; i++) {
      final photo = allPhotos[i];
      if (onProgress != null) onProgress(i + 1, allPhotos.length);

      try {
        final lat = (photo['latitude'] as num).toDouble();
        final lng = (photo['longitude'] as num).toDouble();

        final nearest = DistanceCalculator.findNearestTower(lat, lng, towerCoords);
        if (nearest == null) {
          skipped++;
          continue;
        }

        final tower = allTowers[nearest.key];
        final distance = nearest.value;

        String status;
        if (distance < 500) {
          status = 'associada';
        } else {
          status = 'pendente'; // too far to auto-associate
        }

        await _client.from('fotos').update({
          'torre_id': distance < 500 ? tower.id : null,
          'linha_id': distance < 500 ? tower.linhaId : null,
          'distancia_torre_m': distance,
          'status_associacao': status,
        }).eq('id', photo['id']);

        associated++;
      } catch (e) {
        errors++;
      }
    }

    return {'associated': associated, 'skipped': skipped, 'errors': errors, 'total': allPhotos.length};
  }

  /// Remove duplicate photos (same nome_arquivo + campanha_id).
  /// Keeps the most recent one, deletes older duplicates.
  /// Returns number of duplicates removed.
  static Future<int> removeDuplicatePhotos() async {
    // Use raw SQL via RPC for efficiency, or do it client-side
    // Get all photos grouped by nome_arquivo + campanha_id
    final allPhotos = <Map<String, dynamic>>[];
    const batchSize = 1000;
    int offset = 0;
    while (true) {
      final data = await _client
          .from('fotos')
          .select('id, nome_arquivo, campanha_id, caminho_storage, criado_em')
          .order('criado_em', ascending: false)
          .range(offset, offset + batchSize - 1);
      allPhotos.addAll(List<Map<String, dynamic>>.from(data));
      if (data.length < batchSize) break;
      offset += batchSize;
    }

    // Find duplicates: same nome_arquivo + campanha_id
    final seen = <String, String>{}; // key -> id of first (most recent, kept)
    final duplicateIds = <String>[];

    for (final photo in allPhotos) {
      final key = '${photo['nome_arquivo']}||${photo['campanha_id'] ?? 'null'}';
      if (seen.containsKey(key)) {
        duplicateIds.add(photo['id']);
      } else {
        seen[key] = photo['id'];
      }
    }

    // Delete duplicates in batches
    for (int i = 0; i < duplicateIds.length; i += 50) {
      final batch = duplicateIds.sublist(i, i + 50 > duplicateIds.length ? duplicateIds.length : i + 50);
      await _client.from('fotos').delete().inFilter('id', batch);
    }

    return duplicateIds.length;
  }

  /// Remove all photos from the database.
  /// This deletes all records from the 'fotos' table.
  static Future<void> removeAllPhotos() async {
    // We use a dummy condition to bypass Supabase's mandatory query filter constraint for deletes.
    // 'id' is a UUID, so we can just say neq on a placeholder or use an 'is.not.null' filter.
    await _client.from('fotos').delete().neq('id', '00000000-0000-0000-0000-000000000000');
  }

  // ═══════════════════════════════════════════════════════
  // SUPRESSÃO DE VEGETAÇÃO
  // ═══════════════════════════════════════════════════════
  
  static Future<List<Map<String, dynamic>>> getSupressaoByLinha(String linhaId) async {
    final data = await _client
        .from('mapeamento_supressao')
        .select('*, torres(codigo_torre), linhas(nome)')
        .eq('linha_id', linhaId)
        .order('est_codigo');
    return List<Map<String, dynamic>>.from(data);
  }

  static Future<List<Map<String, dynamic>>> getSupressaoByTorre(String torreId) async {
    final data = await _client
        .from('mapeamento_supressao')
        .select('*, torres(codigo_torre), linhas(nome)')
        .eq('torre_id', torreId)
        .order('est_codigo');
    return List<Map<String, dynamic>>.from(data);
  }

  static Future<List<Map<String, dynamic>>> getSupressaoResumo() async {
    final data = await _client
        .from('vw_supressao_resumo')
        .select()
        .order('linha_nome');
    return List<Map<String, dynamic>>.from(data);
  }

  /// Delete a single suppression mapping record.
  static Future<void> deleteSupressao(String id) async {
    await _client.from('mapeamento_supressao').delete().eq('id', id);
  }

  /// Delete all suppression mapping records for a given line.
  static Future<int> deleteSupressaoByLinha(String linhaId) async {
    final records = await _client
        .from('mapeamento_supressao')
        .select('id')
        .eq('linha_id', linhaId);
    if (records.isEmpty) return 0;
    final ids = records.map<String>((r) => r['id'] as String).toList();
    for (int i = 0; i < ids.length; i += 50) {
      final batch = ids.sublist(i, i + 50 > ids.length ? ids.length : i + 50);
      await _client.from('mapeamento_supressao').delete().inFilter('id', batch);
    }
    return ids.length;
  }

  // ═══════════════════════════════════════════════════════
  // CHAT
  // ═══════════════════════════════════════════════════════

  static Stream<List<ChatMensagem>> streamChatPorTorre(String torreId) {
    return _client
        .from('chat_mensagens')
        .stream(primaryKey: ['id'])
        .eq('torre_id', torreId)
        .order('created_at', ascending: true)
        .asyncMap((event) async {
          // As Stream does not natively join referenced tables effectively without complex setup, 
          // we do a secondary query to fetch user details to embed them.
          if (event.isEmpty) return [];
          final userIds = event.map((e) => e['usuario_id']).toSet().toList();
          final usersData = await _client.from('app_usuarios').select().filter('id', 'in', userIds);
          final Map<int, dynamic> usersMap = {for (var u in usersData) u['id'] as int: u};

          return event.map((msg) {
            final chat = ChatMensagem.fromJson(msg);
            if (usersMap.containsKey(chat.usuarioId)) {
              chat.usuario = AppUsuario.fromJson(usersMap[chat.usuarioId]);
            }
            return chat;
          }).toList();
        });
  }

  static Future<void> enviarMensagemChat({
    required String torreId,
    required int usuarioId,
    required String texto,
    String? tipoAnexo,
    String? urlAnexo,
    double? geoLat,
    double? geoLon,
    Map<String, dynamic>? metadata,
  }) async {
    await _client.from('chat_mensagens').insert({
      'torre_id': torreId,
      'usuario_id': usuarioId,
      'mensagem': texto,
      if (tipoAnexo != null) 'tipo_anexo': tipoAnexo,
      if (urlAnexo != null) 'url_anexo': urlAnexo,
      if (geoLat != null) 'geo_lat': geoLat,
      if (geoLon != null) 'geo_lon': geoLon,
      if (metadata != null) 'metadata': metadata,
    });
  }

  static Future<void> deleteMensagemChat(int id) async {
    final response = await _client.from('chat_mensagens').delete().eq('id', id).select();
    if (response.isEmpty) {
      throw Exception('Nenhuma mensagem foi deletada. Verifique se existe uma política (RLS) no Supabase permitindo a operação de DELETE na tabela chat_mensagens para este usuário.');
    }
  }

  static Future<String> uploadAnexoChat({
    required String torreId,
    required String fileName,
    required Uint8List fileBytes,
    required String mimeType,
  }) async {
    final path = 'torre_$torreId/${DateTime.now().millisecondsSinceEpoch}_$fileName';
    await _client.storage.from('chat_anexos').uploadBinary(
          path,
          fileBytes,
          fileOptions: FileOptions(contentType: mimeType),
        );
    return _client.storage.from('chat_anexos').getPublicUrl(path);
  }

  static Future<Map<String, dynamic>> getSupressaoStats() async {
    try {
      final total = await _client.from('mapeamento_supressao').select('id').count();
      final concluidos = await _client.from('mapeamento_supressao').select('id').eq('roco_concluido', true).count();
      final p1 = await _client.from('mapeamento_supressao').select('id').eq('prioridade', 'P1').count();
      final p2 = await _client.from('mapeamento_supressao').select('id').eq('prioridade', 'P2').count();
      return {
        'total_vaos': total.count,
        'concluidos': concluidos.count,
        'prioridade_1': p1.count,
        'prioridade_2': p2.count,
      };
    } catch (_) {
      return {'total_vaos': 0, 'concluidos': 0, 'prioridade_1': 0, 'prioridade_2': 0};
    }
  }

  // ═══════════════════════════════════════════════════════
  // SUPRESSÃO - LAYOUT VISUAL
  // ═══════════════════════════════════════════════════════

  static Future<List<dynamic>?> getSupressaoLayoutVisual(String mapeamentoId) async {
    final data = await _client
        .from('supressao_layout_visual')
        .select('segmentos')
        .eq('mapeamento_id', mapeamentoId)
        .maybeSingle();
    
    if (data == null) return null;
    return data['segmentos'] as List<dynamic>?;
  }

  static Future<void> saveSupressaoLayoutVisual(String mapeamentoId, List<dynamic> segmentos) async {
    await _client.from('supressao_layout_visual').upsert({
      'mapeamento_id': mapeamentoId,
      'segmentos': segmentos,
      'atualizado_em': DateTime.now().toIso8601String(),
    });
  }
}
