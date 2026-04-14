import 'package:flutter/material.dart';

import 'package:material_design_icons_flutter/material_design_icons_flutter.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/models/chat_model.dart';
import '../../../shared/services/supabase_service.dart';
import 'package:file_picker/file_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

class TorreChatWidget extends StatefulWidget {
  final String torreId;

  const TorreChatWidget({super.key, required this.torreId});

  @override
  State<TorreChatWidget> createState() => _TorreChatWidgetState();
}

class _TorreChatWidgetState extends State<TorreChatWidget> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _isSending = false;

  void _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    setState(() => _isSending = true);
    try {
      await SupabaseService.enviarMensagemChat(
        torreId: widget.torreId, 
        usuarioId: 1, 
        texto: text,
      );
      _messageController.clear();
      // Scroll to bottom
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          0.0,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao enviar: \$e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSending = false);
      }
    }
  }

  void _showAttachmentMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.bgSurface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.image, color: AppColors.primaryLight),
                title: const Text('Foto / Arquivo', style: TextStyle(color: AppColors.textPrimary)),
                onTap: () {
                  Navigator.pop(context);
                  _pickAndUploadFile();
                },
              ),
              ListTile(
                leading: const Icon(Icons.location_on, color: AppColors.error),
                title: const Text('Localização (Demo)', style: TextStyle(color: AppColors.textPrimary)),
                onTap: () {
                  Navigator.pop(context);
                  _sendLocationDemo();
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _pickAndUploadFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(type: FileType.media, withData: true);
      if (result != null && result.files.isNotEmpty) {
        final file = result.files.first;
        if (file.bytes == null) return;
        
        if (file.size > 50 * 1024 * 1024) {
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Arquivo muito grande! O limite é de 50MB.'), backgroundColor: AppColors.error));
          return;
        }

        setState(() => _isSending = true);
        
        // Determine type loosely
        String tipoAnexo = 'file';
        final extension = file.extension?.toLowerCase() ?? '';
        if (['jpg', 'jpeg', 'png', 'gif', 'webp'].contains(extension)) {
          tipoAnexo = 'image';
        } else if (['mp4', 'mov', 'webm'].contains(extension)) {
          tipoAnexo = 'video';
        } else if (['mp3', 'wav', 'ogg'].contains(extension)) {
          tipoAnexo = 'audio';
        }

        String mimeType = 'application/octet-stream';
        if (tipoAnexo == 'video') mimeType = 'video/$extension';
        else if (tipoAnexo == 'image') mimeType = 'image/$extension';
        else if (tipoAnexo == 'audio') mimeType = 'audio/$extension';

        final publicUrl = await SupabaseService.uploadAnexoChat(
          torreId: widget.torreId,
          fileName: file.name,
          fileBytes: file.bytes!,
          mimeType: mimeType,
        );

        await SupabaseService.enviarMensagemChat(
          torreId: widget.torreId,
          usuarioId: 1,
          texto: 'Anexo compartilhado',
          tipoAnexo: tipoAnexo,
          urlAnexo: publicUrl,
          metadata: {'file_name': file.name, 'size': file.size},
        );
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro anexo: $e'), backgroundColor: AppColors.error));
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  Future<void> _sendLocationDemo() async {
    setState(() => _isSending = true);
    try {
      await SupabaseService.enviarMensagemChat(
        torreId: widget.torreId,
        usuarioId: 1,
        texto: 'Lat: -23.5505, Lon: -46.6333',
        tipoAnexo: 'location',
        geoLat: -23.5505,
        geoLon: -46.6333,
      );
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro anexo: $e'), backgroundColor: AppColors.error));
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  Future<void> _confirmarDelecao(ChatMensagem msg) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.bgDark,
        title: const Text('Excluir Mensagem?', style: TextStyle(color: Colors.white)),
        content: const Text('Essa ação não pode ser desfeita.', style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar', style: TextStyle(color: Colors.white))),
          TextButton(
            onPressed: () => Navigator.pop(context, true), 
            child: const Text('Excluir', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await SupabaseService.deleteMensagemChat(msg.id);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Mensagem excluída.'), backgroundColor: AppColors.primary));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro ao excluir: $e'), backgroundColor: AppColors.error));
    }
  }

  // Build attachment preview inside bubble
  Widget _buildAttachmentPreview(ChatMensagem msg, bool isAdmin) {
    if (msg.tipoAnexo == null) return const SizedBox.shrink();

    Widget preview;
    if (msg.tipoAnexo == 'image' && msg.urlAnexo != null) {
      preview = ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: CachedNetworkImage(
          imageUrl: msg.urlAnexo!,
          width: 200,
          fit: BoxFit.cover,
          placeholder: (context, url) => const SizedBox(height: 100, width: 200, child: Center(child: CircularProgressIndicator())),
          errorWidget: (context, url, error) => const Icon(Icons.error, color: AppColors.error),
        ),
      );
    } else if (msg.tipoAnexo == 'location') {
      preview = Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(color: Colors.black12, borderRadius: BorderRadius.circular(8)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.map, color: AppColors.primaryLight, size: 24),
            const SizedBox(width: 8),
            const Text('Localização', style: TextStyle(color: AppColors.primaryLight, fontWeight: FontWeight.bold)),
          ],
        ),
      );
    } else if (msg.tipoAnexo == 'video' && msg.urlAnexo != null) {
      preview = _VideoChatBubble(url: msg.urlAnexo!);
    } else {
      // Audio, or fallback file link
      preview = InkWell(
        onTap: () {
          if (msg.urlAnexo != null) launchUrl(Uri.parse(msg.urlAnexo!));
        },
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: isAdmin ? Colors.white.withValues(alpha: 0.2) : Colors.black12,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: isAdmin ? Colors.white30 : Colors.black26),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(msg.tipoAnexo == 'audio' ? Icons.audiotrack : Icons.insert_drive_file, size: 32, color: isAdmin ? Colors.white : AppColors.accent),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(msg.tipoAnexo?.toUpperCase() ?? 'ARQUIVO', style: TextStyle(color: isAdmin ? Colors.white : AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 12)),
                  Text(msg.metadata?['file_name'] ?? 'Abrir Mídia', style: TextStyle(color: isAdmin ? Colors.white70 : AppColors.textMuted, fontSize: 10), overflow: TextOverflow.ellipsis),
                ],
              ),
            ],
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 6.0),
      child: preview,
    );
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.bgSurface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: AppColors.border)),
            ),
            child: Row(
              children: [
                Icon(MdiIcons.chatProcessingOutline, size: 18, color: AppColors.accent),
                const SizedBox(width: 8),
                const Text(
                  'DISCUSSÃO DA TORRE',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textMuted,
                    letterSpacing: 1.2,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.bgElevated,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text('Admin', style: TextStyle(fontSize: 10, color: AppColors.textSecondary)),
                ),
              ],
            ),
          ),
          
          // Messages List
          Expanded(
            child: StreamBuilder<List<ChatMensagem>>(
              stream: SupabaseService.streamChatPorTorre(widget.torreId),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(
                    child: Text('Erro ao carregar chat: \${snapshot.error}', style: TextStyle(color: AppColors.error, fontSize: 12)),
                  );
                }

                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator(strokeWidth: 2));
                }

                final messages = snapshot.data!;
                if (messages.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(MdiIcons.messageOffOutline, size: 32, color: AppColors.border),
                        const SizedBox(height: 8),
                        const Text('Nenhuma mensagem gerada.', style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  controller: _scrollController,
                  reverse: true, // Show latest at bottom
                  padding: const EdgeInsets.all(12),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final msg = messages[messages.length - 1 - index];
                    final isAdmin = msg.usuarioId == 1; // Assuming 1 is our mock user

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12.0),
                      child: Row(
                        mainAxisAlignment: isAdmin ? MainAxisAlignment.end : MainAxisAlignment.start,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          if (!isAdmin) ...[
                            CircleAvatar(
                              radius: 12,
                              backgroundColor: AppColors.bgElevated,
                              child: Text(msg.usuario?.nome.substring(0, 1).toUpperCase() ?? 'U', style: TextStyle(fontSize: 10)),
                            ),
                            const SizedBox(width: 8),
                          ],
                          Flexible(
                            child: GestureDetector(
                              onLongPress: () => _confirmarDelecao(msg),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              decoration: BoxDecoration(
                                color: isAdmin ? AppColors.accent.withValues(alpha: 0.15) : AppColors.bgElevated,
                                borderRadius: BorderRadius.only(
                                  topLeft: const Radius.circular(12),
                                  topRight: const Radius.circular(12),
                                  bottomLeft: Radius.circular(isAdmin ? 12 : 0),
                                  bottomRight: Radius.circular(isAdmin ? 0 : 12),
                                ),
                                border: isAdmin ? Border.all(color: AppColors.accent.withValues(alpha: 0.3)) : null,
                              ),
                              child: Column(
                                crossAxisAlignment: isAdmin ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                                children: [
                                  if (!isAdmin)
                                    Text(
                                      msg.usuario?.nome ?? 'Usuário',
                                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.textSecondary),
                                    ),
                                  const SizedBox(height: 2),
                                  const SizedBox(height: 2),
                                  _buildAttachmentPreview(msg, isAdmin),
                                  if (msg.mensagem.isNotEmpty && msg.mensagem != 'Anexo compartilhado')
                                    Text(
                                      msg.mensagem,
                                      style: TextStyle(fontSize: 13, color: AppColors.textPrimary, height: 1.3),
                                    ),
                                ],
                              ),
                            ),
                            ),
                          ),
                          if (isAdmin) ...[
                            const SizedBox(width: 8),
                            CircleAvatar(
                              radius: 12,
                              backgroundColor: AppColors.accent.withValues(alpha: 0.2),
                              child: const Text('A', style: TextStyle(fontSize: 10, color: AppColors.accent)),
                            ),
                          ],
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),

          // Input Area
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: AppColors.border)),
              color: AppColors.bgDark,
            ),
            child: Row(
              children: [
                Material(
                  color: Colors.transparent,
                  shape: const CircleBorder(),
                  child: InkWell(
                    onTap: _showAttachmentMenu,
                    customBorder: const CircleBorder(),
                    child: const Padding(
                      padding: EdgeInsets.all(8.0),
                      child: Icon(Icons.add_circle_outline, size: 24, color: AppColors.textMuted),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    style: TextStyle(fontSize: 13),
                    maxLines: 3,
                    minLines: 1,
                    onSubmitted: (_) => _sendMessage(),
                    decoration: InputDecoration(
                      hintText: 'Escreva uma observação...',
                      hintStyle: TextStyle(color: AppColors.textMuted, fontSize: 13),
                      filled: true,
                      fillColor: AppColors.bgDark,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Material(
                  color: AppColors.accent,
                  shape: const CircleBorder(),
                  child: InkWell(
                    onTap: _isSending ? null : _sendMessage,
                    customBorder: const CircleBorder(),
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: _isSending
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.send, size: 18, color: Colors.white),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _VideoChatBubble extends StatefulWidget {
  final String url;
  const _VideoChatBubble({Key? key, required this.url}) : super(key: key);

  @override
  State<_VideoChatBubble> createState() => _VideoChatBubbleState();
}

class _VideoChatBubbleState extends State<_VideoChatBubble> {
  late final Player player;
  late final VideoController controller;
  bool _isDisposed = false;

  @override
  void initState() {
    super.initState();
    player = Player();
    controller = VideoController(player);
    
    // Configuração imbatível: limpa espaços no nome do vídeo
    final safeUrl = widget.url.replaceAll(' ', '%20');
    
    // Toca automaticamente quando carregado e lida com som nativamente
    player.open(Media(safeUrl), play: true);
  }

  @override
  void dispose() {
    _isDisposed = true;
    player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 280, // Aspect ratio costuma se alinhar dinamicamente no media_kit
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 250),
          child: Video(
            controller: controller,
            // O media_kit tem controles maravilhosos built-in!
            controls: AdaptiveVideoControls,
            fill: Colors.transparent,
          ),
        ),
      ),
    );
  }
}

