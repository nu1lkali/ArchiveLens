import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models.dart';
import '../state/library_controller.dart';
import '../utils/format.dart';
import 'app_dropdown.dart';

/// 左侧边栏：路径选择 / 搜索 / 过滤 / 压缩包列表 / 批量操作
class Sidebar extends StatefulWidget {
  final FocusNode searchFocus;
  final VoidCallback onPickFolder;

  const Sidebar({
    super.key,
    required this.searchFocus,
    required this.onPickFolder,
  });

  @override
  State<Sidebar> createState() => _SidebarState();
}

class _SidebarState extends State<Sidebar> {
  final TextEditingController _pathCtrl = TextEditingController();
  final TextEditingController _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    final c = context.read<LibraryController>();
    _pathCtrl.text = c.root;
    _searchCtrl.text = c.search;
    c.addListener(_syncFromController);
  }

  void _syncFromController() {
    final c = context.read<LibraryController>();
    if (_pathCtrl.text != c.root && c.root.isNotEmpty) {
      _pathCtrl.text = c.root;
    }
  }

  @override
  void dispose() {
    try {
      context.read<LibraryController>().removeListener(_syncFromController);
    } catch (_) {}
    _pathCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  // 目录选择由 HomePage 统一提供（快捷键 Ctrl+O 和按钮共用同一条路径）
  void _pickFolder() => widget.onPickFolder();

  @override
  Widget build(BuildContext context) {
    final c = context.watch<LibraryController>();
    final cs = Theme.of(context).colorScheme;

    return Column(
      children: [
        // ---------- 路径选择 ----------
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 10, 10, 6),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _pathCtrl,
                      decoration: const InputDecoration(
                        isDense: true,
                        prefixIcon: Icon(Icons.folder_outlined, size: 18),
                        hintText: r'D:\Comics  或  \\NAS\share',
                        border: OutlineInputBorder(),
                      ),
                      style: const TextStyle(fontSize: 12),
                      onSubmitted: (v) => _startScan(v),
                    ),
                  ),
                  const SizedBox(width: 6),
                  IconButton(
                    tooltip: '选择文件夹',
                    icon: const Icon(Icons.more_horiz),
                    onPressed: _pickFolder,
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      icon: const Icon(Icons.search, size: 16),
                      label: const Text('扫描'),
                      onPressed: c.scanning
                          ? null
                          : () => _startScan(_pathCtrl.text),
                    ),
                  ),
                  const SizedBox(width: 6),
                  OutlinedButton(
                    onPressed: c.scanning ? c.cancelScan : null,
                    child: const Text('取消'),
                  ),
                ],
              ),
              if (c.scanning) ...[
                const SizedBox(height: 6),
                const LinearProgressIndicator(minHeight: 2),
              ],
              const SizedBox(height: 4),
              Row(
                children: [
                  const Icon(Icons.drive_file_move_outlined,
                      size: 13, color: Colors.grey),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      '也可以把文件夹直接拖到窗口上',
                      style: TextStyle(fontSize: 10, color: Colors.grey[600]),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

        // ---------- 搜索 ----------
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          child: TextField(
            controller: _searchCtrl,
            focusNode: widget.searchFocus,
            decoration: InputDecoration(
              isDense: true,
              prefixIcon: const Icon(Icons.filter_alt_outlined, size: 18),
              hintText: '按名称过滤',
              border: const OutlineInputBorder(),
              suffixIcon: _searchCtrl.text.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.clear, size: 16),
                      onPressed: () {
                        _searchCtrl.clear();
                        c.setSearch('');
                      },
                    ),
            ),
            style: const TextStyle(fontSize: 12),
            onChanged: c.setSearch,
          ),
        ),

        // ---------- 状态过滤 ----------
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
          child: Wrap(
            spacing: 4,
            children: [
              for (final f in <(LibraryFilter, String)>[
                (LibraryFilter.all, '全部'),
                (LibraryFilter.liked, '喜欢'),
                (LibraryFilter.disliked, '待删'),
                (LibraryFilter.unmarked, '未标记'),
              ])
                Padding(
                  padding: const EdgeInsets.only(right: 0),
                  child: FilterChip(
                    label: Text(f.$2),
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    selected: c.filter == f.$1,
                    onSelected: (_) => c.setFilter(f.$1),
                  ),
                ),
            ],
          ),
        ),

        // ---------- 排序 ----------
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
          child: Row(
            children: [
              const Text('排序', style: TextStyle(fontSize: 11)),
              const SizedBox(width: 6),
              AppDropdown<SortMode>(
                value: c.sortMode,
                fontSize: 11,
                tooltip: '压缩包列表排序',
                items: const [
                  DropdownMenuItem(
                      value: SortMode.name, child: Text('名称')),
                  DropdownMenuItem(
                      value: SortMode.modified, child: Text('修改时间')),
                  DropdownMenuItem(
                      value: SortMode.size, child: Text('大小')),
                  DropdownMenuItem(
                      value: SortMode.count, child: Text('图片数')),
                  DropdownMenuItem(
                      value: SortMode.random, child: Text('随机打乱')),
                ],
                onChanged: (v) => v == null
                    ? null
                    : c.setSort(v, asc: c.sortMode == v ? null : true),
              ),
              // 随机排序下升降序没有意义，把箭头换成「换一批」
              if (c.sortMode == SortMode.random)
                IconButton(
                  icon: const Icon(Icons.shuffle, size: 16),
                  tooltip: '换一批随机顺序',
                  onPressed: c.reshuffleArchives,
                )
              else
                IconButton(
                  icon: Icon(c.sortAscending
                      ? Icons.arrow_upward
                      : Icons.arrow_downward,
                      size: 16),
                  tooltip: '升序 / 降序',
                  onPressed: () => c.setSort(c.sortMode),
                ),
              const Spacer(),
              Text('${c.visible.length} 项',
                  style: const TextStyle(fontSize: 11)),
            ],
          ),
        ),

        const Divider(height: 1),

        // ---------- 压缩包列表 ----------
        Expanded(child: _buildList(c)),

        const Divider(height: 1),

        // ---------- 批量操作 ----------
        _buildBatchBar(c, cs),
      ],
    );
  }

  void _startScan(String path) {
    final p = path.trim();
    if (p.isEmpty) return;
    context.read<LibraryController>().scan(p);
  }

  Widget _buildList(LibraryController c) {
    final items = c.visible;
    if (items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            c.scanning ? '扫描中…' : '暂无数据，请先选择根目录并扫描',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ),
      );
    }
    return ListView.builder(
      itemCount: items.length,
      itemExtent: 62,
      itemBuilder: (context, i) => _ArchiveRow(
        item: items[i],
        selected: c.selected.contains(items[i].path),
        isCurrent: c.current?.path == items[i].path,
        onTap: () => c.openArchive(items[i]),
        onToggle: () => c.toggleSelection(items[i].path),
        onShowInExplorer: () => _showInExplorer(items[i].path),
      ),
    );
  }

  static void _showInExplorer(String path) {
    try {
      Process.run('explorer', <String>['/select,', path],
          runInShell: false);
    } catch (_) {}
  }

  Widget _buildBatchBar(LibraryController c, ColorScheme cs) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 2,
            children: [
              _StatChip('共 ${c.totalCount}', cs.primary),
              _StatChip('喜欢 ${c.likedCount}', Colors.green),
              _StatChip('待删 ${c.dislikedCount}', Colors.red),
              _StatChip('选中 ${c.selected.length}', cs.tertiary),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              TextButton(
                onPressed: c.selectAllVisible,
                child: const Text('全选当前', style: TextStyle(fontSize: 12)),
              ),
              TextButton(
                onPressed: c.clearSelection,
                child: const Text('清空选择', style: TextStyle(fontSize: 12)),
              ),
              const Spacer(),
              PopupMenuButton<String>(
                tooltip: '批量标记',
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [Text('批量标记', style: TextStyle(fontSize: 12)), Icon(Icons.arrow_drop_down)],
                  ),
                ),
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'disliked', child: Text('标记选中的为「待删」')),
                  PopupMenuItem(value: 'liked', child: Text('标记选中的为「喜欢」')),
                  PopupMenuItem(value: 'normal', child: Text('清除选中项标记')),
                  PopupMenuItem(value: 'all-normal', child: Text('清除全部标记')),
                ],
                onSelected: (v) {
                  if (v == 'all-normal') {
                    c.clearAllMarks();
                  } else {
                    c.markSelected(v == 'disliked'
                        ? MarkStatus.disliked
                        : v == 'liked'
                            ? MarkStatus.liked
                            : MarkStatus.normal);
                  }
                },
              ),
            ],
          ),
          const SizedBox(height: 4),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: c.dislikedCount == 0 ? null : Colors.red,
              foregroundColor: c.dislikedCount == 0 ? null : Colors.white,
            ),
            icon: const Icon(Icons.delete_forever, size: 18),
            label: Text('一键清理已标记 (${c.dislikedCount})'),
            onPressed: c.dislikedCount == 0
                ? null
                : () => _confirmCleanup(context, c, false),
          ),
          if (c.selected.isNotEmpty) ...[
            const SizedBox(height: 4),
            OutlinedButton.icon(
              icon: const Icon(Icons.delete_outline, size: 18),
              label: Text('删除选中的 (${c.selected.length})'),
              onPressed: () => _confirmCleanup(context, c, true),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _confirmCleanup(
      BuildContext context, LibraryController c, bool selectedOnly) async {
    final count = selectedOnly ? c.selected.length : c.dislikedCount;
    final toBin = c.settings.useRecycleBin;
    final dest = toBin
        ? '移入回收站（可在回收站找回）'
        : '从磁盘彻底删除（不可撤销）';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认删除'),
        content: Text(
          selectedOnly
              ? '将把选中的 $count 个压缩包$dest。'
                  '${toBin ? 'UNC 网络路径仍会直接删除。' : ''}'
              : '将删除所有标记为「待删」的 $count 个压缩包，$dest。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;

    final msg = selectedOnly
        ? await c.deleteSelected()
        : await c.deleteDisliked();

    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 3)),
    );
  }
}

