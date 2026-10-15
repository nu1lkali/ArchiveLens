import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models.dart';
import '../state/library_controller.dart';

class ShortcutEntry {
  final String keys;
  final String description;

  const ShortcutEntry(this.keys, this.description);
}

class ShortcutGroup {
  final String title;
  final List<ShortcutEntry> entries;

  const ShortcutGroup(this.title, this.entries);
}

/// 全部快捷键的「唯一数据源」——帮助面板直接渲染它，改这里即可同步文档。
const List<ShortcutGroup> kShortcutGroups = [
  ShortcutGroup('目录与扫描', [
    ShortcutEntry('Ctrl + O', '选择根目录'),
    ShortcutEntry('Ctrl + R  /  F5', '重新扫描当前根目录'),
    ShortcutEntry('Ctrl + F', '聚焦搜索框'),
  ]),
  ShortcutGroup('当前压缩包', [
    ShortcutEntry('L', '标记为「喜欢」'),
    ShortcutEntry('D  /  Delete', '标记为「待删」'),
    ShortcutEntry('Alt + ↑ / ↓', '打开上一个 / 下一个压缩包'),
  ]),
  ShortcutGroup('图片排序（右侧网格）', [
    ShortcutEntry('1', '按名称排序'),
    ShortcutEntry('2', '按日期排序'),
    ShortcutEntry('3', '随机排序'),
    ShortcutEntry('R', '换一批随机顺序'),
  ]),
  ShortcutGroup('列表排序（左侧清单）', [
    ShortcutEntry('Alt + 1  /  2  /  3  /  4', '名称 / 修改时间 / 大小 / 图片数'),
    ShortcutEntry('Alt + 5', '随机打乱列表'),
    ShortcutEntry('Shift + R', '换一批列表随机顺序'),
  ]),
  ShortcutGroup('批量与清理', [
    ShortcutEntry('Ctrl + A', '全选当前列表'),
    ShortcutEntry('Esc', '清空选择'),
    ShortcutEntry('Ctrl + Shift + D', '一键清理所有「待删」'),
  ]),
  ShortcutGroup('其他', [
    ShortcutEntry('Ctrl + ,', '打开设置'),
    ShortcutEntry('F1  /  Ctrl + /  /  ?', '显示本帮助'),
    ShortcutEntry('← →', '大图预览内翻页'),
    ShortcutEntry('Esc', '关闭大图预览'),
  ]),
];

/// Alt + 1..5 对应的列表排序，顺序和侧边栏下拉框保持一致
const List<SortMode> _kArchiveSortOrder = [
  SortMode.name,
  SortMode.modified,
  SortMode.size,
  SortMode.count,
  SortMode.random,
];

/// 全局快捷键作用域。
///
/// 放在 Scaffold 外层：子控件（包括 TextField）没消费掉的按键会冒泡到这里。
/// 因此在搜索框里打字时 L / D 这些单键不会被误触发，而 Ctrl+O 之类仍然生效。
class AppShortcutScope extends StatelessWidget {
  final Widget child;
  final LibraryController controller;
  final FocusNode searchFocus;
  final VoidCallback onPickFolder;
  final VoidCallback onShowHelp;
  final VoidCallback onOpenSettings;

  const AppShortcutScope({
    super.key,
    required this.child,
    required this.controller,
    required this.searchFocus,
    required this.onPickFolder,
    required this.onShowHelp,
    required this.onOpenSettings,
  });

  KeyEventResult _handled() => KeyEventResult.handled;

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: true,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;

        // HardwareKeyboard 没有 isControlPressed 之类的便捷 getter（Flutter 3.13），
        // 直接从当前按下的逻辑键集合里判断。
        final pressed = HardwareKeyboard.instance.logicalKeysPressed;
        final ctrl = pressed.contains(LogicalKeyboardKey.controlLeft) ||
            pressed.contains(LogicalKeyboardKey.controlRight);
        final shift = pressed.contains(LogicalKeyboardKey.shiftLeft) ||
            pressed.contains(LogicalKeyboardKey.shiftRight);
        final alt = pressed.contains(LogicalKeyboardKey.altLeft) ||
            pressed.contains(LogicalKeyboardKey.altRight);
        final key = event.logicalKey;
        final char = event.character?.toLowerCase();

        if (ctrl) {
          if (key == LogicalKeyboardKey.keyO) {
            onPickFolder();
            return _handled();
          }
          if (key == LogicalKeyboardKey.keyR) {
            _rescan(context);
            return _handled();
          }
          if (key == LogicalKeyboardKey.keyF) {
            searchFocus.requestFocus();
            return _handled();
          }
          if (key == LogicalKeyboardKey.keyA) {
            controller.selectAllVisible();
            return _handled();
          }
          if (key == LogicalKeyboardKey.comma) {
            onOpenSettings();
            return _handled();
          }
          if (key == LogicalKeyboardKey.slash) {
            onShowHelp();
            return _handled();
          }
          if (shift && key == LogicalKeyboardKey.keyD) {
            _cleanup(context);
            return _handled();
          }
          return KeyEventResult.ignored;
        }

