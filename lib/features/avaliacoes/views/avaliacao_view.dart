import 'package:flutter/material.dart';
import 'package:material_design_icons_flutter/material_design_icons_flutter.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/services/supabase_service.dart';
import '../../../shared/widgets/shared_widgets.dart';
import '../../../shared/widgets/image_viewer.dart';
import '../../fotos/models/foto.dart';

class AvaliacaoView extends StatefulWidget {
  const AvaliacaoView({super.key});

  @override
  State<AvaliacaoView> createState() => _AvaliacaoViewState();
}

class _AvaliacaoViewState extends State<AvaliacaoView> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<Foto> _allFotos = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
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

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width >= 900;

    final fotosNaoAvaliadas = _allFotos.where((f) => f.statusAvaliacao == 'nao_avaliada').toList();
    final fotosSemTorre = _allFotos.where((f) => f.statusAssociacao == 'pendente' || f.statusAssociacao == 'sem_gps').toList();
    final fotosBaixaQualidade = _allFotos.where((f) => f.qualidadeImagem < 0.4).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Avaliações & Fila de Revisão'),
        leading: isWide ? null : Builder(
          builder: (ctx) => IconButton(
            icon: const Icon(Icons.menu_rounded),
            onPressed: () => Scaffold.of(ctx).openDrawer(),
          ),
        ),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadData, tooltip: 'Atualizar'),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(text: 'Não Avaliadas (${fotosNaoAvaliadas.length})'),
            Tab(text: 'Sem Torre (${fotosSemTorre.length})'),
            Tab(text: 'Baixa Qualidade (${fotosBaixaQualidade.length})'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildFotoList(fotosNaoAvaliadas, 'Todas as fotos foram avaliadas'),
                _buildFotoList(fotosSemTorre, 'Todas as fotos estão associadas'),
                _buildFotoList(fotosBaixaQualidade, 'Nenhuma foto com baixa qualidade'),
              ],
            ),
    );
  }

  Widget _buildFotoList(List<Foto> fotos, String emptyMessage) {
    if (fotos.isEmpty) {
      return EmptyState(
        icon: Icons.check_circle_outline,
        title: emptyMessage,
        subtitle: 'Excelente! Não há pendências nesta categoria.',
      );
    }

    return ListView.builder(
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
                  Container(
                    width: 4, height: 50,
                    decoration: BoxDecoration(
                      color: _getPriorityColor(foto),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 12),
                  GestureDetector(
                    onTap: () => FullScreenImageViewer.openFromStorage(context, foto.caminhoStorage, title: foto.nomeArquivo),
                    child: StorageThumbnail(
                      storagePath: foto.caminhoStorage,
                      width: 48,
                      height: 48,
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
                              Icon(MdiIcons.transmissionTower, size: 12, color: AppColors.textSecondary),
                              const SizedBox(width: 4),
                              Text(foto.torreCodigo!, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                              const SizedBox(width: 8),
                            ],
                            Text('Qualidade: ${(foto.qualidadeImagem * 100).toStringAsFixed(0)}%',
                                style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
                          ],
                        ),
                      ],
                    ),
                  ),
                  ElevatedButton(
                    onPressed: () => context.go('/fotos/${foto.id}'),
                    style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8)),
                    child: const Text('Avaliar'),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Color _getPriorityColor(Foto foto) {
    if (foto.qualidadeImagem < 0.3) return AppColors.error;
    if (foto.statusAssociacao == 'sem_gps') return AppColors.warning;
    if (foto.statusAvaliacao == 'nao_avaliada') return AppColors.info;
    return AppColors.textMuted;
  }
}
