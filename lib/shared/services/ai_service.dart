import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/ai_models.dart';

/// Service for AI analysis operations.
class AiService {
  static const String _aiBaseUrl = 'http://127.0.0.1:8000';
  static SupabaseClient get _client => Supabase.instance.client;

  // â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
  // AI ANALYSIS (from Supabase DB)
  // â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•

  /// Get AI analysis for a specific photo.
  static Future<AiAnalysis?> getAnalysis(String fotoId) async {
    final data = await _client
        .from('ai_analysis')
        .select()
        .eq('foto_id', fotoId)
        .maybeSingle();
    return data != null ? AiAnalysis.fromJson(data) : null;
  }

  /// Get all AI analyses for a tower's photos.
  static Future<List<AiAnalysis>> getAnalysesByTorre(String torreId) async {
    final data = await _client
        .from('ai_analysis')
        .select('*, fotos!inner(torre_id)')
        .eq('fotos.torre_id', torreId)
        .order('severity_score', ascending: false);
    return data.map<AiAnalysis>((json) => AiAnalysis.fromJson(json)).toList();
  }

  // â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
  // TOWER RISK
  // â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•

  /// Get risk score for a tower.
  static Future<TowerRisk?> getTowerRisk(String torreId) async {
    final data = await _client
        .from('tower_risk')
        .select()
        .eq('torre_id', torreId)
        .maybeSingle();
    return data != null ? TowerRisk.fromJson(data) : null;
  }

  /// Get top critical towers (for dashboard).
  static Future<List<Map<String, dynamic>>> getTopCriticalTowers({int limit = 10}) async {
    final data = await _client
        .from('tower_risk')
        .select('*, torres(codigo_torre, linhas(nome))')
        .order('risk_score', ascending: false)
        .limit(limit);
    return List<Map<String, dynamic>>.from(data);
  }

  // â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
  // AI REPORTS
  // â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•

  /// Get AI report for a photo.
  static Future<AiReport?> getReport(String fotoId) async {
    final data = await _client
        .from('ai_reports')
        .select()
        .eq('foto_id', fotoId)
        .order('generated_at', ascending: false)
        .limit(1)
        .maybeSingle();
    return data != null ? AiReport.fromJson(data) : null;
  }

  // â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
  // AI SERVICE CALLS (to Python microservice)
  // â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•

