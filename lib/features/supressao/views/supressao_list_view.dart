import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/services/supabase_service.dart';
import '../../../shared/models/linha.dart';
import '../models/mapeamento_supressao.dart';

class SupressaoListView extends StatefulWidget {
  const SupressaoListView({super.key});

  @override
  State<SupressaoListView> createState() => _SupressaoListViewState();
}

class _SupressaoListViewState extends State<SupressaoListView> {
  List<Linha> _linhas = [];
  String? _selectedLinhaId;
  List<MapeamentoSupressao> _dados = [];
  Map<String, dynamic> _stats = {};
  bool _isLoading = true;
  bool _isLoadingData = false;
  String? _filterPrioridade;
  String? _filterStatus; // concluido, pendente

  @override
  void initState() {
    super.initState();
    _loadInitial();
  }

  Future<void> _loadInitial() async {
    setState(() => _isLoading = true);
    final linhas = await SupabaseService.getLinhas();
    final stats = await SupabaseService.getSupressaoStats();
    setState(() {
      _linhas = linhas;
      _stats = stats;
      _isLoading = false;
    });
  }

  Future<void> _loadData() async {
    if (_selectedLinhaId == null) return;
    setState(() => _isLoadingData = true);
    final data = await SupabaseService.getSupressaoByLinha(_selectedLinhaId!);
    setState(() {
      _dados = data.map((d) => MapeamentoSupressao.fromJson(d)).toList();
      _isLoadingData = false;
    });
  }

