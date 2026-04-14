import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/config/app_constants.dart';
import '../../../shared/services/supabase_service.dart';
import '../../torres/models/torre.dart';

class AnomaliaFormView extends StatefulWidget {
  const AnomaliaFormView({super.key});

  @override
  State<AnomaliaFormView> createState() => _AnomaliaFormViewState();
}

class _AnomaliaFormViewState extends State<AnomaliaFormView> {
  String? _tipo;
  String _severidade = 'media';
  String? _torreId;
  final _descricaoController = TextEditingController();
  final _recomendacaoController = TextEditingController();
  List<Torre> _torres = [];
  bool _isLoadingTorres = true;

  @override
  void initState() {
    super.initState();
    _loadTorres();
  }

  Future<void> _loadTorres() async {
    final torres = await SupabaseService.getTorres(limit: 200);
    setState(() {
      _torres = torres;
      _isLoadingTorres = false;
    });
  }

  @override
  void dispose() {
    _descricaoController.dispose();
    _recomendacaoController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width >= 900;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Registrar Anomalia'),
        leading: isWide
            ? IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.go('/anomalias'))
            : null,
      ),
      body: _isLoadingTorres
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 700),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Nova Anomalia', style: Theme.of(context).textTheme.headlineMedium),
                    const SizedBox(height: 8),
                    Text('Registre uma ocorrência encontrada durante a inspeção.', style: TextStyle(color: AppColors.textSecondary)),
                    const SizedBox(height: 32),

                    // Torre
                    DropdownButtonFormField<String>(
                      initialValue: _torreId,
                      decoration: const InputDecoration(labelText: 'Torre *'),
                      items: _torres.map((t) => DropdownMenuItem(
                        value: t.id,
                        child: Text('${t.codigoTorre} — ${t.descricao ?? ""}'),
                      )).toList(),
                      onChanged: (v) => setState(() => _torreId = v),
                    ),
                    const SizedBox(height: 20),

                    // Tipo
                    const Text('Tipo de Anomalia *', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: AppConstants.tiposAnomalia.map((t) {
                        final isSelected = _tipo == t;
                        return ChoiceChip(
                          label: Text(AppConstants.anomaliaLabels[t] ?? t),
                          selected: isSelected,
                          onSelected: (v) => setState(() => _tipo = v ? t : null),
                          selectedColor: AppColors.primaryLight.withValues(alpha: 0.3),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 24),

                    // Severidade
                    const Text('Severidade *', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    Row(
                      children: AppConstants.severidades.map((s) {
                        final isSelected = _severidade == s;
                        final color = AppColors.getCriticalityColor(s);
                        return Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            label: Text(AppConstants.severidadeLabels[s] ?? s),
                            selected: isSelected,
                            onSelected: (v) => setState(() => _severidade = s),
                            selectedColor: color.withValues(alpha: 0.3),
                            labelStyle: TextStyle(color: isSelected ? color : null),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 24),

                    // Descrição
                    TextField(
                      controller: _descricaoController,
                      decoration: const InputDecoration(labelText: 'Descrição *', hintText: 'Descreva a anomalia encontrada...'),
                      maxLines: 4,
                    ),
                    const SizedBox(height: 20),

                    // Recomendação
                    TextField(
                      controller: _recomendacaoController,
                      decoration: const InputDecoration(labelText: 'Recomendação', hintText: 'Qual ação recomendada...'),
                      maxLines: 3,
                    ),
                    const SizedBox(height: 32),

                    // Actions
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(onPressed: () => context.go('/anomalias'), child: const Text('Cancelar')),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          flex: 2,
                          child: ElevatedButton.icon(
                            icon: const Icon(Icons.save_rounded),
                            label: const Text('Registrar Anomalia'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.warning,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                            ),
                            onPressed: () {
                              if (_tipo == null || _torreId == null || _descricaoController.text.isEmpty) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Preencha os campos obrigatórios'), backgroundColor: AppColors.error),
                                );
                                return;
                              }
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Anomalia registrada com sucesso!'), backgroundColor: AppColors.success),
                              );
                              context.go('/anomalias');
                            },
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
