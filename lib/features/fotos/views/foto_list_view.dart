import 'package:flutter/material.dart';
import 'package:material_design_icons_flutter/material_design_icons_flutter.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/config/app_constants.dart';
import '../../../shared/services/supabase_service.dart';
import '../../../shared/widgets/shared_widgets.dart';
import '../../../shared/widgets/image_viewer.dart';
import '../models/foto.dart';

class FotoListView extends StatefulWidget {
  const FotoListView({super.key});

  @override
  State<FotoListView> createState() => _FotoListViewState();
}

class _FotoListViewState extends State<FotoListView> {
  String _searchQuery = '';
  String? _filterStatusAvaliacao;
  String? _filterStatusAssociacao;
  List<Foto> _allFotos = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final fotos = await SupabaseService.getFotos();
    setState(() {
      _allFotos = fotos;
      _isLoading = false;
    });
  }

  List<Foto> get _filteredFotos {
    var fotos = _allFotos;
    if (_searchQuery.isNotEmpty) {
      fotos = fotos.where((f) =>
          f.nomeArquivo.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          (f.torreCodigo?.toLowerCase().contains(_searchQuery.toLowerCase()) ?? false)
      ).toList();
    }
    if (_filterStatusAvaliacao != null) {
      fotos = fotos.where((f) => f.statusAvaliacao == _filterStatusAvaliacao).toList();
    }
    if (_filterStatusAssociacao != null) {
      fotos = fotos.where((f) => f.statusAssociacao == _filterStatusAssociacao).toList();
    }
    return fotos;
  }

  Future<void> _reAssociateAll() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reassociar Fotos'),
        content: const Text(
          'Isso irá recalcular a torre mais próxima para TODAS as fotos com GPS.\n\n'
          'Fotos com associação manual NÃO serão preservadas.\n\n'
          'Deseja continuar?',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
            child: const Text('Reassociar'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    // Show progress dialog
    int current = 0;
    int total = 0;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          _progressSetState = setDialogState;
          return AlertDialog(
            title: const Text('Reassociando...'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                LinearProgressIndicator(value: total > 0 ? current / total : null),
                const SizedBox(height: 12),
                Text('$current / $total fotos', style: const TextStyle(color: AppColors.textMuted)),
              ],
            ),
          );
        },
      ),
    );

    final result = await SupabaseService.reAssociateAllPhotos(
      onProgress: (c, t) {
        current = c;
        total = t;
        _progressSetState?.call(() {});
      },
    );

    if (mounted) {
      Navigator.of(context, rootNavigator: true).pop(); // close progress dialog
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('✅ Reassociação concluída: ${result['associated']} atualizadas, ${result['skipped']} sem torre próxima'),
        backgroundColor: AppColors.success,
        duration: const Duration(seconds: 5),
      ));
      _loadData();
    }
  }

  void Function(void Function())? _progressSetState;

  Future<void> _removeDuplicates() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remover Duplicatas'),
        content: const Text(
          'Isso irá buscar fotos com o mesmo nome de arquivo na mesma campanha '
          'e remover as cópias mais antigas.\n\n'
          'Deseja continuar?',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Remover Duplicatas'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    setState(() => _isLoading = true);
    final removed = await SupabaseService.removeDuplicatePhotos();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(removed > 0
            ? '✅ $removed duplicatas removidas!'
            : 'Nenhuma duplicata encontrada.'),
        backgroundColor: removed > 0 ? AppColors.success : AppColors.info,
      ));
      _loadData();
    }
  }

  Future<void> _removeAllPhotos() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remover Todas as Fotos', style: TextStyle(color: AppColors.error)),
        content: const Text(
          'ALERTA: Isso irá apagar TODOS os registros de fotos desta tela no banco de dados.\n\n'
          '(Use apenas para limpar bases de testes)\n\n'
          'Deseja continuar?',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Excluir Tudo'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    setState(() => _isLoading = true);
    try {
      await SupabaseService.removeAllPhotos();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('✅ Todas as fotos foram excluídas com sucesso!'),
          backgroundColor: AppColors.success,
        ));
        _loadData();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Erro ao excluir fotos: $e'),
          backgroundColor: AppColors.error,
        ));
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width >= 900;
    final fotos = _filteredFotos;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Fotos'),
        leading: isWide ? null : Builder(
          builder: (ctx) => IconButton(
            icon: const Icon(Icons.menu_rounded),
            onPressed: () => Scaffold.of(ctx).openDrawer(),
          ),
        ),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.build_rounded),
            tooltip: 'Manutenção',
            onSelected: (value) {
              if (value == 'reassociate') _reAssociateAll();
              if (value == 'dedup') _removeDuplicates();
              if (value == 'remove_all') _removeAllPhotos();
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'reassociate', child: ListTile(
                leading: Icon(Icons.sync, color: AppColors.primary),
                title: Text('Reassociar Fotos', style: TextStyle(fontSize: 14)),
                subtitle: Text('Recalcular torre mais próxima', style: TextStyle(fontSize: 11)),
              )),
              const PopupMenuItem(value: 'dedup', child: ListTile(
                leading: Icon(Icons.delete_sweep, color: AppColors.error),
                title: Text('Remover Duplicatas', style: TextStyle(fontSize: 14)),
                subtitle: Text('Excluir fotos duplicadas', style: TextStyle(fontSize: 11)),
              )),
              const PopupMenuItem(value: 'remove_all', child: ListTile(
                leading: Icon(Icons.delete_forever, color: AppColors.error),
                title: Text('Remover Todas as Fotos', style: TextStyle(fontSize: 14, color: AppColors.error)),
                subtitle: Text('Limpar a tela para testes', style: TextStyle(fontSize: 11)),
              )),
            ],
          ),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadData, tooltip: 'Atualizar'),
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(child: Text('${fotos.length} fotos', style: const TextStyle(color: AppColors.textMuted, fontSize: 13))),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  color: AppColors.bgSurface,
                  child: Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: TextField(
                          decoration: const InputDecoration(hintText: 'Buscar foto...', prefixIcon: Icon(Icons.search, size: 20), isDense: true),
                          onChanged: (v) => setState(() => _searchQuery = v),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: _filterStatusAvaliacao,
                          decoration: const InputDecoration(labelText: 'Avaliação', isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
                          items: const [
                            DropdownMenuItem(value: null, child: Text('Todas')),
                            DropdownMenuItem(value: 'nao_avaliada', child: Text('Não avaliada')),
                            DropdownMenuItem(value: 'avaliada', child: Text('Avaliada')),
                            DropdownMenuItem(value: 'em_revisao', child: Text('Em revisão')),
                          ],
                          onChanged: (v) => setState(() => _filterStatusAvaliacao = v),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: _filterStatusAssociacao,
                          decoration: const InputDecoration(labelText: 'Associação', isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
                          items: const [
                            DropdownMenuItem(value: null, child: Text('Todas')),
                            DropdownMenuItem(value: 'associada', child: Text('Associada')),
                            DropdownMenuItem(value: 'pendente', child: Text('Pendente')),
                            DropdownMenuItem(value: 'sem_gps', child: Text('Sem GPS')),
                          ],
                          onChanged: (v) => setState(() => _filterStatusAssociacao = v),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: fotos.isEmpty
                      ? const EmptyState(icon: Icons.photo_camera_rounded, title: 'Nenhuma foto encontrada')
                      : ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: fotos.length,
                          itemBuilder: (context, index) {
                            final foto = fotos[index];
                            return Card(
                              margin: const EdgeInsets.only(bottom: 8),
                              child: InkWell(
                                onTap: () => context.go('/fotos/${foto.id}'),
                                borderRadius: BorderRadius.circular(12),
                                child: Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Row(
                                    children: [
                                      GestureDetector(
                                        onTap: () => FullScreenImageViewer.openFromStorage(context, foto.caminhoStorage, title: foto.nomeArquivo),
                                        child: StorageThumbnail(
                                          storagePath: foto.caminhoStorage,
                                          width: 56,
                                          height: 56,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(foto.nomeArquivo, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                                            const SizedBox(height: 4),
                                            Row(
                                              children: [
                                                if (foto.torreCodigo != null) ...[
                                                  Icon(MdiIcons.transmissionTower, size: 12, color: AppColors.textMuted),
                                                  const SizedBox(width: 4),
                                                  Text(foto.torreCodigo!, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                                                  const SizedBox(width: 8),
                                                ],
                                                if (foto.distanciaTorreM != null) ...[
                                                  Text('${foto.distanciaTorreM!.toStringAsFixed(0)}m', style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
                                                  const SizedBox(width: 8),
                                                ],
                                                Text(foto.campanhaNome ?? '', style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                      Column(
                                        crossAxisAlignment: CrossAxisAlignment.end,
                                        children: [
                                          StatusBadge(status: foto.statusAvaliacao, labels: AppConstants.statusAvaliacaoLabels),
                                          const SizedBox(height: 4),
                                          StatusBadge(status: foto.statusAssociacao, labels: AppConstants.statusAssociacaoLabels),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }
}
