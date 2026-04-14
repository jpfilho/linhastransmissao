import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';

class RocoSegment {
  String tipo; // 'manual', 'mecanizado', 'seletivo', 'nao_rocar'
  String status; // 'nao_iniciado', 'iniciado', 'concluido', 'com_pendencias', 'fiscalizado'
  int startKm; // Using meters as integer for start
  int endKm; // Using meters as integer for end

  RocoSegment({
    required this.tipo,
    this.status = 'nao_iniciado',
    required this.startKm,
    required this.endKm,
  });

  Map<String, dynamic> toJson() => {
        'tipo': tipo,
        'status': status,
        'inicio': startKm,
        'fim': endKm,
      };

  factory RocoSegment.fromJson(Map<String, dynamic> json) {
    return RocoSegment(
      tipo: json['tipo'] ?? 'nao_rocar',
      status: json['status'] ?? 'nao_iniciado',
      startKm: (json['inicio'] as num).toInt(),
      endKm: (json['fim'] as num).toInt(),
    );
  }
}

class InteractiveSpanBar extends StatefulWidget {
  final double totalLengthMeters;
  final List<RocoSegment> initialSegments;
  final ValueChanged<List<RocoSegment>> onChanged;

  const InteractiveSpanBar({
    super.key,
    required this.totalLengthMeters,
    required this.initialSegments,
    required this.onChanged,
  });

  @override
  State<InteractiveSpanBar> createState() => _InteractiveSpanBarState();
}

class _InteractiveSpanBarState extends State<InteractiveSpanBar> {
  late List<RocoSegment> _segments;
  late int _maxMeters;

  // Interaction state
  int? _draggingSegmentIndex;
  bool _isDraggingStart = false; // true = dragging start handle, false = dragging end handle
  bool _isDraggingBody = false;
  int _dragInitialBoundary = 0;
  int _dragInitialEndBoundary = 0;
  double _dragStartPx = 0.0;
  String? _hoveredHandle;

  @override
  void initState() {
    super.initState();
    _maxMeters = widget.totalLengthMeters.round();
    _segments = List.from(widget.initialSegments)
      ..sort((a, b) => a.startKm.compareTo(b.startKm));
  }

