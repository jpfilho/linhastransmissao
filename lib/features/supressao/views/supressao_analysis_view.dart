import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../../core/theme/app_colors.dart';
import '../../../shared/services/supabase_service.dart';
import '../../../shared/models/linha.dart';
import '../../torres/models/torre.dart';

class SupressaoAnalysisView extends StatefulWidget {
  const SupressaoAnalysisView({super.key});

  @override
  State<SupressaoAnalysisView> createState() => _SupressaoAnalysisViewState();
}

class _SupressaoAnalysisViewState extends State<SupressaoAnalysisView> {
  static const String _aiBaseUrl = 'http://127.0.0.1:8000';

  List<Linha> _linhas = [];
  List<Torre> _torres = [];
  String? _selectedLinhaId;
  String? _selectedTorreId;
  bool _isLoading = true;
  bool _isAnalyzing = false;
  Map<String, dynamic>? _analysisResult;
  String? _photoUrl;

  @override
  void initState() {
    super.initState();
    _loadLinhas();
  }

  Future<void> _loadLinhas() async {
    setState(() => _isLoading = true);
    final linhas = await SupabaseService.getLinhas();
    setState(() {
      _linhas = linhas;
      _isLoading = false;
    });
  }

  Future<void> _loadTorres(String linhaId) async {
    final torres = await SupabaseService.getTorresByLinha(linhaId);
    // Natural numeric sort: "PDDTSDW2 1-1" < "PDDTSDW2 2-1" < "PDDTSDW2 10-1"
    torres.sort((a, b) {
      final aNum = _extractEstNumber(a.codigoTorre);
      final bNum = _extractEstNumber(b.codigoTorre);
      if (aNum != null && bNum != null) {
        final cmp = aNum.$1.compareTo(bNum.$1);
        if (cmp != 0) return cmp;
        return aNum.$2.compareTo(bNum.$2);
      }
      return a.codigoTorre.compareTo(b.codigoTorre);
    });
    setState(() => _torres = torres);
  }

  /// Extract numeric parts from torre code: "PDDTSDW2 142-2" -> (142, 2)
  (int, int)? _extractEstNumber(String code) {
    final match = RegExp(r'(\d+)-(\d+)$').firstMatch(code);
    if (match != null) {
      return (int.parse(match.group(1)!), int.parse(match.group(2)!));
    }
    return null;
  }

