import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models.dart';
import '../services/settings_service.dart';
import '../services/thumbnail_service.dart';
import 'image_tile.dart';
import 'viewer_dialog.dart';

/// 右侧主界面：当前压缩包的图片网格。
///
/// 用 GridView.builder 按需构建 —— 只有出现在视口附近的单元才会被创建，
/// 每个单元再向 ThumbnailService 请求一张缩略图，因此
/// 「包里有 1000 张图」和「包里有 10 张图」的内存占用几乎一样。
class ImageGrid extends StatelessWidget {
  final ArchiveItem item;

  /// 已按当前排序规则排好序的图片列表
  final List<ImageEntry> entries;
  final int generation;
  final ThumbnailService thumbs;

  const ImageGrid({
    super.key,
    required this.item,
    required this.entries,
    required this.generation,
    required this.thumbs,
  });

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) return const SizedBox.shrink();

    final settings = context.watch<SettingsService>();
    final extent = settings.gridExtent.clamp(110.0, 420.0);

    return GridView.builder(
      // 切换压缩包时重建，滚动位置自动回到顶部
      key: ValueKey<String>('${item.path}::$generation'),
      padding: const EdgeInsets.all(10),
      // 预加载视口外一屏，滚动更顺
      cacheExtent: extent * 3,
      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: extent,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        childAspectRatio: 0.72,
      ),
      itemCount: entries.length,
      itemBuilder: (context, index) {
        return ImageTile(
          item: item,
          entry: entries[index],
          index: index,
          thumbs: thumbs,
          generation: generation,
          onTap: () {
            showDialog(
              context: context,
              builder: (_) => ViewerDialog(
                thumbs: thumbs,
                item: item,
                initialIndex: index,
              ),
            );
          },
        );
      },
    );
  }
}