class _StatChip extends StatelessWidget {
  final String text;
  final Color color;

  const _StatChip(this.text, this.color);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(text,
          style: TextStyle(fontSize: 11, color: color.withAlpha(230))),
    );
  }
}

/// 列表中的一行
class _ArchiveRow extends StatelessWidget {
  final ArchiveItem item;
  final bool selected;
  final bool isCurrent;
  final VoidCallback onTap;
  final VoidCallback onToggle;
  final VoidCallback onShowInExplorer;

  const _ArchiveRow({
    required this.item,
    required this.selected,
    required this.isCurrent,
    required this.onTap,
    required this.onToggle,
    required this.onShowInExplorer,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    Color? barColor;
    IconData? trailingIcon;
    Color? trailingColor;
    switch (item.status) {
      case MarkStatus.liked:
        barColor = Colors.green;
        trailingIcon = Icons.favorite;
        trailingColor = Colors.green;
        break;
      case MarkStatus.disliked:
        barColor = Colors.red;
        trailingIcon = Icons.thumb_down;
        trailingColor = Colors.red;
        break;
      case MarkStatus.normal:
        barColor = null;
        trailingIcon = null;
        break;
    }

    return Container(
      decoration: BoxDecoration(
        color: isCurrent ? cs.primaryContainer.withOpacity(0.5) : null,
        border: Border(
          left: BorderSide(
            color: barColor ?? Colors.transparent,
            width: 3,
          ),
        ),
      ),
      child: ListTile(
        dense: true,
        contentPadding: const EdgeInsets.only(left: 8, right: 4),
        visualDensity: VisualDensity.compact,
        leading: SizedBox(
          width: 24,
          height: 24,
          child: Checkbox(
            value: selected,
            onChanged: (_) => onToggle(),
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            visualDensity: VisualDensity.compact,
          ),
        ),
        title: Text(
          item.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 12),
        ),
        subtitle: Text(
          '${formatBytes(item.fileSize)}'
          '${item.isListed ? ' · ${item.imageCount} 张' : ''}',
          maxLines: 1,
          style: const TextStyle(fontSize: 10),
        ),
        trailing: trailingIcon == null
            ? null
            : Icon(trailingIcon, size: 16, color: trailingColor),
        onTap: onTap,
        onLongPress: onShowInExplorer,
      ),
    );
  }
}
