import 'package:flutter/material.dart';
import 'package:material_design_icons_flutter/material_design_icons_flutter.dart';
import 'package:file_picker/file_picker.dart';
import 'package:uuid/uuid.dart';
import 'dart:typed_data';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/exif_reader.dart';
import '../../../core/utils/quality_scorer.dart';
import '../../../core/utils/distance_calculator.dart';
import '../../../shared/services/supabase_service.dart';
import '../../../shared/models/linha.dart';
import '../../../shared/models/campanha.dart';
import '../../../features/fotos/models/foto.dart';
import '../../../features/torres/models/torre.dart';

const _uuid = Uuid();

enum DuplicateRule { overwrite, keepBoth, ignore }

class PhotoImportView extends StatefulWidget {
  const PhotoImportView({super.key});

  @override
  State<PhotoImportView> createState() => _PhotoImportViewState();
}

class _PhotoImportViewState extends State<PhotoImportView> {
  List<_PhotoPreview> _photos = [];
  bool _isLoading = false;
  bool _isUploading = false;
  double _uploadProgress = 0;
  String _newCampaignName = '';
  String? _selectedCampanhaId; // null = create new
  String? _selectedLinhaId;
  bool _imported = false;
  int _photosAssociated = 0;
  int _photosImported = 0;

  // Duplication tracking
  int _duplicateCount = 0;
  int _newCount = 0;
  List<String> _duplicateNames = [];
  DuplicateRule _duplicateRule = DuplicateRule.ignore;