  /// Trigger AI analysis for a single photo.
  static Future<AiAnalysis?> analyzeImage(String fotoId, String imageUrl) async {
    try {
      final response = await http.post(
        Uri.parse('$_aiBaseUrl/analyze-image'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'image_url': imageUrl, 'photo_id': fotoId}),
      );
      if (response.statusCode == 200) {
        // After AI processes, fetch from DB (it auto-saves)
        await Future.delayed(const Duration(milliseconds: 500));
        return await getAnalysis(fotoId);
      }
      debugPrint('AI analysis failed: ${response.statusCode} ${response.body}');
      return null;
    } catch (e) {
      debugPrint('AI service error: $e');
      return null;
    }
  }

  /// Generate LLM summary for a photo.
  static Future<AiReport?> generateSummary(String fotoId, {String? imageUrl, Map<String, dynamic>? analysisData}) async {
    try {
      final response = await http.post(
        Uri.parse('$_aiBaseUrl/generate-summary'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'photo_id': fotoId,
          if (imageUrl != null) 'image_url': imageUrl,
          if (analysisData != null) 'analysis_data': analysisData,
        }),
      );
      if (response.statusCode == 200) {
        await Future.delayed(const Duration(milliseconds: 500));
        return await getReport(fotoId);
      }
      return null;
    } catch (e) {
      debugPrint('AI summary error: $e');
      return null;
    }
  }

  /// Trigger batch analysis for multiple photos.
  static Future<Map<String, dynamic>?> batchAnalyze(List<String> photoIds) async {
    try {
      final response = await http.post(
        Uri.parse('$_aiBaseUrl/batch-analyze'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(photoIds),
      );
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
      return null;
    } catch (e) {
      debugPrint('Batch analysis error: $e');
      return null;
    }
  }

  /// Annotate image with tower name and type using AI detection.
  /// Returns a map with 'imageBytes' (Uint8List), 'towerCode', 'towerType', and 'detection' (Map).
  static Future<Map<String, dynamic>?> annotateImage(String fotoId, String imageUrl) async {
    try {
      final response = await http.post(
        Uri.parse('$_aiBaseUrl/annotate-image'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'image_url': imageUrl, 'photo_id': fotoId}),
      ).timeout(const Duration(seconds: 120));
      if (response.statusCode == 200) {
        Map<String, dynamic>? detection;
        try {
          final detectionHeader = response.headers['x-ai-detection'];
          if (detectionHeader != null) {
            detection = jsonDecode(detectionHeader) as Map<String, dynamic>;
          }
        } catch (_) {}
        return {
          'imageBytes': response.bodyBytes,
          'towerCode': response.headers['x-tower-code'] ?? 'unknown',
          'towerFunction': response.headers['x-tower-function'] ?? 'desconhecido',
          'towerStructure': response.headers['x-tower-structure'] ?? 'desconhecido',
          'towerHeight': response.headers['x-tower-height'] ?? '0',
          'detection': detection,
        };
      }
      debugPrint('Annotate image failed: ${response.statusCode}');
      return null;
    } catch (e) {
      debugPrint('Annotate image error: $e');
      return null;
    }
  }

  /// Annotate image with Moondream 3 - detects vegetation corridor and overlays segment distances.
  /// [segments] should be a list of maps with keys: tipo, inicio, fim (in meters).
  /// [largura_m] is the right-of-way strip width from the DB (used to size the corridor band).
  /// Returns JPEG image bytes with colored boxes drawn on the photo.
  static Future<Uint8List?> annotateMoondream({
    required String imageUrl,
    required List<Map<String, dynamic>> segments,
    required double vaoTotalM,
    double larguraM = 40.0,
    String? fotoId,
    String? torreCodigo,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$_aiBaseUrl/annotate-moondream'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'image_url': imageUrl,
          'photo_id': fotoId,
          'torre_codigo': torreCodigo,
          'vao_total_m': vaoTotalM,
          'largura_m': larguraM,
          'segments': segments,
        }),
      ).timeout(const Duration(seconds: 90));
      if (response.statusCode == 200) {
        return response.bodyBytes;
      }
      debugPrint('annotateMoondream failed: \${response.statusCode}');
      return null;
    } catch (e) {
      debugPrint('annotateMoondream error: \$e');
      return null;
    }
  }

  /// Check if AI service is running.
  static Future<bool> isServiceHealthy() async {
    try {
      final response = await http.get(Uri.parse('$_aiBaseUrl/health')).timeout(const Duration(seconds: 3));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  // â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
  // DASHBOARD STATS
  // â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•

  /// Get AI-related stats for the dashboard.
  static Future<Map<String, dynamic>> getAiStats() async {
    try {
      final analysisCount = await _client.from('ai_analysis').select('id').count();
      final vegCount = await _client.from('ai_analysis').select('id').eq('vegetation_detected', true).count();
      final fireCount = await _client.from('ai_analysis').select('id').eq('fire_signs', true).count();
      final structCount = await _client.from('ai_analysis').select('id').eq('structural_issue', true).count();
      final criticalTowers = await _client.from('tower_risk').select('id').eq('priority_level', 'CRITICAL').count();

      return {
        'total_analyzed': analysisCount.count,
        'vegetation_alerts': vegCount.count,
        'fire_alerts': fireCount.count,
        'structural_alerts': structCount.count,
        'critical_towers': criticalTowers.count,
      };
    } catch (e) {
      return {'total_analyzed': 0, 'vegetation_alerts': 0, 'fire_alerts': 0, 'structural_alerts': 0, 'critical_towers': 0};
    }
  }

  // -------------------------------------------------------
  // SUPRESSÃO AUTOMÁTICA
  // -------------------------------------------------------

  static Future<List<Map<String, dynamic>>?> parseRocoText(String texto, int vaoM) async {
    try {
      final response = await http.post(
        Uri.parse('$_aiBaseUrl/parse-roco-text'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'texto': texto,
          'vao_m': vaoM,
        }),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data != null && data['segmentos'] != null) {
          return List<Map<String, dynamic>>.from(data['segmentos']);
        }
      }
      return null;
    } catch (e) {
      debugPrint('AI parse-roco error: $e');
      return null;
    }
  }
}

