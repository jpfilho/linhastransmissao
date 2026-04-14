import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:file_picker/file_picker.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/services/supabase_service.dart';
import '../../../shared/models/linha.dart';

class SupressaoImportView extends StatefulWidget {
  const SupressaoImportView({super.key});

  @override
  State<SupressaoImportView> createState() => _SupressaoImportViewState();
}

class _SupressaoImportViewState extends State<SupressaoImportView> {
  static const String _aiBaseUrl = 'http://127.0.0.1:8000';

  List<Linha> _linhas = [];
  String? _selectedLinhaId;
  String _campanhaRoco = '2026';
  bool _isLoading = true;
  bool _isImporting = false;
  PlatformFile? _selectedFile;
  Map<String, dynamic>? _importResult;
  List<Map<String, dynamic>> _importHistory = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final linhas = await SupabaseService.getLinhas();
    final resumo = await SupabaseService.getSupressaoResumo();
    setState(() {
      _linhas = linhas;
      _importHistory = resumo;
      _isLoading = false;
    });
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx', 'xls'],
      withData: true,
    );
    if (result != null && result.files.isNotEmpty) {
      setState(() {
        _selectedFile = result.files.first;
        _importResult = null;
      });
    }
  }

  Future<void> _importFile() async {
    if (_selectedFile == null || _selectedFile!.bytes == null) return;

    setState(() => _isImporting = true);

    try {
      final request = http.MultipartRequest('POST', Uri.parse('$_aiBaseUrl/import-supressao'));
      request.files.add(http.MultipartFile.fromBytes(
        'file',
        _selectedFile!.bytes!,
        filename: _selectedFile!.name,
      ));
      request.fields['campanha_roco'] = _campanhaRoco;
      if (_selectedLinhaId != null) {
        request.fields['linha_id'] = _selectedLinhaId!;
      }

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        setState(() => _importResult = result);
        _loadData(); // Refresh history
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('✅ Importação concluída! ${result['imported']} registros importados.'),
            backgroundColor: AppColors.success,
          ));
        }
      } else {
        final error = jsonDecode(response.body);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('❌ Erro: ${error['detail'] ?? response.statusCode}'),
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

    setState(() => _isImporting = false);
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width >= 900;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Importar Mapeamento de Roço'),
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
                  Text('Importar Mapeamento de Supressão', style: Theme.of(context).textTheme.headlineMedium),
                  const SizedBox(height: 8),
                  Text(
                    'Importe planilhas Excel (.xlsx) de mapeamento de roço. Os dados serão vinculados às torres existentes automaticamente.',
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 24),

                  // Import Card
                  _buildImportCard(),

                  const SizedBox(height: 24),

                  // Result Card
                  if (_importResult != null) _buildResultCard(),

                  const SizedBox(height: 24),

                  // History
                  if (_importHistory.isNotEmpty) _buildHistoryCard(),
                ],
              ),
            ),
    );
  }

  Widget _buildImportCard() {
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

          // Line selector
          DropdownButtonFormField<String>(
            value: _selectedLinhaId,
            decoration: const InputDecoration(
              labelText: 'Linha de Transmissão (opcional)',
              prefixIcon: Icon(Icons.power),
              helperText: 'Se não selecionada, será detectada automaticamente pela planilha',
            ),
            items: [
              const DropdownMenuItem(value: null, child: Text('Auto-detectar')),
              ..._linhas.map((l) => DropdownMenuItem(value: l.id, child: Text(l.nome))),
            ],
            onChanged: (v) => setState(() => _selectedLinhaId = v),
          ),
          const SizedBox(height: 16),

          // Campaign
          TextFormField(
            initialValue: _campanhaRoco,
            decoration: const InputDecoration(
              labelText: 'Campanha de Roço',
              prefixIcon: Icon(Icons.calendar_today),
            ),
            onChanged: (v) => _campanhaRoco = v,
          ),
          const SizedBox(height: 20),

          // File picker
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.bgElevated,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: _selectedFile != null ? AppColors.success : AppColors.border),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _selectedFile != null ? Icons.check_circle : Icons.attach_file,
                        color: _selectedFile != null ? AppColors.success : AppColors.textMuted,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _selectedFile?.name ?? 'Nenhum arquivo selecionado',
                          style: TextStyle(
                            color: _selectedFile != null ? AppColors.textPrimary : AppColors.textMuted,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (_selectedFile != null)
                        Text(
                          '${(_selectedFile!.size / 1024).toStringAsFixed(0)} KB',
                          style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              ElevatedButton.icon(
                icon: const Icon(Icons.folder_open),
                label: const Text('Selecionar'),
                onPressed: _isImporting ? null : _pickFile,
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Import button
          ElevatedButton.icon(
            icon: Icon(_isImporting ? Icons.hourglass_top : Icons.upload_rounded),
            label: Text(_isImporting ? 'Importando...' : 'Importar Planilha'),
            onPressed: (_isImporting || _selectedFile == null) ? null : _importFile,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResultCard() {
    final r = _importResult!;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.success.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('✅ Resultado da Importação', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 16),
          Wrap(
            spacing: 16,
            runSpacing: 8,
            children: [
              _infoChip('📄 Planilha', r['sheet_name'] ?? '—'),
              _infoChip('🔌 LT', r['lt_name'] ?? '—'),
              _infoChip('📥 Importados', '${r['imported']}'),
              _infoChip('❌ Erros', '${r['errors']}'),
              _infoChip('🔗 Torres vinculadas', '${r['towers_matched']}'),
              _infoChip('⚠️ Sem vínculo', '${r['towers_unmatched']}'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _infoChip(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.bgElevated,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 10, color: AppColors.textMuted)),
          const SizedBox(height: 2),
          Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _buildHistoryCard() {
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
          const Text('📊 Resumo por Linha', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          Table(
            columnWidths: const {
              0: FlexColumnWidth(3),
              1: FlexColumnWidth(1),
              2: FlexColumnWidth(1),
              3: FlexColumnWidth(1),
              4: FlexColumnWidth(1),
              5: FlexColumnWidth(1),
            },
            children: [
              const TableRow(
                decoration: BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.border))),
                children: [
                  Padding(padding: EdgeInsets.all(8), child: Text('Linha', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12))),
                  Padding(padding: EdgeInsets.all(8), child: Text('Total', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12))),
                  Padding(padding: EdgeInsets.all(8), child: Text('Concl.', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12))),
                  Padding(padding: EdgeInsets.all(8), child: Text('P1', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12))),
                  Padding(padding: EdgeInsets.all(8), child: Text('P2', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12))),
                  Padding(padding: EdgeInsets.all(8), child: Text('%', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12))),
                ],
              ),
              ..._importHistory.map((r) => TableRow(
                children: [
                  Padding(padding: const EdgeInsets.all(8), child: Text('${r['linha_nome']}', style: const TextStyle(fontSize: 12))),
                  Padding(padding: const EdgeInsets.all(8), child: Text('${r['total_vaos']}', style: const TextStyle(fontSize: 12))),
                  Padding(padding: const EdgeInsets.all(8), child: Text('${r['vaos_concluidos']}', style: const TextStyle(fontSize: 12, color: AppColors.success))),
                  Padding(padding: const EdgeInsets.all(8), child: Text('${r['vaos_p1']}', style: const TextStyle(fontSize: 12, color: AppColors.error))),
                  Padding(padding: const EdgeInsets.all(8), child: Text('${r['vaos_p2']}', style: const TextStyle(fontSize: 12, color: AppColors.warning))),
                  Padding(padding: const EdgeInsets.all(8), child: Text('${r['percentual_concluido'] ?? 0}%', style: const TextStyle(fontSize: 12))),
                ],
              )),
            ],
          ),
        ],
      ),
    );
  }
}
