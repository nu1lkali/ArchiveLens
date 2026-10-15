import 'package:flutter/material.dart';

/// 统一风格的下拉框。
///
/// 应用整体是浅色（Scaffold 接近纯白），而 Material 默认的下拉菜单背景取的是
/// `canvasColor / surface`，展开后和白底几乎融为一体、边界完全看不出来。
/// 这里显式做三件事：
///   1. 菜单背景混一层主题色（浅色下偏蓝灰，深色下提亮），和白底拉开对比
///   2. 文字颜色显式取 `onSurface`，不再依赖上层 DefaultTextStyle
///   3. 收起状态给一个圆角描边，控件本身也有清晰轮廓
class AppDropdown<T> extends StatelessWidget {
  final T value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?>? onChanged;
  final double fontSize;
  final double itemHeight;
  final double? menuMaxHeight;
  final String? tooltip;

  const AppDropdown({
    super.key,
    required this.value,
    required this.items,
    required this.onChanged,
    this.fontSize = 12,
    this.itemHeight = 38,
    this.menuMaxHeight = 320,
    this.tooltip,
  });

  /// 菜单背景：在 surface 上混一层主色，保证和白底有可见差异
  static Color menuBackground(ColorScheme cs) => Color.alphaBlend(
        cs.primary.withOpacity(cs.brightness == Brightness.dark ? 0.20 : 0.12),
        cs.surface,
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final child = DropdownButtonHideUnderline(
      child: DropdownButton<T>(
        value: value,
        items: items,
        onChanged: onChanged,
        isDense: true,
        itemHeight: itemHeight,
        menuMaxHeight: menuMaxHeight,
        borderRadius: BorderRadius.circular(10),
        elevation: 4,
        // 关键：显式背景 + 显式文字色
        dropdownColor: menuBackground(cs),
        style: TextStyle(fontSize: fontSize, color: cs.onSurface),
        icon: Icon(Icons.arrow_drop_down, size: 18, color: cs.onSurfaceVariant),
      ),
    );

    final box = Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: child,
    );

    if (tooltip == null) return box;
    return Tooltip(message: tooltip!, child: box);
  }
}
