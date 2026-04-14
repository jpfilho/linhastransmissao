import 'package:flutter/material.dart';
import '../../../shared/services/supabase_service.dart';
import '../../../core/theme/app_colors.dart';
import 'interactive_span_bar.dart';
import '../../../shared/services/ai_service.dart';

class VisualLayoutEditor extends StatefulWidget {
  final String mapeamentoId;
  final double vaoM;
  final String descricaoServico;

  const VisualLayoutEditor({super.key, required this.mapeamentoId, required this.vaoM, this.descricaoServico = ''});

  @override
  State<VisualLayoutEditor> createState() => _VisualLayoutEditorState();
}

class _VisualLayoutEditorState extends State<VisualLayoutEditor> {
  bool _isLoading = true;
  bool _isSaving = false;
  bool _isAiLoading = false;
  List<RocoSegment> _segments = [];
  bool _hasUnsavedChanges = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void didUpdateWidget(VisualLayoutEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.mapeamentoId != widget.mapeamentoId) {
      _segments = [];
      _hasUnsavedChanges = false;
      _loadData();
    }
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final jsonList = await SupabaseService.getSupressaoLayoutVisual(widget.mapeamentoId);
      if (jsonList != null && mounted) {
        setState(() {
          _segments = jsonList.map((e) => RocoSegment.fromJson(e as Map<String, dynamic>)).toList();
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'Falha: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _save() async {
    setState(() => _isSaving = true);
    try {
      await SupabaseService.saveSupressaoLayoutVisual(
        widget.mapeamentoId, 
        _segments.map((s) => s.toJson()).toList()
      );
      if (mounted) {
        setState(() => _hasUnsavedChanges = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Layout visual salvo com sucesso!'), backgroundColor: AppColors.success)
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao salvar: $e'), backgroundColor: AppColors.error)
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _fillWithAI() async {
    if (widget.descricaoServico.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Descrição vazia. A IA não tem o que ler.'), backgroundColor: Colors.orange)
      );
      return;
    }
    
    setState(() => _isAiLoading = true);
    try {
      final aiResult = await AiService.parseRocoText(widget.descricaoServico, widget.vaoM.round());
      if (aiResult != null && aiResult.isNotEmpty && mounted) {
        setState(() {
          _segments = aiResult.map((e) => RocoSegment.fromJson(e)).toList();
          _hasUnsavedChanges = true;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✨ Mapeamento estruturado pela IA!'), backgroundColor: AppColors.primary)
        );
      } else {
        throw Exception('Sem segmentos ou erro interno da IA.');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('A IA não conseguiu interpretar: $e'), backgroundColor: AppColors.error)
        );
      }
    } finally {
      if (mounted) setState(() => _isAiLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator()));
    }

    if (_error != null) {
      return Center(child: Text(_error!, style: const TextStyle(color: AppColors.error, fontSize: 11)));
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: AppColors.bgElevated,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.primaryLight.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.architecture, size: 14, color: AppColors.primaryLight),
              const SizedBox(width: 4),
              const Text('Editor Visual de Roço', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.primaryLight)),
              const Spacer(),
              if (widget.descricaoServico.isNotEmpty) ...[
                SizedBox(
                  height: 24,
                  child: OutlinedButton.icon(
                    onPressed: _isAiLoading ? null : _fillWithAI,
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Color(0xFF9B59B6)),
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      foregroundColor: const Color(0xFF9B59B6),
                    ),
                    icon: _isAiLoading 
                      ? const SizedBox(width: 10, height: 10, child: CircularProgressIndicator(color: Color(0xFF9B59B6), strokeWidth: 2))
                      : const Icon(Icons.auto_awesome, size: 12),
                    label: const Text('IA', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              if (_hasUnsavedChanges)
                SizedBox(
                  height: 24,
                  child: ElevatedButton(
                    onPressed: _isSaving ? null : _save,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      backgroundColor: AppColors.success,
                      foregroundColor: Colors.white,
                    ),
                    child: _isSaving 
                      ? const SizedBox(width: 10, height: 10, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) 
                      : const Text('SALVAR', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          InteractiveSpanBar(
            totalLengthMeters: widget.vaoM,
            initialSegments: _segments,
            onChanged: (newSegments) {
              setState(() {
                _segments = newSegments;
                _hasUnsavedChanges = true;
              });
            },
          ),
        ],
      ),
    );
  }
}