        if (alt) {
          if (key == LogicalKeyboardKey.arrowUp) {
            controller.openRelative(-1);
            return _handled();
          }
          if (key == LogicalKeyboardKey.arrowDown) {
            controller.openRelative(1);
            return _handled();
          }
          // Alt + 1..5：切换左侧压缩包列表排序（顺序与下拉框一致）
          final idx = _altDigitIndex(key);
          if (idx != null && idx < _kArchiveSortOrder.length) {
            final m = _kArchiveSortOrder[idx];
            controller.setSort(m, asc: controller.sortMode == m ? null : true);
            return _handled();
          }
          return KeyEventResult.ignored;
        }

        if (key == LogicalKeyboardKey.f5) {
          _rescan(context);
          return _handled();
        }
        if (key == LogicalKeyboardKey.f1) {
          onShowHelp();
          return _handled();
        }
        if (key == LogicalKeyboardKey.escape) {
          controller.clearSelection();
          return _handled();
        }
        if (key == LogicalKeyboardKey.delete) {
          _mark(context, MarkStatus.disliked);
          return _handled();
        }

        if (shift && char == 'r') {
          controller.reshuffleArchives();
          return _handled();
        }

        switch (char) {
          case 'l':
            _mark(context, MarkStatus.liked);
            return _handled();
          case 'd':
            _mark(context, MarkStatus.disliked);
            return _handled();
          case '1':
            controller.setImageSort(ImageSort.name);
            return _handled();
          case '2':
            controller.setImageSort(ImageSort.date);
            return _handled();
          case '3':
            controller.reshuffleImages();
            return _handled();
          case 'r':
            controller.reshuffleImages();
            return _handled();
          case '?':
            onShowHelp();
            return _handled();
        }
        return KeyEventResult.ignored;
      },
      child: child,
    );
  }

  /// Alt + 数字 → 排序模式下标（1 起），不是数字键返回 null
  static int? _altDigitIndex(LogicalKeyboardKey key) {
    const digits = <LogicalKeyboardKey>[
      LogicalKeyboardKey.digit1,
      LogicalKeyboardKey.digit2,
      LogicalKeyboardKey.digit3,
      LogicalKeyboardKey.digit4,
      LogicalKeyboardKey.digit5,
      LogicalKeyboardKey.digit6,
    ];
    final i = digits.indexOf(key);
    return i < 0 ? null : i;
  }

  void _rescan(BuildContext context) {
    if (controller.root.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('还没有选择根目录，请先按 Ctrl + O')),
      );
      return;
    }
    controller.scan(controller.root);
  }

  void _mark(BuildContext context, MarkStatus status) {
    final item = controller.current;
    if (item == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先在左侧选择一个压缩包')),
      );
      return;
    }
    controller.setStatus(item, status);
  }

  Future<void> _cleanup(BuildContext context) async {
    if (controller.dislikedCount == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('没有标记为「待删」的压缩包')),
      );
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('将删除所有标记为「待删」的 ${controller.dislikedCount} 个压缩包，此操作不可撤销。'),
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
    final msg = await controller.deleteDisliked();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }
}

/// 快捷键指引
class ShortcutHelpDialog extends StatelessWidget {
  const ShortcutHelpDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AlertDialog(
      title: const Text('快捷键'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final group in kShortcutGroups) ...[
                Padding(
                  padding: const EdgeInsets.only(top: 10, bottom: 4),
                  child: Text(
                    group.title,
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                ),
                for (final e in group.entries)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 150,
                          child: Wrap(
                            spacing: 4,
                            children: [
                              for (final k in e.keys.split('  /  '))
                                _KeyChip(text: k.trim()),
                            ],
                          ),
                        ),
                        Expanded(
                          child: Text(e.description,
                              style: const TextStyle(fontSize: 12)),
                        ),
                      ],
                    ),
                  ),
              ],
              const SizedBox(height: 10),
              Text(
                '提示：把文件夹直接从资源管理器拖到窗口上即可识别路径。',
                style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('知道了'),
        ),
      ],
    );
  }
}

class _KeyChip extends StatelessWidget {
  final String text;

  const _KeyChip({required this.text});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: cs.surfaceVariant,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Text(
        text,
        style: const TextStyle(fontSize: 11, fontFamily: 'Consolas'),
      ),
    );
  }
}