  // Cached data from Supabase
  List<Torre> _torres = [];
  List<Linha> _linhas = [];
  List<Campanha> _campanhas = [];
  bool _dataLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadCachedData();
  }

  Future<void> _loadCachedData() async {
    final results = await Future.wait([
      SupabaseService.getTorres(),
      SupabaseService.getLinhas(),
      SupabaseService.getCampanhas(),
    ]);
    setState(() {
      _torres = results[0] as List<Torre>;
      _linhas = results[1] as List<Linha>
        ..sort((a, b) => a.nome.toLowerCase().compareTo(b.nome.toLowerCase()));
      _campanhas = results[2] as List<Campanha>;
      _dataLoaded = true;
    });
  }

  Future<void> _pickPhotos() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: true,
      withData: true,
    );

    if (result == null || result.files.isEmpty) return;

    setState(() => _isLoading = true);

    try {
      // Build tower coordinate list for nearest-tower lookup
      final towers = _torres
          .map((t) => {'lat': t.latitude, 'lng': t.longitude})
          .toList();

      final photos = <_PhotoPreview>[];
      for (final file in result.files) {
        ExifData? exif;
        double quality = 0;
        Torre? nearestTorre;
        double? distanceM;

        if (file.bytes != null) {
          try {
            exif = await ExifReader.readFromBytes(file.bytes!);
          } catch (e) {
            debugPrint('Erro ao ler EXIF de ${file.name}: $e');
            exif = ExifData(); // Fallback to avoid dropping the photo
          }
          
          quality = QualityScorer.calculateScore(
            hasGps: exif!.hasGps,
            imageWidth: exif.imageWidth,
            imageHeight: exif.imageHeight,
            altitude: exif.altitude,
            hasDateTime: exif.dateTime != null,
            hasAzimuth: exif.azimuth != null,
          );

          // Auto-associate with nearest tower if GPS is available
          if (exif!.hasGps && towers.isNotEmpty) {
            final nearest = DistanceCalculator.findNearestTower(
              exif.latitude!, exif.longitude!, towers,
            );
            if (nearest != null) {
              nearestTorre = _torres[nearest.key];
              distanceM = nearest.value;
            }
          }
        }

        photos.add(_PhotoPreview(
          fileName: file.name,
          sizeBytes: file.size,
          bytes: file.bytes,
          exif: exif,
          quality: quality,
          nearestTorre: nearestTorre,
          distanceM: distanceM,
        ));
      }

      setState(() {
        _photos = photos;
        _isLoading = false;
      });
      
      // Perform association calculation based on the currently selected line (if any)
      _recalculateAssociations();
      _checkDuplicates();
      
    } catch (e) {
      debugPrint('General error in _pickPhotos: $e');
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao processar imagens: $e'), backgroundColor: AppColors.error),
        );
      }
    }
  }

  void _recalculateAssociations() {
    if (_photos.isEmpty || _torres.isEmpty) return;

    // Filter available towers if a specific line is selected
    final validTowers = _selectedLinhaId != null
        ? _torres.where((t) => t.linhaId == _selectedLinhaId).toList()
        : _torres;

    if (validTowers.isEmpty) {
      // No towers to associate with
      setState(() {
        for (final p in _photos) {
          p.nearestTorre = null;
          p.distanceM = null;
        }
      });
      return;
    }

    final validCoords = validTowers
        .map((t) => {'lat': t.latitude, 'lng': t.longitude})
        .toList();

    setState(() {
      for (final p in _photos) {
        if (p.exif?.hasGps == true) {
          final nearest = DistanceCalculator.findNearestTower(
            p.exif!.latitude!,
            p.exif!.longitude!,
            validCoords,
          );
          if (nearest != null) {
            p.nearestTorre = validTowers[nearest.key];
            p.distanceM = nearest.value;
          } else {
            p.nearestTorre = null;
            p.distanceM = null;
          }
        }
      }
    });
  }

  Future<void> _checkDuplicates() async {
    if (_selectedCampanhaId == null || _selectedLinhaId == null || _photos.isEmpty) {
      if (mounted) {
        setState(() {
          _duplicateNames = [];
          _duplicateCount = 0;
          _newCount = _photos.length;
        });
      }
      return;
    }

    try {
      final existingNames = await SupabaseService.getFotoFileNames(_selectedCampanhaId!, _selectedLinhaId!);
      final existingSet = existingNames.toSet();
      
      int dupes = 0;
      final duplicateList = <String>[];
      for (final p in _photos) {
        if (existingSet.contains(p.fileName)) {
          dupes++;
          duplicateList.add(p.fileName);
        }
      }
      
      if (mounted) {
        setState(() {
          _duplicateCount = dupes;
          _newCount = _photos.length - dupes;
          _duplicateNames = duplicateList;
        });
      }
    } catch (e) {
      debugPrint('Erro ao checar duplicadas: $e');
    }
  }

  Future<void> _startImport() async {
    // Validate campaign and line selection
    if (_selectedCampanhaId == null || _selectedLinhaId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecione uma campanha e uma linha obrigatórias antes de importar'), backgroundColor: AppColors.error),
      );
      return;
    }

    int totalToImport = _duplicateRule == DuplicateRule.ignore ? _newCount : _photos.length;
    if (totalToImport == 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Nenhuma foto para importar.')));
      return;
    }

    setState(() {
      _isUploading = true;
      _uploadProgress = 0;
    });

    try {
      if (_duplicateCount > 0 && _duplicateRule == DuplicateRule.overwrite) {
        await SupabaseService.deleteFotosByNames(_selectedCampanhaId!, _selectedLinhaId!, _duplicateNames);
      }

      // Use existing campaign
      Campanha campanha = _campanhas.firstWhere((c) => c.id == _selectedCampanhaId);

      // Process photos and upload to Storage
      final fotos = <Foto>[];
      int associated = 0;
      int processedCount = 0;

      for (int i = 0; i < _photos.length; i++) {
        final p = _photos[i];
        
        bool isDuplicate = _duplicateNames.contains(p.fileName);
        if (isDuplicate && _duplicateRule == DuplicateRule.ignore) {
           continue; // Skip this photo
        }
        
        String uploadFileName = p.fileName;
        if (isDuplicate && _duplicateRule == DuplicateRule.keepBoth) {
           final extIndex = uploadFileName.lastIndexOf('.');
           if (extIndex != -1) {
              uploadFileName = '${uploadFileName.substring(0, extIndex)}_${_uuid.v4().substring(0, 4)}${uploadFileName.substring(extIndex)}';
           } else {
              uploadFileName = '${uploadFileName}_${_uuid.v4().substring(0, 4)}';
           }
        }

        final fotoId = _uuid.v4();

        String statusAssociacao = 'sem_gps';
        String? torreId;
        String? linhaId;
        String? torreCodigo;
        String? linhaNome;
        double? distanciaTorreM;

        if (p.nearestTorre != null && p.distanceM != null) {
          if (p.distanceM! < 500) {
            statusAssociacao = 'associada';
            torreId = p.nearestTorre!.id;
            linhaId = p.nearestTorre!.linhaId;
            torreCodigo = p.nearestTorre!.codigoTorre;
            linhaNome = p.nearestTorre!.linhaNome;
            distanciaTorreM = p.distanceM;
            associated++;
          } else {
            statusAssociacao = 'pendente';
          }
        } else if (p.exif?.hasGps == true) {
          statusAssociacao = 'pendente';
        }

        String finalLinhaNome = _linhas.where((l) => l.id == _selectedLinhaId).first.nome;
        linhaId = _selectedLinhaId;
        linhaNome = finalLinhaNome;

        // Upload photo bytes to Supabase Storage
        final folderName = finalLinhaNome.replaceAll('/', '-');
        String storagePath = '${campanha.nome.replaceAll('/', '-')}/$folderName/$uploadFileName';
        if (p.bytes != null) {
          try {
            storagePath = await SupabaseService.uploadFoto(
              fileName: uploadFileName,
              bytes: p.bytes as Uint8List,
              linhaCode: folderName,
              campanhaNome: campanha.nome,
            );
          } catch (e) {
            debugPrint('Storage upload failed for $uploadFileName: $e');
            throw Exception('Falha ao enviar arquivo para o Storage (Verifique Policy do Bucket): $e');
          }
        }

        fotos.add(Foto(
          id: fotoId,
          campanhaId: campanha.id,
          linhaId: linhaId,
          torreId: torreId,
          nomeArquivo: uploadFileName,
          caminhoStorage: storagePath,
          latitude: p.exif?.latitude,
          longitude: p.exif?.longitude,
          altitude: p.exif?.altitude,
          dataHoraCaptura: p.exif?.dateTime,
          azimute: p.exif?.azimuth,
          distanciaTorreM: distanciaTorreM,
          statusAssociacao: statusAssociacao,
          qualidadeImagem: p.quality,
          statusAvaliacao: 'nao_avaliada',
          torreCodigo: torreCodigo,
          linhaNome: linhaNome,
          campanhaNome: campanha.nome,
          bytesData: p.bytes as Uint8List?,
        ));

        processedCount++;
        setState(() => _uploadProgress = processedCount / totalToImport);
        await Future.delayed(const Duration(milliseconds: 50));
      }

      // Persist in Supabase database
      await SupabaseService.insertFotos(fotos);

      setState(() {
        _isUploading = false;
        _imported = true;
        _photosAssociated = associated;
        _photosImported = fotos.length;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$_photosImported fotos importadas e salvas no Supabase! $_photosAssociated associadas a torres.'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      debugPrint('Supabase import error: $e');
      setState(() => _isUploading = false);
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
    final withGps = _photos.where((p) => p.exif?.hasGps == true).length;
    final withoutGps = _photos.length - withGps;
    final withTorre = _photos.where((p) => p.nearestTorre != null && (p.distanceM ?? 9999) < 500).length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Importar Fotos'),
        leading: isWide ? null : Builder(
          builder: (ctx) => IconButton(
            icon: const Icon(Icons.menu_rounded),
            onPressed: () => Scaffold.of(ctx).openDrawer(),
          ),
        ),
      ),
      body: !_dataLoaded
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Importação de Fotos', style: Theme.of(context).textTheme.headlineMedium),
                  const SizedBox(height: 8),
                  Text(
                    'Selecione as fotos capturadas pelo helicóptero. O sistema lê GPS do EXIF e associa cada foto à torre mais próxima.',
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 24),

                  // Campaign config
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.bgCard,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Campanha', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              flex: 2,
                              child: DropdownButtonFormField<String?>(
                                value: _selectedCampanhaId,
                                decoration: const InputDecoration(labelText: 'Selecione a campanha'),
                                items: [
                                  ..._campanhas.map((c) => DropdownMenuItem<String?>(
                                    value: c.id,
                                    child: Text(c.nome),
                                  )),
                                ],
                                onChanged: (v) {
                                  setState(() => _selectedCampanhaId = v);
                                  _checkDuplicates();
                                },
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: DropdownButtonFormField<String>(
                                value: _selectedLinhaId,
                                decoration: const InputDecoration(labelText: 'Linha (Obrigatório)'),
                                items: [
                                  ..._linhas.map((l) => DropdownMenuItem(value: l.id, child: Text(l.codigo ?? l.nome))),
                                ],
                                onChanged: (v) {
                                  setState(() => _selectedLinhaId = v);
                                  _recalculateAssociations(); // Recalculate on line change!
                                  _checkDuplicates();
                                },
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Upload area
                  InkWell(
                    onTap: _isLoading || _isUploading ? null : _pickPhotos,
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(32),
                      decoration: BoxDecoration(
                        color: AppColors.bgCard,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: _photos.isNotEmpty ? AppColors.success : AppColors.border, width: 2),
                      ),
                      child: Column(
                        children: [
                          Icon(
                            _photos.isNotEmpty ? Icons.photo_library_rounded : Icons.add_photo_alternate_rounded,
                            size: 48,
                            color: _photos.isNotEmpty ? AppColors.success : AppColors.textMuted,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            _photos.isNotEmpty
                                ? '${_photos.length} foto(s) selecionada(s)'
                                : 'Clique para selecionar fotos',
                            style: TextStyle(
                              fontSize: 15,
                              color: _photos.isNotEmpty ? AppColors.textPrimary : AppColors.textSecondary,
                              fontWeight: _photos.isNotEmpty ? FontWeight.w600 : FontWeight.w400,
                            ),
                          ),
                          if (_photos.isEmpty) ...[
                            const SizedBox(height: 8),
                            Text('JPEG, PNG, TIFF — Fotos com GPS serão associadas automaticamente às torres', style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
                          ],
                        ],
                      ),
                    ),
                  ),

                  if (_isLoading) ...[
                    const SizedBox(height: 32),
                    const Center(child: CircularProgressIndicator()),
                    const SizedBox(height: 8),
                    const Center(child: Text('Lendo metadados EXIF e associando torres...')),
                  ],

                  if (_photos.isNotEmpty && !_isLoading) ...[
                    const SizedBox(height: 24),

                    // GPS & Association Report
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.bgCard,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Row(
                        children: [
                          _statItem(Icons.photo, '${_photos.length}', 'Total', AppColors.info),
                          const SizedBox(width: 16),
                          _statItem(Icons.gps_fixed, '$withGps', 'Com GPS', AppColors.success),
                          const SizedBox(width: 16),
                          _statItem(Icons.gps_off, '$withoutGps', 'Sem GPS', AppColors.error),
                          const SizedBox(width: 16),
                          _statItem(MdiIcons.transmissionTower, '$withTorre', 'Torres\nassociadas', AppColors.primary),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Duplication Alert and Controls
                    if (_duplicateCount > 0)
                      Container(
                        margin: const EdgeInsets.only(bottom: 20),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppColors.bgCard,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.warning.withValues(alpha: 0.5)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.warning_amber_rounded, color: AppColors.warning),
                                const SizedBox(width: 8),
                                const Expanded(child: Text(
                                  'Atenção: Existem fotos duplicadas com o mesmo nome nesta campanha.',
                                  style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.warning),
                                )),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: AppColors.success.withValues(alpha: 0.2),
                                    borderRadius: BorderRadius.circular(16)
                                  ),
                                  child: Text('Novas: $_newCount', style: const TextStyle(color: AppColors.success, fontWeight: FontWeight.w600)),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: AppColors.warning.withValues(alpha: 0.2),
                                    borderRadius: BorderRadius.circular(16)
                                  ),
                                  child: Text('Duplicadas: $_duplicateCount', style: const TextStyle(color: AppColors.warning, fontWeight: FontWeight.w600)),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            const Text('Comportamento para as duplicadas:', style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                            const SizedBox(height: 8),
                            SegmentedButton<DuplicateRule>(
                              segments: const [
                                ButtonSegment(value: DuplicateRule.ignore, label: Text('Ignorar')),
                                ButtonSegment(value: DuplicateRule.overwrite, label: Text('Sobrescrever')),
                                ButtonSegment(value: DuplicateRule.keepBoth, label: Text('Manter Ambas')),
                              ],
                              selected: <DuplicateRule>{_duplicateRule},
                              onSelectionChanged: (Set<DuplicateRule> newSelection) {
                                setState(() {
                                  _duplicateRule = newSelection.first;
                                });
                              },
                              style: ButtonStyle(
                                backgroundColor: WidgetStateProperty.resolveWith<Color>(
                                  (Set<WidgetState> states) {
                                    if (states.contains(WidgetState.selected)) {
                                      return AppColors.primary;
                                    }
                                    return Colors.transparent;
                                  },
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                    // Photo list with association results
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.bgCard,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Preview do Lote', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                          const SizedBox(height: 12),
                          SizedBox(
                            height: 400,
                            child: ListView.separated(
                              itemCount: _photos.length,
                              separatorBuilder: (_, _) => const Divider(height: 1),
                              itemBuilder: (context, index) {
                                final photo = _photos[index];
                                final hasAssociation = photo.nearestTorre != null && (photo.distanceM ?? 9999) < 500;
                                return ListTile(
                                  dense: true,
                                  leading: Icon(
                                    hasAssociation ? MdiIcons.transmissionTower : (photo.exif?.hasGps == true ? Icons.gps_fixed : Icons.gps_off),
                                    color: hasAssociation ? AppColors.primary : (photo.exif?.hasGps == true ? AppColors.success : AppColors.error),
                                    size: 18,
                                  ),
                                  title: Text(photo.fileName, style: const TextStyle(fontSize: 13)),
                                  subtitle: Text(
                                    hasAssociation
                                        ? '→ ${photo.nearestTorre!.codigoTorre} (${photo.distanceM!.toStringAsFixed(0)}m)'
                                        : photo.exif?.hasGps == true
                                            ? '${photo.exif!.latitude!.toStringAsFixed(5)}, ${photo.exif!.longitude!.toStringAsFixed(5)} — sem torre próxima'
                                            : 'Sem coordenadas GPS',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: hasAssociation ? AppColors.primary : AppColors.textMuted,
                                      fontWeight: hasAssociation ? FontWeight.w600 : FontWeight.w400,
                                    ),
                                  ),
                                  trailing: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: _qualityColor(photo.quality).withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      QualityScorer.qualityLabel(photo.quality),
                                      style: TextStyle(fontSize: 11, color: _qualityColor(photo.quality), fontWeight: FontWeight.w600),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ),

                    if (!_imported) ...[
                      const SizedBox(height: 24),

                      // Upload progress
                      if (_isUploading) ...[
                        LinearProgressIndicator(value: _uploadProgress, minHeight: 6),
                        const SizedBox(height: 8),
                        Text(
                          'Importando ${(_uploadProgress * (_duplicateRule == DuplicateRule.ignore ? _newCount : _photos.length)).ceil()} de ${_duplicateRule == DuplicateRule.ignore ? _newCount : _photos.length}...',
                          style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                        ),
                        const SizedBox(height: 16),
                      ],

                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          icon: Icon(_isUploading ? Icons.hourglass_top : Icons.cloud_upload_rounded),
                          label: Text(_isUploading ? 'Importando...' : 'Importar ${_duplicateRule == DuplicateRule.ignore ? _newCount : _photos.length} Fotos'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.success,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                          onPressed: _isUploading ? null : _startImport,
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
                                const Icon(Icons.check_circle, color: AppColors.success),
                                const SizedBox(width: 12),
                                Text(
                                  '$_photosImported fotos importadas com sucesso!',
                                  style: const TextStyle(color: AppColors.success, fontWeight: FontWeight.w600, fontSize: 15),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '• $_photosAssociated fotos associadas a torres automaticamente\n'
                              '• ${_photosImported - _photosAssociated} fotos pendentes de associação',
                              style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
                            ),
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

  Widget _statItem(IconData icon, String value, String label, Color color) {
    return Expanded(
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color)),
              Text(label, style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
            ],
          ),
        ],
      ),
    );
  }

  Color _qualityColor(double q) {
    if (q >= 0.7) return AppColors.success;
    if (q >= 0.4) return AppColors.warning;
    return AppColors.error;
  }
}

class _PhotoPreview {
  final String fileName;
  final int sizeBytes;
  final dynamic bytes;
  final ExifData? exif;
  final double quality;
  Torre? nearestTorre;
  double? distanceM;

  _PhotoPreview({
    required this.fileName,
    required this.sizeBytes,
    this.bytes,
    this.exif,
    this.quality = 0,
    this.nearestTorre,
    this.distanceM,
  });
}
