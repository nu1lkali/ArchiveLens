import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models.dart';
import '../services/drop_service.dart';
import '../state/library_controller.dart';
import '../utils/format.dart';
import 'app_dropdown.dart';
import 'app_shortcuts.dart';
import 'image_grid.dart';
import 'settings_dialog.dart';
import 'sidebar.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  bool _inited = false;
  final FocusNode _searchFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final c = context.read<LibraryController>();
      await c.init();
      if (!mounted) return;

      // 从资源管理器把文件夹拖到窗口 → native 层通过 MethodChannel 送过来
      DropService((path) {
        if (!mounted) return;
        final c = context.read<LibraryController>();
        c.scan(path);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已拖入目录，开始扫描：$path')),
        );
      });

      setState(() => _inited = true);
    });
  }

  @override
  void dispose() {
    _searchFocus.dispose();
    super.dispose();
  }

  Future<void> _pickFolder() async {
    final c = context.read<LibraryController>();
    final dir = await FilePicker.platform.getDirectoryPath(
      dialogTitle: '选择图片压缩包根目录',
      lockParentWindow: true,
    );
    if (dir == null || !mounted) return;
    await c.scan(dir);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<LibraryController>();

    return AppShortcutScope(
      controller: c,
      searchFocus: _searchFocus,
      onPickFolder: _pickFolder,
      onShowHelp: () => showDialog(
        context: context,
        builder: (_) => const ShortcutHelpDialog(),
      ),
      onOpenSettings: () => showDialog(
        context: context,
        builder: (_) => const SettingsDialog(),
      ),
      child: Scaffold(
        appBar: AppBar(
          title: const Text('ArchiveLens · 图片压缩包管理器'),
          actions: [
            IconButton(
              tooltip: '快捷键 (F1)',
              icon: const Icon(Icons.keyboard_outlined),
              onPressed: () => showDialog(
                context: context,
                builder: (_) => const ShortcutHelpDialog(),
              ),
            ),
            IconButton(
              tooltip: '设置 (Ctrl + ,)',
              icon: const Icon(Icons.settings_outlined),
              onPressed: () => showDialog(
                context: context,
                builder: (_) => const SettingsDialog(),
              ),
            ),
            IconButton(
              tooltip: '清空缩略图缓存',
              icon: const Icon(Icons.cleaning_services_outlined),
              onPressed: () async {
                await c.clearCache();
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('缩略图缓存已清空')),
                  );
                }
              },
            ),
            const SizedBox(width: 8),
          ],
        ),
        body: !_inited
            ? const Center(child: CircularProgressIndicator())
            : Row(
                children: [
                  SizedBox(
                    width: 340,
                    child: Sidebar(
                      searchFocus: _searchFocus,
                      onPickFolder: _pickFolder,
                    ),
                  ),
                  const VerticalDivider(width: 1),
                  const Expanded(child: _MainPanel()),
                ],
              ),
        bottomNavigationBar: _StatusBar(),
      ),
    );
  }
}

/// 右侧主面板
class _MainPanel extends StatelessWidget {
  const _MainPanel();

  @override
  Widget build(BuildContext context) {
    final c = context.watch<LibraryController>();
    final item = c.current;

    return Column(
      children: [
        if (item != null) _Header(item: item),
        const Divider(height: 1),
        Expanded(child: _buildBody(context, c, item)),
      ],
    );
  }

  Widget _buildBody(
      BuildContext context, LibraryController c, ArchiveItem? item) {
    if (item == null) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.photo_library_outlined, size: 56, color: Colors.grey),
            SizedBox(height: 12),
            Text('从左侧选择一个压缩包开始预览'),
            SizedBox(height: 4),
            Text('不会解压整个包，只会按需读取你看到的那些图',
                style: TextStyle(fontSize: 12, color: Colors.grey)),
          ],
        ),
      );
    }
    if (item.listing) {
      return const Center(child: CircularProgressIndicator());
    }
    if (item.listError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 40, color: Colors.red),
              const SizedBox(height: 10),
              const Text('列出包内容失败'),
              const SizedBox(height: 6),
              Text(item.listError!,
                  style: const TextStyle(fontSize: 12, color: Colors.grey)),
            ],
          ),
        ),
      );
    }
    if (item.images != null && item.images!.isEmpty) {
      return const Center(child: Text('该压缩包内没有图片'));
    }

    final thumbs = c.thumbnailService;
    if (thumbs == null) return const SizedBox.shrink();

    return ImageGrid(
      item: item,
      entries: c.orderedImages,
      generation: c.generation,
      thumbs: thumbs,
    );
  }
}

/// 当前压缩包的信息栏 + 单包操作 + 图片排序
class _Header extends StatelessWidget {
  final ArchiveItem item;

  const _Header({required this.item});