  Future<void> _runAnalysis() async {
    if (_selectedTorreId == null) return;
    setState(() {
      _isAnalyzing = true;
      _analysisResult = null;
    });

    try {
      // First get the photo URL for display
      final photos = await SupabaseService.getFotosByTorre(_selectedTorreId!);
      if (photos.isNotEmpty) {
        final foto = photos.first;
        setState(() => _photoUrl = SupabaseService.getPhotoUrl(foto.caminhoStorage));
      }

      // Call the AI analysis endpoint
      final response = await http.post(
        Uri.parse('$_aiBaseUrl/analyze-supressao'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'torre_id': _selectedTorreId}),
      );

      if (response.statusCode == 200) {
        setState(() => _analysisResult = jsonDecode(response.body));
      } else {
        final error = jsonDecode(response.body);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('❌ ${error['detail'] ?? 'Erro na análise'}'),
            backgroundColor: AppColors.error,
          ));
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('❌ Erro de conexão: $e'),
          backgroundColor: AppColors.error,
        ));
      }
    }

    setState(() => _isAnalyzing = false);
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width >= 900;

    return Scaffold(
      appBar: AppBar(
        title: const Text('IA + Supressão de Vegetação'),
        leading: isWide ? null : Builder(
          builder: (ctx) => IconButton(
            icon: const Icon(Icons.menu_rounded),
            onPressed: () => Scaffold.of(ctx).openDrawer(),
          ),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Análise IA × Mapeamento de Roço', style: Theme.of(context).textTheme.headlineMedium),
                  const SizedBox(height: 8),
                  Text(
                    'A IA compara a foto aérea com o planejamento de supressão do mapeamento, avaliando se o roço foi executado e sugerindo prioridades.',
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 24),

                  // Selection
                  _buildSelectionCard(),

                  // Photo + Results side by side
                  if (_analysisResult != null || _isAnalyzing) ...[
                    const SizedBox(height: 24),
                    isWide ? _buildWideLayout() : _buildNarrowLayout(),
                  ],
                ],
              ),
            ),
    );
  }

  Widget _buildSelectionCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          // Linha dropdown
          Expanded(
            flex: 3,
            child: DropdownButtonFormField<String>(
              value: _selectedLinhaId,
              decoration: const InputDecoration(
                labelText: 'Linha de Transmissão',
                prefixIcon: Icon(Icons.power),
                isDense: true,
              ),
              items: _linhas.map((l) => DropdownMenuItem(value: l.id, child: Text(l.nome))).toList(),
              onChanged: (v) {
                setState(() {
                  _selectedLinhaId = v;
                  _selectedTorreId = null;
                  _analysisResult = null;
                  _torres = [];
                });
                if (v != null) _loadTorres(v);
              },
            ),
          ),
          const SizedBox(width: 12),
          // Searchable torre selector
          Expanded(
            flex: 3,
            child: Autocomplete<Torre>(
              displayStringForOption: (t) => t.codigoTorre,
              optionsBuilder: (textEditingValue) {
                final query = textEditingValue.text.toLowerCase();
                if (query.isEmpty) return _torres;
                return _torres.where((t) => t.codigoTorre.toLowerCase().contains(query));
              },
              onSelected: (torre) => setState(() {
                _selectedTorreId = torre.id;
                _analysisResult = null;
              }),
              fieldViewBuilder: (context, controller, focusNode, onSubmitted) {
                return TextFormField(
                  controller: controller,
                  focusNode: focusNode,
                  decoration: InputDecoration(
                    labelText: 'Torre / Vão (digite para buscar)',
                    prefixIcon: const Icon(Icons.cell_tower),
                    isDense: true,
                    suffixIcon: controller.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 18),
                            onPressed: () {
                              controller.clear();
                              setState(() {
                                _selectedTorreId = null;
                                _analysisResult = null;
                              });
                            },
                          )
                        : null,
                  ),
                );
              },
              optionsViewBuilder: (context, onSelected, options) {
                return Align(
                  alignment: Alignment.topLeft,
                  child: Material(
                    elevation: 4,
                    borderRadius: BorderRadius.circular(8),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 300, maxWidth: 400),
                      child: ListView.builder(
                        padding: EdgeInsets.zero,
                        shrinkWrap: true,
                        itemCount: options.length,
                        itemBuilder: (context, index) {
                          final torre = options.elementAt(index);
                          return ListTile(
                            dense: true,
                            title: Text(torre.codigoTorre, style: const TextStyle(fontSize: 13)),
                            onTap: () => onSelected(torre),
                          );
                        },
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(width: 16),
          ElevatedButton.icon(
            icon: Icon(_isAnalyzing ? Icons.hourglass_top : Icons.auto_awesome),
            label: Text(_isAnalyzing ? 'Analisando...' : 'Analisar com IA'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            ),
            onPressed: (_isAnalyzing || _selectedTorreId == null) ? null : _runAnalysis,
          ),
        ],
      ),
    );
  }

  Widget _buildWideLayout() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Photo
        Expanded(flex: 4, child: _buildPhotoCard()),
        const SizedBox(width: 16),
        // Results
        Expanded(flex: 6, child: _isAnalyzing ? _buildLoadingCard() : _buildResultsCard()),
      ],
    );
  }

  Widget _buildNarrowLayout() {
    return Column(
      children: [
        _buildPhotoCard(),
        const SizedBox(height: 16),
        _isAnalyzing ? _buildLoadingCard() : _buildResultsCard(),
      ],
    );
  }

  Widget _buildPhotoCard() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('📷 Foto Aérea', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
          ),
          if (_photoUrl != null)
            ClipRRect(
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(12),
                bottomRight: Radius.circular(12),
              ),
              child: Image.network(
                _photoUrl!,
                fit: BoxFit.cover,
                width: double.infinity,
                height: 400,
                errorBuilder: (_, __, ___) => const SizedBox(
                  height: 300,
                  child: Center(child: Icon(Icons.broken_image, size: 48, color: AppColors.textMuted)),
                ),
              ),
            )
          else
            const SizedBox(
              height: 300,
              child: Center(child: Text('Nenhuma foto disponível', style: TextStyle(color: AppColors.textMuted))),
            ),
        ],
      ),
    );
  }

  Widget _buildLoadingCard() {
    return Container(
      padding: const EdgeInsets.all(40),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: const Column(
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 16),
          Text('🤖 A IA está analisando a foto e comparando com o mapeamento de roço...',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textMuted),
          ),
          SizedBox(height: 8),
          Text('Isso pode levar alguns segundos',
            style: TextStyle(fontSize: 12, color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }

  Widget _buildResultsCard() {
    if (_analysisResult == null) return const SizedBox.shrink();
    final ai = _analysisResult!['ai_analysis'] as Map<String, dynamic>? ?? {};
    final supp = _analysisResult!['suppression_data'] as Map<String, dynamic>? ?? {};
    final cvVeg = _analysisResult!['cv_vegetation_score'] ?? 0;

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
          // Header
          Row(
            children: [
              const Text('🤖 Resultado da Análise IA', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
              const Spacer(),
              _buildConfiancaBadge(ai['confianca']),
            ],
          ),
          const SizedBox(height: 16),

          // Status badges
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _statusBadge('Vegetação', ai['vegetacao_status'] ?? '?', _vegStatusColor(ai['vegetacao_status'])),
              _statusBadge('Roço Necessário', ai['roco_necessario'] == true ? 'SIM' : 'NÃO',
                  ai['roco_necessario'] == true ? AppColors.error : AppColors.success),
              _statusBadge('Roço Executado', ai['roco_aparentemente_executado'] == true ? 'SIM' : 'NÃO',
                  ai['roco_aparentemente_executado'] == true ? AppColors.success : AppColors.warning),
              _statusBadge('Conformidade', ai['concordancia_mapeamento'] ?? '?', _conformColor(ai['concordancia_mapeamento'])),
              _statusBadge('Prioridade IA', ai['prioridade_sugerida'] ?? '?', _priorColor(ai['prioridade_sugerida'])),
              _statusBadge('Tipo Roço', ai['tipo_roco_sugerido'] ?? '?', AppColors.primary),
              _statusBadge('CV Veg Score', '${cvVeg}%', AppColors.primary),
            ],
          ),
          const SizedBox(height: 16),

          // Comparison: Mapping vs AI
          _buildComparisonSection(supp, ai),
          const SizedBox(height: 16),

          // Observations
          if (ai['observacoes'] != null) ...[
            const Text('📋 Observações', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.bgElevated,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(ai['observacoes'], style: const TextStyle(fontSize: 13, height: 1.4)),
            ),
          ],
          const SizedBox(height: 12),

          // Recommended action
          if (ai['acao_recomendada'] != null) ...[
            const Text('✅ Ação Recomendada', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.success.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.success.withValues(alpha: 0.3)),
              ),
              child: Text(ai['acao_recomendada'], style: const TextStyle(fontSize: 13, height: 1.4)),
            ),
          ],
          const SizedBox(height: 12),

          // Risks
          if (ai['riscos_identificados'] is List && (ai['riscos_identificados'] as List).isNotEmpty) ...[
            const Text('⚠️ Riscos Identificados', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
            const SizedBox(height: 8),
            ...((ai['riscos_identificados'] as List).map((r) => Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('• ', style: TextStyle(color: AppColors.warning, fontWeight: FontWeight.bold)),
                  Expanded(child: Text('$r', style: const TextStyle(fontSize: 12))),
                ],
              ),
            ))),
          ],
          const SizedBox(height: 12),

          // Attention zones
          if (ai['zonas_atencao'] is List && (ai['zonas_atencao'] as List).isNotEmpty) ...[
            const Text('🎯 Zonas de Atenção', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
            const SizedBox(height: 8),
            ...((ai['zonas_atencao'] as List).map((z) {
              final zona = z as Map<String, dynamic>;
              return Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: _sevColor(zona['severidade']).withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: _sevColor(zona['severidade']).withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.location_on, size: 16, color: _sevColor(zona['severidade'])),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${zona['descricao']}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
                          Text('Posição: ${zona['posicao']} | Área: ~${zona['area_percentual']}% | Severidade: ${zona['severidade']}',
                            style: const TextStyle(fontSize: 10, color: AppColors.textMuted)),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            })),
          ],
        ],
      ),
    );
  }

  Widget _buildComparisonSection(Map<String, dynamic> supp, Map<String, dynamic> ai) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.bgElevated,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('📊 Mapeamento vs IA', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          const SizedBox(height: 8),
          Table(
            columnWidths: const {0: FlexColumnWidth(3), 1: FlexColumnWidth(2), 2: FlexColumnWidth(2)},
            children: [
              const TableRow(children: [
                Padding(padding: EdgeInsets.all(4), child: Text('', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600))),
                Padding(padding: EdgeInsets.all(4), child: Text('Mapeamento', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600))),
                Padding(padding: EdgeInsets.all(4), child: Text('IA', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600))),
              ]),
              _compRow('Prioridade', supp['prioridade'] ?? '—', ai['prioridade_sugerida'] ?? '—'),
              _compRow('Roço Concluído', supp['roco_concluido'] == true ? 'SIM' : 'NÃO', ai['roco_aparentemente_executado'] == true ? 'SIM' : 'NÃO'),
              _compRow('Extensão', '${supp['map_mec_extensao'] ?? 0}+${supp['map_man_extensao'] ?? 0}m', '~${ai['extensao_estimada_m'] ?? '?'}m necessários'),
            ],
          ),
        ],
      ),
    );
  }

  TableRow _compRow(String label, String mapeamento, String ia) {
    return TableRow(children: [
      Padding(padding: const EdgeInsets.all(4), child: Text(label, style: const TextStyle(fontSize: 11))),
      Padding(padding: const EdgeInsets.all(4), child: Text(mapeamento, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500))),
      Padding(padding: const EdgeInsets.all(4), child: Text(ia, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500))),
    ]);
  }

  Widget _statusBadge(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Text(label, style: const TextStyle(fontSize: 9, color: AppColors.textMuted)),
          const SizedBox(height: 2),
          Text(value, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: color)),
        ],
      ),
    );
  }

  Widget _buildConfiancaBadge(dynamic confianca) {
    final c = (confianca is num) ? confianca.toDouble() : 0.5;
    final pct = (c * 100).round();
    final color = c >= 0.8 ? AppColors.success : c >= 0.5 ? AppColors.warning : AppColors.error;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text('Confiança: $pct%', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color)),
    );
  }

  Color _vegStatusColor(String? s) => switch (s) {
    'limpa' => AppColors.success,
    'parcial' => AppColors.warning,
    'densa' => AppColors.error,
    'critica' => const Color(0xFFB71C1C),
    _ => AppColors.textMuted,
  };

  Color _conformColor(String? s) => switch (s) {
    'conforme' => AppColors.success,
    'parcial' => AppColors.warning,
    'divergente' => AppColors.error,
    _ => AppColors.textMuted,
  };

  Color _priorColor(String? s) => switch (s) {
    'P1' => AppColors.error,
    'P2' => AppColors.warning,
    'P3' => AppColors.success,
    _ => AppColors.textMuted,
  };

  Color _sevColor(String? s) => switch (s) {
    'critica' => const Color(0xFFB71C1C),
    'alta' => AppColors.error,
    'media' => AppColors.warning,
    'baixa' => AppColors.success,
    _ => AppColors.textMuted,
  };
}
