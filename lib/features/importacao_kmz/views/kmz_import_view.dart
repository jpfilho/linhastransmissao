import 'package:flutter/material.dart';
import 'package:material_design_icons_flutter/material_design_icons_flutter.dart';
import 'package:file_picker/file_picker.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/kmz_parser.dart';
import '../../../shared/services/supabase_service.dart';

class KmzImportView extends StatefulWidget {
  const KmzImportView({super.key});

  @override
  State<KmzImportView> createState() => _KmzImportViewState();
}

class _KmzImportViewState extends State<KmzImportView> {
  KmzParseResult? _result;
  bool _isLoading = false;
  String? _fileName;
  bool _imported = false;
  Map<String, int>? _importStats;

  Future<void> _pickFile() async {
    final pickerResult = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['kmz', 'kml'],
      withData: true,
    );

    if (pickerResult == null || pickerResult.files.isEmpty) return;

    final file = pickerResult.files.first;
    setState(() {
      _isLoading = true;
      _fileName = file.name;
      _result = null;
      _imported = false;
    });

    try {
      final bytes = file.bytes;
      if (bytes == null) {
        setState(() {
          _isLoading = false;
          _result = KmzParseResult(lines: [], towers: [], errors: ['Não foi possível ler o arquivo']);
        });
        return;
      }

      KmzParseResult result;
      if (file.name.toLowerCase().endsWith('.kml')) {
        result = KmzParser.parseKml(String.fromCharCodes(bytes));
      } else {
        result = KmzParser.parseKmz(bytes);
      }

      setState(() {
        _result = result;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _result = KmzParseResult(lines: [], towers: [], errors: ['Erro inesperado: $e']);
      });
    }
  }

  Future<void> _confirmImport() async {
    if (_result == null) return;
    setState(() => _isLoading = true);

    try {
      // Convert parsed data to maps for SupabaseService
      final parsedLines = _result!.lines.map((l) => <String, dynamic>{
        'name': l.name,
        'description': l.description,
        'code': l.code ?? l.name,
        'coordinates': l.coordinates,
      }).toList();

      final parsedTowers = _result!.towers.map((t) => <String, dynamic>{
        'name': t.name,
        'description': t.description,
        'code': t.code ?? t.name,
        'latitude': t.latitude,
        'longitude': t.longitude,
        'altitude': t.altitude,
        'tipo': t.attributes['tipo'] ?? t.attributes['type'] ?? 'Suspensão',
      }).toList();

      final stats = await SupabaseService.importFromKml(
        parsedLines: parsedLines,
        parsedTowers: parsedTowers,
      );

      setState(() {
        _isLoading = false;
        _imported = true;
        _importStats = stats;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Importação concluída: ${stats['torres_created']} novas torres, '
              '${stats['torres_updated']} atualizadas, '
              '${stats['linhas_created']} novas linhas',
            ),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro na importação: $e'), backgroundColor: AppColors.error),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width >= 900;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Importar KMZ'),
        leading: isWide ? null : Builder(
          builder: (ctx) => IconButton(
            icon: const Icon(Icons.menu_rounded),
            onPressed: () => Scaffold.of(ctx).openDrawer(),
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Importação de Arquivo KMZ/KML', style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 8),
            Text(
              'Selecione um arquivo KMZ ou KML contendo dados geográficos de linhas de transmissão e torres.',
              style: TextStyle(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 24),

            // Upload area
            _buildUploadArea(),

            if (_isLoading) ...[
              const SizedBox(height: 32),
              const Center(child: CircularProgressIndicator()),
              const SizedBox(height: 16),
              const Center(child: Text('Processando arquivo...')),
            ],

            if (_result != null && !_isLoading) ...[
              const SizedBox(height: 32),
              _buildResultSummary(),

              if (_result!.hasErrors) ...[
                const SizedBox(height: 20),
                _buildLogSection('Erros', _result!.errors, AppColors.error),
              ],

              if (_result!.warnings.isNotEmpty) ...[
                const SizedBox(height: 20),
                _buildLogSection('Avisos', _result!.warnings, AppColors.warning),
              ],

              if (_result!.towers.isNotEmpty) ...[
                const SizedBox(height: 20),
                _buildTowersPreview(),
              ],

              if (_result!.lines.isNotEmpty) ...[
                const SizedBox(height: 20),
                _buildLinesPreview(),
              ],

              if (!_imported && _result!.totalElements > 0) ...[
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.check_circle_outline),
                    label: const Text('Confirmar Importação'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.success,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    onPressed: _confirmImport,
                  ),
                ),
              ],

              if (_imported) ...[
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.success.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.success.withValues(alpha: 0.3)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.check_circle, color: AppColors.success),
                          const SizedBox(width: 12),
                          Text('Importação concluída!', style: TextStyle(color: AppColors.success, fontWeight: FontWeight.w600)),
                        ],
                      ),
                      if (_importStats != null) ...[
                        const SizedBox(height: 12),
                        Text('• ${_importStats!['torres_created'] ?? 0} torres criadas', style: const TextStyle(fontSize: 13)),
                        Text('• ${_importStats!['torres_updated'] ?? 0} torres atualizadas', style: const TextStyle(fontSize: 13)),
                        Text('• ${_importStats!['linhas_created'] ?? 0} linhas criadas', style: const TextStyle(fontSize: 13)),
                      ],
                    ],
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildUploadArea() {
    return InkWell(
      onTap: _isLoading ? null : _pickFile,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(40),
        decoration: BoxDecoration(
          color: AppColors.bgCard,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: _fileName != null ? AppColors.success : AppColors.border,
            width: 2,
            strokeAlign: BorderSide.strokeAlignInside,
          ),
        ),
        child: Column(
          children: [
            Icon(
              _fileName != null ? Icons.description_rounded : Icons.upload_file_rounded,
              size: 48,
              color: _fileName != null ? AppColors.success : AppColors.textMuted,
            ),
            const SizedBox(height: 12),
            Text(
              _fileName ?? 'Clique para selecionar arquivo KMZ ou KML',
              style: TextStyle(
                fontSize: 15,
                fontWeight: _fileName != null ? FontWeight.w600 : FontWeight.w400,
                color: _fileName != null ? AppColors.textPrimary : AppColors.textSecondary,
              ),
            ),
            if (_fileName == null) ...[
              const SizedBox(height: 8),
              Text('Formatos aceitos: .kmz, .kml', style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildResultSummary() {
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
          const Text('Resumo da Análise', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 16),
          Row(
            children: [
              _summaryItem(MdiIcons.transmissionTower, '${_result!.towers.length}', 'Torres encontradas', AppColors.accent),
              const SizedBox(width: 24),
              _summaryItem(Icons.power_rounded, '${_result!.lines.length}', 'Linhas encontradas', AppColors.primaryLight),
              const SizedBox(width: 24),
              _summaryItem(Icons.error_outline, '${_result!.errors.length}', 'Erros', AppColors.error),
              const SizedBox(width: 24),
              _summaryItem(Icons.warning_amber, '${_result!.warnings.length}', 'Avisos', AppColors.warning),
            ],
          ),
        ],
      ),
    );
  }

  Widget _summaryItem(IconData icon, String value, String label, Color color) {
    return Expanded(
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color)),
              Text(label, style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLogSection(String title, List<String> items, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(title == 'Erros' ? Icons.error : Icons.warning, color: color, size: 18),
              const SizedBox(width: 8),
              Text(title, style: TextStyle(fontWeight: FontWeight.w600, color: color)),
            ],
          ),
          const SizedBox(height: 8),
          ...items.map((e) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Text('• $e', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          )),
        ],
      ),
    );
  }

  Widget _buildTowersPreview() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Torres Encontradas', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          SizedBox(
            height: 200,
            child: ListView.separated(
              itemCount: _result!.towers.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final tower = _result!.towers[index];
                return ListTile(
                  dense: true,
                  leading: Icon(MdiIcons.transmissionTower, size: 18, color: AppColors.accent),
                  title: Text(tower.name, style: const TextStyle(fontSize: 13)),
                  subtitle: Text(
                    '${tower.latitude.toStringAsFixed(5)}, ${tower.longitude.toStringAsFixed(5)}',
                    style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
                  ),
                  trailing: tower.altitude != null
                      ? Text('${tower.altitude!.toStringAsFixed(0)}m', style: const TextStyle(fontSize: 11))
                      : null,
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLinesPreview() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Linhas Encontradas', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          ...(_result!.lines.map((line) => ListTile(
            dense: true,
            leading: const Icon(Icons.power, size: 18, color: AppColors.primaryLight),
            title: Text(line.name, style: const TextStyle(fontSize: 13)),
            subtitle: Text(
              '${line.coordinates.length} pontos',
              style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
            ),
          ))),
        ],
      ),
    );
  }
}