  @override
  Widget build(BuildContext context) {
    final c = context.read<LibraryController>();
    final cs = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  item.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              const SizedBox(width: 8),
              _gridSlider(context),
              IconButton(
                tooltip: '在资源管理器中显示',
                icon: const Icon(Icons.folder_open_outlined, size: 20),
                onPressed: () => Process.run(
                    'explorer', <String>['/select,', item.path],
                    runInShell: false),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            '${item.path}   ·   ${formatBytes(item.fileSize)}'
            '${item.isListed ? '   ·   ${item.imageCount} 张图片' : ''}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              OutlinedButton.icon(
                icon: const Icon(Icons.favorite_border, size: 16),
                label: const Text('喜欢'),
                style: item.status == MarkStatus.liked
                    ? OutlinedButton.styleFrom(
                        foregroundColor: Colors.green,
                        side: const BorderSide(color: Colors.green))
                    : null,
                onPressed: () => c.setStatus(item, MarkStatus.liked),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                icon: const Icon(Icons.thumb_down_off_alt, size: 16),
                label: const Text('标记待删'),
                style: item.status == MarkStatus.disliked
                    ? OutlinedButton.styleFrom(
                        foregroundColor: Colors.red,
                        side: const BorderSide(color: Colors.red))
                    : null,
                onPressed: () => c.setStatus(item, MarkStatus.disliked),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: Colors.red),
                icon: const Icon(Icons.delete_forever, size: 16),
                label: const Text('直接删除'),
                onPressed: () => _confirmDelete(context, c, item),
              ),
              const Spacer(),
              // ---- 图片排序（状态会被记忆） ----
              const _ImageSortControl(),
            ],
          ),
        ],
      ),
    );
  }

  Widget _gridSlider(BuildContext context) {
    return SizedBox(
      width: 130,
      child: Row(
        children: [
          const Icon(Icons.grid_view, size: 16),
          Expanded(
            child: Slider(
              min: 110,
              max: 360,
              divisions: 25,
              value: context
                  .watch<LibraryController>()
                  .settings
                  .gridExtent
                  .clamp(110.0, 360.0),
              onChanged: (v) =>
                  context.read<LibraryController>().settings.setGridExtent(v),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(
      BuildContext context, LibraryController c, ArchiveItem item) async {
    final toBin = c.settings.useRecycleBin;
    final dest = toBin
        ? '移入回收站（可在回收站找回）'
        : '从磁盘彻底删除（不可撤销）';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('将$dest：\n${item.name}'
            '${toBin ? '\n\nUNC 网络路径仍会直接删除。' : ''}'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final msg = await c.deleteOne(item);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }
}

/// 图片网格排序控件：名称 / 日期 / 随机 + 升降序 + 换一批
class _ImageSortControl extends StatelessWidget {
  const _ImageSortControl();

  @override
  Widget build(BuildContext context) {
    final c = context.watch<LibraryController>();
    final sort = c.imageSort;
    final isRandom = sort == ImageSort.random;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.sort, size: 16),
        const SizedBox(width: 4),
        AppDropdown<ImageSort>(
          value: sort,
          tooltip: '图片网格排序',
          items: const [
            DropdownMenuItem(value: ImageSort.name, child: Text('名称')),
            DropdownMenuItem(value: ImageSort.date, child: Text('日期')),
            DropdownMenuItem(value: ImageSort.random, child: Text('随机')),
          ],
          onChanged: (v) {
            if (v != null) c.setImageSort(v);
          },
        ),
        IconButton(
          tooltip: isRandom
              ? '随机排序无升序/降序'
              : (c.imageSortAscending ? '当前升序，点击改为降序' : '当前降序，点击改为升序'),
          icon: Icon(
            c.imageSortAscending ? Icons.arrow_upward : Icons.arrow_downward,
            size: 16,
          ),
          // 随机排序下升降序无意义，置灰
          onPressed: isRandom
              ? null
              : () => c.setImageSortAscending(!c.imageSortAscending),
        ),
        if (isRandom)
          TextButton.icon(
            icon: const Icon(Icons.shuffle, size: 16),
            label: const Text('换一批'),
            onPressed: c.reshuffleImages,
          ),
      ],
    );
  }
}

/// 底部状态栏
class _StatusBar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final c = context.watch<LibraryController>();
    final cs = Theme.of(context).colorScheme;

    return Container(
      height: 30,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      color: cs.surfaceVariant.withOpacity(0.35),
      child: Row(
        children: [
          Expanded(
            child: Text(
              c.errorMessage ?? c.statusMessage,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                color: c.errorMessage != null ? Colors.red : null,
              ),
            ),
          ),
          Text(
            '${c.totalCount} 个包 · ${formatBytes(c.totalSize)}',
            style: const TextStyle(fontSize: 11),
          ),
          const SizedBox(width: 12),
          InkWell(
            onTap: () => showDialog(
              context: context,
              builder: (_) => const ShortcutHelpDialog(),
            ),
            child: const Text('快捷键 (F1)',
                style: TextStyle(fontSize: 11, color: Colors.blue)),
          ),
        ],
      ),
    );
  }
}