  List<MapeamentoSupressao> get _filteredDados {
    var list = List<MapeamentoSupressao>.from(_dados);
    if (_filterPrioridade != null) {
      list = list.where((d) => d.prioridade == _filterPrioridade).toList();
    }
    if (_filterStatus == 'concluido') {
      list = list.where((d) => d.rocoConcluido).toList();
    } else if (_filterStatus == 'pendente') {
      list = list.where((d) => !d.rocoConcluido).toList();
    }
    // Sort EST numerically: "2/1" < "3/1" < "10/1"
    list.sort((a, b) {
      final aParts = a.estCodigo.split('/');
      final bParts = b.estCodigo.split('/');
      final a1 = int.tryParse(aParts[0]) ?? 9999;
      final b1 = int.tryParse(bParts[0]) ?? 9999;
      if (a1 != b1) return a1.compareTo(b1);
      final a2 = aParts.length > 1 ? (int.tryParse(aParts[1]) ?? 0) : 0;
      final b2 = bParts.length > 1 ? (int.tryParse(bParts[1]) ?? 0) : 0;
      return a2.compareTo(b2);
    });
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width >= 900;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Supressão de Vegetação'),
        leading: isWide ? null : Builder(
          builder: (ctx) => IconButton(
            icon: const Icon(Icons.menu_rounded),
            onPressed: () => Scaffold.of(ctx).openDrawer(),
          ),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Stats bar
                _buildStatsBar(),
                
                // Filters
                _buildFilters(),
                
                // Data table
                Expanded(child: _buildDataTable()),
              ],
            ),
    );
  }

  Widget _buildStatsBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      color: AppColors.bgElevated,
      child: Row(
        children: [
          _statItem('Total Vãos', '${_stats['total_vaos'] ?? 0}', Icons.grid_view, AppColors.primary),
          _statItem('Concluídos', '${_stats['concluidos'] ?? 0}', Icons.check_circle, AppColors.success),
          _statItem('P1 (Crítica)', '${_stats['p1'] ?? 0}', Icons.warning, AppColors.error),
          _statItem('P2 (Alta)', '${_stats['p2'] ?? 0}', Icons.info, AppColors.warning),
        ],
      ),
    );
  }

  Widget _statItem(String label, String value, IconData icon, Color color) {
    return Expanded(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: color)),
              Text(label, style: const TextStyle(fontSize: 10, color: AppColors.textMuted)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFilters() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          // Line selector
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
                setState(() => _selectedLinhaId = v);
                _loadData();
              },
            ),
          ),
          const SizedBox(width: 12),
          
          // Priority filter
          Expanded(
            flex: 2,
            child: DropdownButtonFormField<String>(
              value: _filterPrioridade,
              decoration: const InputDecoration(
                labelText: 'Prioridade',
                prefixIcon: Icon(Icons.flag),
                isDense: true,
              ),
              items: const [
                DropdownMenuItem(value: null, child: Text('Todas')),
                DropdownMenuItem(value: 'P1', child: Text('🔴 P1 - Crítica')),
                DropdownMenuItem(value: 'P2', child: Text('🟡 P2 - Alta')),
                DropdownMenuItem(value: 'P3', child: Text('🟢 P3 - Normal')),
              ],
              onChanged: (v) => setState(() => _filterPrioridade = v),
            ),
          ),
          const SizedBox(width: 12),
          
          // Status filter
          Expanded(
            flex: 2,
            child: DropdownButtonFormField<String>(
              value: _filterStatus,
              decoration: const InputDecoration(
                labelText: 'Status',
                prefixIcon: Icon(Icons.check_box),
                isDense: true,
              ),
              items: const [
                DropdownMenuItem(value: null, child: Text('Todos')),
                DropdownMenuItem(value: 'concluido', child: Text('✅ Concluído')),
                DropdownMenuItem(value: 'pendente', child: Text('⏳ Pendente')),
              ],
              onChanged: (v) => setState(() => _filterStatus = v),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDataTable() {
    if (_selectedLinhaId == null) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.grass, size: 64, color: AppColors.textMuted),
            SizedBox(height: 16),
            Text('Selecione uma Linha de Transmissão', style: TextStyle(color: AppColors.textMuted, fontSize: 16)),
          ],
        ),
      );
    }

    if (_isLoadingData) {
      return const Center(child: CircularProgressIndicator());
    }

    final filtered = _filteredDados;
    if (filtered.isEmpty) {
      return const Center(
        child: Text('Nenhum dado de supressão encontrado', style: TextStyle(color: AppColors.textMuted)),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SingleChildScrollView(
        child: DataTable(
          headingRowColor: WidgetStateProperty.all(AppColors.bgElevated),
          columnSpacing: 16,
          dataRowMinHeight: 36,
          dataRowMaxHeight: 48,
          columns: const [
            DataColumn(label: Text('EST', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 11))),
            DataColumn(label: Text('Prioridade', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 11))),
            DataColumn(label: Text('Vão (m)', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 11)), numeric: true),
            DataColumn(label: Text('Larg (m)', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 11)), numeric: true),
            DataColumn(label: Text('Mec Ext', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 11)), numeric: true),
            DataColumn(label: Text('Man Ext', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 11)), numeric: true),
            DataColumn(label: Text('Concluído', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 11))),
            DataColumn(label: Text('GGT', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 11))),
            DataColumn(label: Text('Descrição', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 11))),
            DataColumn(label: Text('Torre', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 11))),
          ],
          rows: filtered.map((d) => DataRow(
            color: WidgetStateProperty.resolveWith<Color?>((states) {
              if (d.rocoConcluido) return AppColors.success.withValues(alpha: 0.05);
              if (d.prioridade == 'P1') return AppColors.error.withValues(alpha: 0.05);
              return null;
            }),
            cells: [
              DataCell(Text(d.estCodigo, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12))),
              DataCell(_prioridadeBadge(d.prioridade)),
              DataCell(Text('${d.vaoFrenteM?.toStringAsFixed(0) ?? '—'}', style: const TextStyle(fontSize: 12))),
              DataCell(Text('${d.larguraM?.toStringAsFixed(0) ?? '—'}', style: const TextStyle(fontSize: 12))),
              DataCell(Text('${d.mapMecExtensao?.toStringAsFixed(0) ?? '—'}', style: const TextStyle(fontSize: 12))),
              DataCell(Text('${d.mapManExtensao?.toStringAsFixed(0) ?? '—'}', style: const TextStyle(fontSize: 12))),
              DataCell(Icon(
                d.rocoConcluido ? Icons.check_circle : Icons.radio_button_unchecked,
                size: 18,
                color: d.rocoConcluido ? AppColors.success : AppColors.textMuted,
              )),
              DataCell(Text(d.codigoGgtExecucao ?? '—', style: const TextStyle(fontSize: 12))),
              DataCell(SizedBox(
                width: 250,
                child: Text(d.descricaoServico ?? '', style: const TextStyle(fontSize: 11), maxLines: 2, overflow: TextOverflow.ellipsis),
              )),
              DataCell(Text(d.codigoTorre ?? '—', style: const TextStyle(fontSize: 11, color: AppColors.textMuted))),
            ],
          )).toList(),
        ),
      ),
    );
  }

  Widget _prioridadeBadge(String? prioridade) {
    final (color, label) = switch (prioridade) {
      'P1' => (AppColors.error, 'P1'),
      'P2' => (AppColors.warning, 'P2'),
      'P3' => (AppColors.success, 'P3'),
      _ => (AppColors.textMuted, '—'),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color)),
    );
  }
}
