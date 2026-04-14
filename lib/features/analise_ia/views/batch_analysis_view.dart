import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/services/supabase_service.dart';
import '../../../shared/services/ai_service.dart';
import '../../../shared/models/campanha.dart';
import '../../fotos/models/foto.dart';

class BatchAnalysisView extends StatefulWidget {
  const BatchAnalysisView({super.key});

  @override
  State<BatchAnalysisView> createState() => _BatchAnalysisViewState();
}

class _BatchAnalysisViewState extends State<BatchAnalysisView> {
  // Data
  List<Campanha> _campanhas = [];
  bool _isLoading = true;
  bool _isServiceOnline = false;

  // Selection
  String? _selectedCampanhaId;
  bool _analyzeAll = false;

  // Analysis state
  bool _isAnalyzing = false;
  int _totalPhotos = 0;
  int _processed = 0;
  int _success = 0;
  int _errors = 0;
  int _alreadyAnalyzed = 0;
  bool _skipAlreadyAnalyzed = true;
  String _currentPhotoName = '';
  List<_AnalysisResult> _results = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final results = await Future.wait([
      SupabaseService.getCampanhas(),
      AiService.isServiceHealthy(),
    ]);
    setState(() {
      _campanhas = results[0] as List<Campanha>;
      _isServiceOnline = results[1] as bool;
      _isLoading = false;
    });
  }

  Future<void> _startAnalysis() async {
    if (!_isServiceOnline) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('❌ Serviço de IA offline! Inicie o servidor Python.'), backgroundColor: AppColors.error),
      );
      return;
    }

    setState(() {
      _isAnalyzing = true;
      _processed = 0;
      _success = 0;
      _errors = 0;
      _alreadyAnalyzed = 0;
      _results = [];
    });

    // Get all photos for the selected scope
    List<Foto> photos;
    if (_analyzeAll) {
      photos = await SupabaseService.getFotos(limit: 10000);
    } else {
      photos = await SupabaseService.getFotos(campanhaId: _selectedCampanhaId);
    }

    setState(() => _totalPhotos = photos.length);

    if (photos.isEmpty) {
      setState(() => _isAnalyzing = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Nenhuma foto encontrada.'), backgroundColor: AppColors.info),
        );
      }
      return;
    }

    // Process each photo
    for (int i = 0; i < photos.length; i++) {
      if (!_isAnalyzing) break; // Allow cancel

      final foto = photos[i];
      setState(() {
        _processed = i + 1;
        _currentPhotoName = foto.nomeArquivo;
      });

      try {
        // Check if already analyzed
        if (_skipAlreadyAnalyzed) {
          final existing = await AiService.getAnalysis(foto.id);
          if (existing != null) {
            _results.add(_AnalysisResult(
              photoName: foto.nomeArquivo,
              photoId: foto.id,
              status: 'skipped',
              message: 'Já analisada',
            ));
            setState(() => _alreadyAnalyzed++);
            continue;
          }
        }

        // Get the photo URL
        final imageUrl = SupabaseService.getPhotoUrl(foto.caminhoStorage);

        // Call AI analysis
        final analysis = await AiService.analyzeImage(foto.id, imageUrl);

        if (analysis != null) {
          _results.add(_AnalysisResult(
            photoName: foto.nomeArquivo,
            photoId: foto.id,
            status: 'success',
            severity: analysis.severityScore,
            message: analysis.summary ?? 'OK',
          ));
          setState(() => _success++);
        } else {
          _results.add(_AnalysisResult(
            photoName: foto.nomeArquivo,
            photoId: foto.id,
            status: 'error',
            message: 'Falha na análise',
          ));
          setState(() => _errors++);
        }
      } catch (e) {
        _results.add(_AnalysisResult(
          photoName: foto.nomeArquivo,
          photoId: foto.id,
          status: 'error',
          message: e.toString(),
        ));
        setState(() => _errors++);
      }
    }

    setState(() => _isAnalyzing = false);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('✅ Análise concluída! $_success analisadas, $_errors erros, $_alreadyAnalyzed já existentes.'),
        backgroundColor: AppColors.success,
        duration: const Duration(seconds: 5),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width >= 900;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Análise IA em Lote'),
        leading: isWide ? null : Builder(
          builder: (ctx) => IconButton(
            icon: const Icon(Icons.menu_rounded),
            onPressed: () => Scaffold.of(ctx).openDrawer(),
          ),
        ),
        actions: [
          // Service status indicator
          Container(
            margin: const EdgeInsets.only(right: 16),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: _isServiceOnline
                  ? AppColors.success.withValues(alpha: 0.15)
                  : AppColors.error.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _isServiceOnline ? Icons.check_circle : Icons.error,
                  size: 14,
                  color: _isServiceOnline ? AppColors.success : AppColors.error,
                ),
                const SizedBox(width: 6),
                Text(
                  _isServiceOnline ? 'IA Online' : 'IA Offline',
                  style: TextStyle(
                    fontSize: 12,
                    color: _isServiceOnline ? AppColors.success : AppColors.error,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
            tooltip: 'Verificar status',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header
                  Text('Análise IA em Lote', style: Theme.of(context).textTheme.headlineMedium),
                  const SizedBox(height: 8),
                  Text(
                    'Analise automaticamente todas as fotos de uma campanha usando GPT-4o Vision + OpenCV.',
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 24),

                  // Configuration card
                  _buildConfigCard(),

                  const SizedBox(height: 24),

                  // Progress section
                  if (_isAnalyzing || _results.isNotEmpty) ...[
                    _buildProgressCard(),
                    const SizedBox(height: 24),
                  ],

                  // Results
                  if (_results.isNotEmpty) _buildResultsCard(),
                ],
              ),
            ),
    );
  }

  Widget _buildConfigCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Configuração', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 16),

          // Campaign selector
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: _analyzeAll ? null : _selectedCampanhaId,
                  decoration: const InputDecoration(
                    labelText: 'Campanha',
                    prefixIcon: Icon(Icons.campaign),
                  ),
                  items: [
                    ..._campanhas.map((c) => DropdownMenuItem(
                      value: c.id,
                      child: Text(c.nome),
                    )),
                  ],
                  onChanged: _isAnalyzing ? null : (v) {
                    setState(() {
                      _selectedCampanhaId = v;
                      _analyzeAll = false;
                    });
                  },
                ),
              ),
              const SizedBox(width: 16),
              Column(
                children: [
                  const Text('Todas', style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
                  Switch(
                    value: _analyzeAll,
                    onChanged: _isAnalyzing ? null : (v) => setState(() => _analyzeAll = v),
                    activeColor: AppColors.primary,
                  ),
                ],
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Options
          Row(
            children: [
              Checkbox(
                value: _skipAlreadyAnalyzed,
                onChanged: _isAnalyzing ? null : (v) => setState(() => _skipAlreadyAnalyzed = v ?? true),
                activeColor: AppColors.primary,
              ),
              const Text('Pular fotos já analisadas', style: TextStyle(fontSize: 13)),
            ],
          ),

          const SizedBox(height: 20),

          // Action buttons
          Row(
            children: [
              ElevatedButton.icon(
                icon: Icon(_isAnalyzing ? Icons.hourglass_top : Icons.auto_awesome),
                label: Text(_isAnalyzing ? 'Analisando...' : 'Iniciar Análise IA'),
                onPressed: (_isAnalyzing || (!_analyzeAll && _selectedCampanhaId == null))
                    ? null
                    : _startAnalysis,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                ),
              ),
              if (_isAnalyzing) ...[
                const SizedBox(width: 16),
                OutlinedButton.icon(
                  icon: const Icon(Icons.stop, color: AppColors.error),
                  label: const Text('Parar', style: TextStyle(color: AppColors.error)),
                  onPressed: () => setState(() => _isAnalyzing = false),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildProgressCard() {
    final progress = _totalPhotos > 0 ? _processed / _totalPhotos : 0.0;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _isAnalyzing ? AppColors.primary.withValues(alpha: 0.5) : AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (_isAnalyzing) ...[
                const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                const SizedBox(width: 12),
              ],
              Text(
                _isAnalyzing ? 'Analisando...' : 'Análise Concluída',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              Text('$_processed / $_totalPhotos', style: const TextStyle(fontSize: 14, color: AppColors.textMuted)),
            ],
          ),
          const SizedBox(height: 12),

          // Progress bar
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 8,
              backgroundColor: AppColors.bgElevated,
              valueColor: AlwaysStoppedAnimation(
                _errors > 0 ? AppColors.warning : AppColors.primary,
              ),
            ),
          ),
          const SizedBox(height: 8),

          if (_isAnalyzing)
            Text('📸 $_currentPhotoName', style: const TextStyle(fontSize: 11, color: AppColors.textMuted), maxLines: 1, overflow: TextOverflow.ellipsis),

          const SizedBox(height: 16),

          // Stats row
          Row(
            children: [
              _statChip('✅ Sucesso', _success, AppColors.success),
              const SizedBox(width: 12),
              _statChip('⏭️ Puladas', _alreadyAnalyzed, AppColors.info),
              const SizedBox(width: 12),
              _statChip('❌ Erros', _errors, AppColors.error),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statChip(String label, int count, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text('$label: $count', style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w600)),
    );
  }

  Widget _buildResultsCard() {
    // Show only the last 50 results in reverse order (newest first)
    final displayResults = _results.reversed.take(50).toList();

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('Resultados', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              const Spacer(),
              Text('${_results.length} registros', style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
            ],
          ),
          const SizedBox(height: 12),

          // Results table
          Table(
            columnWidths: const {
              0: FlexColumnWidth(3),
              1: FlexColumnWidth(1),
              2: FlexColumnWidth(1),
              3: FlexColumnWidth(3),
            },
            children: [
              const TableRow(
                decoration: BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.border))),
                children: [
                  Padding(padding: EdgeInsets.all(8), child: Text('Foto', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12))),
                  Padding(padding: EdgeInsets.all(8), child: Text('Status', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12))),
                  Padding(padding: EdgeInsets.all(8), child: Text('Severidade', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12))),
                  Padding(padding: EdgeInsets.all(8), child: Text('Detalhes', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12))),
                ],
              ),
              ...displayResults.map((r) => TableRow(
                decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.border, width: 0.5))),
                children: [
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: Text(r.photoName, style: const TextStyle(fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: _statusBadge(r.status),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: r.severity != null
                        ? Text('${(r.severity! * 100).toInt()}%', style: TextStyle(fontSize: 11, color: _severityColor(r.severity!)))
                        : const Text('—', style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: Text(r.message, style: const TextStyle(fontSize: 11, color: AppColors.textMuted), maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                ],
              )),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statusBadge(String status) {
    final (color, label) = switch (status) {
      'success' => (AppColors.success, '✅'),
      'skipped' => (AppColors.info, '⏭️'),
      'error' => (AppColors.error, '❌'),
      _ => (AppColors.textMuted, '?'),
    };
    return Text(label, style: TextStyle(fontSize: 14, color: color));
  }

  Color _severityColor(double severity) {
    if (severity >= 0.7) return AppColors.error;
    if (severity >= 0.4) return AppColors.warning;
    return AppColors.success;
  }
}

class _AnalysisResult {
  final String photoName;
  final String photoId;
  final String status; // success, skipped, error
  final double? severity;
  final String message;

  _AnalysisResult({
    required this.photoName,
    required this.photoId,
    required this.status,
    this.severity,
    required this.message,
  });
}