  @override
  void didUpdateWidget(InteractiveSpanBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialSegments != widget.initialSegments) {
      _segments = List.from(widget.initialSegments)
        ..sort((a, b) => a.startKm.compareTo(b.startKm));
    }
    if (oldWidget.totalLengthMeters != widget.totalLengthMeters) {
      _maxMeters = widget.totalLengthMeters.round();
    }
  }

  Color _getColorForType(String tipo) {
    switch (tipo) {
      case 'manual':
        return const Color(0xFFE67E22);
      case 'mecanizado':
        return const Color(0xFF8E44AD);
      case 'seletivo':
        return const Color(0xFF27AE60);
      case 'cultivado':
        return Colors.lightGreen;
      case 'nao_rocar':
      default:
        return Colors.transparent;
    }
  }

  void _addSegmentAt(int meters) {
    // Find gaps
    int start = 0;
    int end = _maxMeters;

    for (int i = 0; i < _segments.length; i++) {
      if (_segments[i].startKm <= meters && _segments[i].endKm >= meters) {
        // Tapped inside an existing segment, do nothing here.
        return;
      }
    }

    // Determine boundaries for new segment based on surrounding segments
    for (int i = 0; i < _segments.length; i++) {
      if (_segments[i].endKm <= meters && _segments[i].endKm > start) start = _segments[i].endKm;
      if (_segments[i].startKm > meters && _segments[i].startKm < end) end = _segments[i].startKm;
    }

    setState(() {
      _segments.add(RocoSegment(tipo: 'mecanizado', startKm: start, endKm: end));
      _segments.sort((a, b) => a.startKm.compareTo(b.startKm));
    });
    _notifyChanges();
  }

  void _showSegmentOptions(BuildContext context, int index) {
    final RenderBox overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    showMenu(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(MediaQuery.of(context).size.width / 2, MediaQuery.of(context).size.height / 2, 0, 0),
        Offset.zero & overlay.size,
      ),
      items: <PopupMenuEntry<String>>[
        const PopupMenuItem<String>(value: 'mecanizado', child: Text('Mecanizado', style: TextStyle(color: Color(0xFF8E44AD)))),
        const PopupMenuItem<String>(value: 'manual', child: Text('Manual', style: TextStyle(color: Color(0xFFE67E22)))),
        const PopupMenuItem<String>(value: 'seletivo', child: Text('Seletivo', style: TextStyle(color: Color(0xFF27AE60)))),
        const PopupMenuItem<String>(value: 'cultivado', child: Text('Cultivado (Sem Roço)', style: TextStyle(color: Colors.lightGreen))),
        const PopupMenuDivider(),
        const PopupMenuItem<String>(value: 'dividir', child: Text('Dividir ao Meio')),
        const PopupMenuItem<String>(value: 'excluir', child: Text('Excluir', style: TextStyle(color: Colors.red))),
      ],
    ).then((value) {
      if (value != null) {
        if (value == 'excluir') {
          setState(() {
            _segments.removeAt(index);
          });
          _notifyChanges();
        } else if (value == 'dividir') {
          _handleDivision(index);
        } else {
          setState(() {
            _segments[index].tipo = value;
          });
          _notifyChanges();
        }
      }
    });
  }

   void _handleDivision(int index) {
    setState(() {
      final seg = _segments[index];
      if (seg.endKm - seg.startKm < 2) return; // Too small to divide
      final originalEnd = seg.endKm;
      final mid = seg.startKm + ((seg.endKm - seg.startKm) ~/ 2);
      seg.endKm = mid;
      _segments.insert(index + 1, RocoSegment(tipo: seg.tipo, startKm: mid, endKm: originalEnd));
      _segments.sort((a, b) => a.startKm.compareTo(b.startKm));
    });
    _notifyChanges();
  }

  void _notifyChanges() {
    widget.onChanged(_segments);
  }

  @override
  Widget build(BuildContext context) {
    if (_maxMeters <= 0) {
      return const Text('Vão inválido para roço.', style: TextStyle(color: AppColors.textMuted));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // The interactive bar
        Container(
          height: 85,
          width: double.infinity,
          decoration: BoxDecoration(
            color: AppColors.bgSurface,
            border: Border.all(color: AppColors.border),
            borderRadius: BorderRadius.circular(8),
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final pxPerMeter = constraints.maxWidth / _maxMeters;

              return GestureDetector(
                onTapUp: (details) {
                  final tappedMeters = (details.localPosition.dx / pxPerMeter).round();
                  _addSegmentAt(tappedMeters);
                },
                child: Stack(
                  children: [
                    // Base background with tick marks
                    CustomPaint(
                      size: Size(constraints.maxWidth, 85),
                      painter: _TicksPainter(_maxMeters, pxPerMeter),
                    ),
                    
                    // Segments
                    ..._segments.asMap().entries.map((entry) {
                      final idx = entry.key;
                      final seg = entry.value;
                      final leftPx = seg.startKm * pxPerMeter;
                      final widthPx = (seg.endKm - seg.startKm) * pxPerMeter;

                      bool isHoveredOrDragged = (_draggingSegmentIndex == idx) || (_hoveredHandle == 'left_$idx') || (_hoveredHandle == 'right_$idx') || (_hoveredHandle == 'body_$idx');

                      return Positioned(
                        left: leftPx,
                        width: widthPx,
                        top: 4,
                        bottom: 25,
                        child: MouseRegion(
                          cursor: (_draggingSegmentIndex == idx && _isDraggingBody) ? SystemMouseCursors.grabbing : SystemMouseCursors.grab,
                          onEnter: (_) => setState(() => _hoveredHandle = 'body_$idx'),
                          onExit: (_) => setState(() => _hoveredHandle = null),
                          child: GestureDetector(
                            onPanStart: (details) => setState(() {
                              _draggingSegmentIndex = idx;
                              _isDraggingBody = true;
                              _dragInitialBoundary = seg.startKm;
                              _dragInitialEndBoundary = seg.endKm;
                              _dragStartPx = details.globalPosition.dx;
                            }),
                            onPanUpdate: (details) {
                              final diffPx = details.globalPosition.dx - _dragStartPx;
                              final diffMeters = (diffPx / pxPerMeter).round();
                              if (diffMeters == 0) return;
                              
                              setState(() {
                                int minBoundary = idx > 0 ? _segments[idx - 1].endKm : 0;
                                int maxBoundary = idx < _segments.length - 1 ? _segments[idx + 1].startKm : _maxMeters;
                                int length = _dragInitialEndBoundary - _dragInitialBoundary;

                                int newStart = _dragInitialBoundary + diffMeters;
                                int newEnd = _dragInitialEndBoundary + diffMeters;

                                if (newStart < minBoundary) {
                                  newStart = minBoundary;
                                  newEnd = newStart + length;
                                }
                                if (newEnd > maxBoundary) {
                                  newEnd = maxBoundary;
                                  newStart = newEnd - length;
                                }
                                
                                seg.startKm = newStart;
                                seg.endKm = newEnd;
                              });
                            },
                            onPanEnd: (_) {
                              setState(() {
                                _draggingSegmentIndex = null;
                                _isDraggingBody = false;
                              });
                              _notifyChanges();
                            },
                            onTap: () {
                              _showEditModal(idx);
                            },
                            child: Container(
                            decoration: BoxDecoration(
                              color: _getColorForType(seg.tipo).withValues(alpha: isHoveredOrDragged ? 1.0 : 0.8),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: isHoveredOrDragged ? Colors.white : _getColorForType(seg.tipo), 
                                width: isHoveredOrDragged ? 3 : 2
                              ),
                              boxShadow: isHoveredOrDragged ? [const BoxShadow(color: Colors.white54, blurRadius: 6, spreadRadius: 1)] : null,
                            ),
                            child: Stack(
                              clipBehavior: Clip.none,
                              children: [
                                Center(
                                  child: Text(
                                    '${seg.tipo.toUpperCase().substring(0, 3)} ${_getStatusEmoji(seg.status)}', // MEC 🟢
                                    style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                                  ),
                                ),
                                if (_draggingSegmentIndex == idx && (_isDraggingStart || _isDraggingBody)) ...[
                                  Positioned(
                                    left: -8,
                                    top: -25,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius: BorderRadius.circular(6),
                                        boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 4)],
                                      ),
                                      child: Text('${seg.startKm}m', style: const TextStyle(color: Colors.black, fontSize: 11, fontWeight: FontWeight.w900)),
                                    ),
                                  ),
                                  Positioned(
                                    left: -8,
                                    bottom: -25,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: Colors.black87,
                                        borderRadius: BorderRadius.circular(6),
                                        boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 4)],
                                      ),
                                      child: Text('${seg.startKm - _maxMeters}m', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w900)),
                                    ),
                                  ),
                                ],
                                if (_draggingSegmentIndex == idx && (!_isDraggingStart || _isDraggingBody)) ...[
                                  Positioned(
                                    right: -8,
                                    top: -25,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius: BorderRadius.circular(6),
                                        boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 4)],
                                      ),
                                      child: Text('${seg.endKm}m', style: const TextStyle(color: Colors.black, fontSize: 11, fontWeight: FontWeight.w900)),
                                    ),
                                  ),
                                  Positioned(
                                    right: -8,
                                    bottom: -25,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: Colors.black87,
                                        borderRadius: BorderRadius.circular(6),
                                        boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 4)],
                                      ),
                                      child: Text('${seg.endKm - _maxMeters}m', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w900)),
                                    ),
                                  ),
                                ],
                                // Left drag handle
                                Positioned(
                                  left: 0,
                                  top: 0,
                                  bottom: 0,
                                  width: 20,
                                  child: MouseRegion(
                                    cursor: SystemMouseCursors.resizeLeftRight,
                                    onEnter: (_) => setState(() => _hoveredHandle = 'left_$idx'),
                                    onExit: (_) => setState(() => _hoveredHandle = null),
                                    child: GestureDetector(
                                      behavior: HitTestBehavior.opaque,
                                    onPanStart: (details) => setState(() {
                                      _draggingSegmentIndex = idx;
                                      _isDraggingStart = true;
                                      _dragInitialBoundary = seg.startKm;
                                      _dragStartPx = details.globalPosition.dx;
                                    }),
                                    onPanUpdate: (details) {
                                      final diffPx = details.globalPosition.dx - _dragStartPx;
                                      final diffMeters = (diffPx / pxPerMeter).round();
                                      if (diffMeters == 0) return;
                                      
                                      setState(() {
                                        int minBoundary = idx > 0 ? _segments[idx - 1].endKm : 0;

                                        int newStart = _dragInitialBoundary + diffMeters;
                                        if (newStart < minBoundary) newStart = minBoundary;
                                        if (newStart >= seg.endKm - 1) newStart = seg.endKm - 1;
                                        
                                        seg.startKm = newStart;
                                      });
                                    },
                                    onPanEnd: (_) {
                                      setState(() => _draggingSegmentIndex = null);
                                      _notifyChanges();
                                    },
                                    child: Center(child: Icon(Icons.drag_indicator, size: 14, color: _hoveredHandle == 'left_$idx' ? Colors.white : Colors.white54)),
                                    ),
                                  ),
                                ),
                                // Right drag handle
                                Positioned(
                                  right: 0,
                                  top: 0,
                                  bottom: 0,
                                  width: 20,
                                  child: MouseRegion(
                                    cursor: SystemMouseCursors.resizeLeftRight,
                                    onEnter: (_) => setState(() => _hoveredHandle = 'right_$idx'),
                                    onExit: (_) => setState(() => _hoveredHandle = null),
                                    child: GestureDetector(
                                      behavior: HitTestBehavior.opaque,
                                    onPanStart: (details) => setState(() {
                                      _draggingSegmentIndex = idx;
                                      _isDraggingStart = false;
                                      _dragInitialBoundary = seg.endKm;
                                      _dragStartPx = details.globalPosition.dx;
                                    }),
                                    onPanUpdate: (details) {
                                      final diffPx = details.globalPosition.dx - _dragStartPx;
                                      final diffMeters = (diffPx / pxPerMeter).round();
                                      if (diffMeters == 0) return;
                                      
                                      setState(() {
                                        int maxBoundary = idx < _segments.length - 1 ? _segments[idx + 1].startKm : _maxMeters;

                                        int newEnd = _dragInitialBoundary + diffMeters;
                                        if (newEnd > maxBoundary) newEnd = maxBoundary;
                                        if (newEnd <= seg.startKm + 1) newEnd = seg.startKm + 1;
                                        
                                        seg.endKm = newEnd;
                                      });
                                    },
                                    onPanEnd: (_) {
                                      setState(() => _draggingSegmentIndex = null);
                                      _notifyChanges();
                                    },
                                    child: Center(child: Icon(Icons.drag_indicator, size: 14, color: _hoveredHandle == 'right_$idx' ? Colors.white : Colors.white54)),
                                    ),
                                  ),
                                ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    }),
                  ],
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 8),
        // Active list overview
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _segments.map((seg) {
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: _getColorForType(seg.tipo).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: _getColorForType(seg.tipo).withValues(alpha: 0.5)),
              ),
              child: Text(
                '${seg.startKm}m a ${seg.endKm}m',
                style: TextStyle(fontSize: 10, color: _getColorForType(seg.tipo), fontWeight: FontWeight.bold),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  String _getStatusEmoji(String status) {
    switch (status) {
      case 'iniciado': return '🔵';
      case 'concluido': return '🟢';
      case 'com_pendencias': return '🟠';
      case 'fiscalizado': return '⭐';
      case 'nao_iniciado':
      default: return '⚪';
    }
  }

  void _showEditModal(int idx) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.bgElevated,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final seg = _segments[idx];
            return Padding(
              padding: EdgeInsets.only(
                left: 24.0, 
                right: 24.0, 
                top: 24.0, 
                bottom: MediaQuery.of(context).viewInsets.bottom + 24.0
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Editar Segmento', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                  const SizedBox(height: 24),
                  
                  const Text('Tipo de Serviço', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      ChoiceChip(
                        label: const Text('Mecanizado'),
                        selected: seg.tipo == 'mecanizado',
                        selectedColor: const Color(0xFF8E44AD).withValues(alpha: 0.3),
                        onSelected: (val) {
                          if (val) {
                             setState(() => seg.tipo = 'mecanizado');
                             setModalState(() {});
                             _notifyChanges();
                          }
                        },
                      ),
                      ChoiceChip(
                        label: const Text('Manual'),
                        selected: seg.tipo == 'manual',
                        selectedColor: const Color(0xFFE67E22).withValues(alpha: 0.3),
                        onSelected: (val) {
                          if (val) {
                             setState(() => seg.tipo = 'manual');
                             setModalState(() {});
                             _notifyChanges();
                          }
                        },
                      ),
                      ChoiceChip(
                        label: const Text('Seletivo'),
                        selected: seg.tipo == 'seletivo',
                        selectedColor: const Color(0xFF27AE60).withValues(alpha: 0.3),
                        onSelected: (val) {
                          if (val) {
                             setState(() => seg.tipo = 'seletivo');
                             setModalState(() {});
                             _notifyChanges();
                          }
                        },
                      ),
                      ChoiceChip(
                        label: const Text('Cultivado'),
                        selected: seg.tipo == 'cultivado',
                        selectedColor: Colors.lightGreen.withValues(alpha: 0.3),
                        onSelected: (val) {
                          if (val) {
                             setState(() {
                               seg.tipo = 'cultivado';
                               seg.status = 'nao_aplicavel'; // Force no status
                             });
                             setModalState(() {});
                             _notifyChanges();
                          }
                        },
                      ),
                    ],
                  ),
                  
                  if (seg.tipo != 'cultivado') ...[
                    const SizedBox(height: 24),
                    const Text('Status da Empreitada', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _buildStatusChip(seg, setModalState, 'nao_iniciado', '⚪ Não Iniciado'),
                        _buildStatusChip(seg, setModalState, 'iniciado', '🔵 Iniciado'),
                        _buildStatusChip(seg, setModalState, 'concluido', '🟢 Concluído'),
                        _buildStatusChip(seg, setModalState, 'com_pendencias', '🟠 Pendência'),
                        _buildStatusChip(seg, setModalState, 'fiscalizado', '⭐ Fiscalizado'),
                      ],
                    ),
                  ],

                  const SizedBox(height: 32),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      TextButton.icon(
                        icon: const Icon(Icons.call_split),
                        label: const Text('Dividir ao Meio'),
                        onPressed: () {
                          Navigator.pop(context);
                          _handleDivision(idx);
                          _notifyChanges();
                        },
                      ),
                      TextButton.icon(
                        icon: const Icon(Icons.delete, color: AppColors.error),
                        label: const Text('Excluir', style: TextStyle(color: AppColors.error)),
                        onPressed: () {
                          Navigator.pop(context);
                          setState(() => _segments.removeAt(idx));
                          _notifyChanges();
                        },
                      ),
                    ],
                  ),
                ],
              ),
            );
          }
        );
      }
    );
  }

  Widget _buildStatusChip(RocoSegment seg, StateSetter setModalState, String value, String label) {
    return ChoiceChip(
      label: Text(label),
      selected: seg.status == value,
      onSelected: (selected) {
        if (selected) {
          setState(() => seg.status = value);
          setModalState(() {});
          _notifyChanges();
        }
      },
    );
  }
}

