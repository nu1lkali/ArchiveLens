import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../models.dart';
import '../services/thumbnail_service.dart';

/// 一个网格单元。
///
/// 只负责「请求 → 显示」，图片的生命周期由 ThumbnailService 的 LRU 管理，
/// 本 Widget **不会** dispose 拿到的 ui.Image。
class ImageTile extends StatefulWidget {
  final ArchiveItem item;
  final ImageEntry entry;
  final int index;
  final ThumbnailService thumbs;
  final int generation;
  final VoidCallback onTap;

  const ImageTile({
    super.key,
    required this.item,
    required this.entry,
    required this.index,
    required this.thumbs,
    required this.generation,
    required this.onTap,
  });

  @override
  State<ImageTile> createState() => _ImageTileState();
}

class _ImageTileState extends State<ImageTile> {
  ui.Image? _image;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant ImageTile old) {
    super.didUpdateWidget(old);
    if (old.entry.name != widget.entry.name ||
        old.item.path != widget.item.path ||
        old.generation != widget.generation) {
      _image = null;
      _error = null;

      _load();
    }
  }

  Future<void> _load() async {
    final gen = widget.generation;

    // 先同步查一次内存缓存，命中就能在首帧直接上屏（避免闪一下占位图）
    final key = widget.thumbs
        .cacheKeyFor(widget.item.path, widget.item.signature, widget.entry);
    final cached = widget.thumbs.peek(key);
    if (cached != null) {
      if (!mounted) return;
      setState(() {
        _image = cached;

      });
      return;
    }

    try {
      final img =
          await widget.thumbs.load(item: widget.item, entry: widget.entry);
      if (!mounted) return;
      // 期间用户切换了压缩包 → 丢弃这次结果
      if (gen != widget.generation) return;
      setState(() {
        _image = img;

      });
    } catch (e) {
      if (!mounted) return;
      if (gen != widget.generation) return;
      setState(() {
        _error = e;

      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Card(
      clipBehavior: Clip.antiAlias,
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: widget.onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (_image != null)
                    RawImage(
                      image: _image,
                      fit: BoxFit.cover,
                      filterQuality: FilterQuality.medium,
                    )
                  else if (_error != null)
                    _buildError(cs)
                  else
                    _buildPlaceholder(cs),
                  // 序号角标
                  Positioned(
                    left: 4,
                    top: 4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.55),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        '${widget.index + 1}',
                        style: const TextStyle(
                            color: Colors.white, fontSize: 10),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // 文件名
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              color: cs.surfaceVariant.withOpacity(0.6),
              child: Text(
                widget.entry.baseName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(fontSize: 11),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlaceholder(ColorScheme cs) {
    return Container(
      color: cs.surfaceVariant.withOpacity(0.4),
      alignment: Alignment.center,
      child: SizedBox(
        width: 18,
        height: 18,
        child: CircularProgressIndicator(strokeWidth: 2, color: cs.primary),
      ),
    );
  }

  Widget _buildError(ColorScheme cs) {
    return Container(
      color: cs.errorContainer.withOpacity(0.35),
      alignment: Alignment.center,
      child: Icon(Icons.broken_image_outlined,
          size: 24, color: cs.onErrorContainer),
    );
  }
}
