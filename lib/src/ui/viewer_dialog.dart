import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models.dart';
import '../services/thumbnail_service.dart';

/// 大图预览：只解码当前这一张（可限制最大宽度），支持左右翻页。
class ViewerDialog extends StatefulWidget {
  final ThumbnailService thumbs;
  final ArchiveItem item;
  final int initialIndex;

  const ViewerDialog({
    super.key,
    required this.thumbs,
    required this.item,
    required this.initialIndex,
  });

  @override
  State<ViewerDialog> createState() => _ViewerDialogState();
}

class _ViewerDialogState extends State<ViewerDialog> {
  late int _index;
  ui.Image? _image;
  bool _loading = true;
  String? _error;

  List<ImageEntry> get _entries => widget.item.images ?? const <ImageEntry>[];

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex;
    _load();
  }

  Future<void> _load() async {
    final i = _index;
    if (i < 0 || i >= _entries.length) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final img =
          await widget.thumbs.loadFull(widget.item, _entries[i]);
      if (!mounted || _index != i) return;
      setState(() {
        _image = img;
        _loading = false;
      });
      // 预取下一张，翻页时几乎零等待
      if (i + 1 < _entries.length) {
        // ignore: unawaited_futures
        widget.thumbs.loadFull(widget.item, _entries[i + 1]);
      }
    } catch (e) {
      if (!mounted || _index != i) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  void _go(int delta) {
    final next = _index + delta;
    if (next < 0 || next >= _entries.length) return;
    setState(() {
      _index = next;
      _image = null;
    });
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final total = _entries.length;
    final cs = Theme.of(context).colorScheme;
    final name = _entries.isEmpty ? '' : _entries[_index].baseName;

    return Dialog(
      backgroundColor: cs.surface,
      insetPadding: const EdgeInsets.all(20),
      child: SizedBox(
        width: 1180,
        height: 880,
        child: Focus(
          autofocus: true,
          onKeyEvent: (node, event) {
            if (event is KeyDownEvent) {
              if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
                _go(1);
                return KeyEventResult.handled;
              }
              if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
                _go(-1);
                return KeyEventResult.handled;
              }
              if (event.logicalKey == LogicalKeyboardKey.escape) {
                Navigator.of(context).pop();
                return KeyEventResult.handled;
              }
            }
            return KeyEventResult.ignored;
          },
          child: Column(
            children: [
              // 顶部标题栏
              Container(
                height: 48,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: cs.surfaceVariant.withOpacity(0.4),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${widget.item.name}  ·  ${_index + 1}/$total  ·  $name',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      tooltip: '关闭 (Esc)',
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
              // 图片区
              Expanded(
                child: Container(
                  color: Colors.black.withOpacity(0.9),
                  alignment: Alignment.center,
                  child: _buildBody(cs),
                ),
              ),
              // 底部翻页栏
              Container(
                height: 52,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: cs.surfaceVariant.withOpacity(0.4),
                ),
                child: Row(
                  children: [
                    IconButton(
                      tooltip: '上一张 (←)',
                      icon: const Icon(Icons.chevron_left),
                      onPressed: _index > 0 ? () => _go(-1) : null,
                    ),
                    Text('${_index + 1} / $total'),
                    IconButton(
                      tooltip: '下一张 (→)',
                      icon: const Icon(Icons.chevron_right),
                      onPressed:
                          _index < total - 1 ? () => _go(1) : null,
                    ),
                    const Spacer(),
                    Text(
                      '左右方向键翻页 · Esc 关闭',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody(ColorScheme cs) {
    if (_loading) {
      return const SizedBox(
        width: 36,
        height: 36,
        child: CircularProgressIndicator(strokeWidth: 3),
      );
    }
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Text('加载失败：$_error',
            style: const TextStyle(color: Colors.white70)),
      );
    }
    final img = _image;
    if (img == null) {
      return const Text('无图像', style: TextStyle(color: Colors.white70));
    }
    // 用 LayoutBuilder 把图像约束到可用区域，再交给 InteractiveViewer 缩放/平移
    return LayoutBuilder(
      builder: (context, constraints) {
        return InteractiveViewer(
          minScale: 0.2,
          maxScale: 8.0,
          child: SizedBox(
            width: constraints.maxWidth,
            height: constraints.maxHeight,
            child: FittedBox(
              fit: BoxFit.contain,
              child: RawImage(image: img, fit: BoxFit.contain),
            ),
          ),
        );
      },
    );
  }
}