class _TicksPainter extends CustomPainter {
  final int maxMeters;
  final double pxPerMeter;

  _TicksPainter(this.maxMeters, this.pxPerMeter);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = AppColors.border..strokeWidth = 1;
    final textPainter = TextPainter(textDirection: TextDirection.ltr);

    int textStep = 50;
    if (maxMeters <= 50) textStep = 10;
    else if (maxMeters <= 100) textStep = 20;
    else if (maxMeters <= 200) textStep = 50;
    else textStep = 100;

    for (int i = 0; i <= maxMeters; i += 10) {
      final x = i * pxPerMeter;
      
      bool is50 = (i % 50 == 0) || i == maxMeters;
      bool isText = (i % textStep == 0) || is50;

      if (is50) {
        // Tracinho gigante a cada 50m
        canvas.drawLine(Offset(x, size.height - 24), Offset(x, size.height - 12), paint);
      } else if (isText) {
        // Tracinho sub-multiplo com texto
        canvas.drawLine(Offset(x, size.height - 24), Offset(x, size.height - 18), paint);
      } else {
        // Tracinho simples a cada 10m
        canvas.drawLine(Offset(x, size.height - 24), Offset(x, size.height - 21), paint);
      }
      
      if (isText) {
        textPainter.text = TextSpan(text: '${i}m', style: const TextStyle(color: AppColors.textMuted, fontSize: 10, fontWeight: FontWeight.bold));
        textPainter.layout();
        textPainter.paint(canvas, Offset(x - textPainter.width / 2, size.height - 12));
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
