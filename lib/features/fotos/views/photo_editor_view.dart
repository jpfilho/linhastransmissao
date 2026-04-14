import 'package:flutter/material.dart';
import 'package:pro_image_editor/pro_image_editor.dart';
import '../../../shared/services/supabase_service.dart';
import '../../../core/theme/app_colors.dart';
import 'dart:typed_data';

class PhotoEditorView extends StatefulWidget {
  final String fotoId;
  final String imageUrl;
  final String originalStoragePath;
  final String? editedStoragePath;

  const PhotoEditorView({
    super.key,
    required this.fotoId,
    required this.imageUrl,
    required this.originalStoragePath,
    this.editedStoragePath,
  });

  @override
  State<PhotoEditorView> createState() => _PhotoEditorViewState();
}

class _PhotoEditorViewState extends State<PhotoEditorView> {
  final GlobalKey<ProImageEditorState> _editorKey = GlobalKey<ProImageEditorState>();
  bool _isSaving = false;
  bool _isLoadingState = true;
  ImportStateHistory? _initStateHistory;

  @override
  void initState() {
    super.initState();
    _loadStateHistory();
  }

  Future<void> _loadStateHistory() async {
    if (widget.editedStoragePath != null) {
      final jsonStr = await SupabaseService.getEditedPhotoStateHistory(widget.editedStoragePath!);
      if (jsonStr != null && jsonStr.isNotEmpty) {
        try {
          _initStateHistory = ImportStateHistory.fromJson(jsonStr);
        } catch (e) {
          debugPrint('Failed to parse history: $e');
        }
      }
    }
    if (mounted) setState(() => _isLoadingState = false);
  }

  Future<void> _handleSave(Uint8List bytes, {String? stateJson}) async {
    setState(() => _isSaving = true);
    try {
      await SupabaseService.saveEditedPhoto(
        widget.fotoId, 
        widget.originalStoragePath, 
        bytes,
        stateJson: stateJson,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Edição salva com sucesso!', style: TextStyle(color: Colors.white)), backgroundColor: AppColors.success)
        );
        Navigator.of(context).pop(true); // Return true to indicate change
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao salvar: $e', style: const TextStyle(color: Colors.white)), backgroundColor: AppColors.error)
        );
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoadingState) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: AppColors.primary),
              SizedBox(height: 16),
              Text('Carregando Projeto de Edição...', style: TextStyle(color: Colors.white)),
            ],
          ),
        ),
      );
    }
  
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          ProImageEditor.network(
            widget.imageUrl,
            key: _editorKey,
            callbacks: ProImageEditorCallbacks(
              onImageEditingComplete: (Uint8List bytes) async {
                String? jsonStr;
                try {
                  final stateHistory = await _editorKey.currentState?.exportStateHistory(
                    configs: const ExportEditorConfigs(),
                  );
                  if (stateHistory != null) {
                    jsonStr = await stateHistory.toJson();
                  }
                } catch (e) {
                  debugPrint('Failed to export state: $e');
                }
                await _handleSave(bytes, stateJson: jsonStr);
              },
            ),
            configs: ProImageEditorConfigs(
              stateHistory: StateHistoryConfigs(
                initStateHistory: _initStateHistory,
              ),
              designMode: ImageEditorDesignMode.material,
              mainEditor: MainEditorConfigs(
                enableZoom: true,
                editorMaxScale: 8.0,
              ),
              paintEditor: PaintEditorConfigs(
                enableZoom: true,
                editorMaxScale: 8.0,
              ),
              textEditor: TextEditorConfigs(
                showSelectFontStyleBottomBar: true,
                showFontScaleButton: true,
              ),
              layerInteraction: LayerInteractionConfigs(
                selectable: LayerInteractionSelectable.enabled,
              ),
            ),
          ),
          if (_isSaving)
            Container(
              color: Colors.black54,
              child: const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: AppColors.primary),
                    SizedBox(height: 16),
                    Text('Salvando edição na nuvem...', style: TextStyle(color: Colors.white, fontSize: 16)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
