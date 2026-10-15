import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/seven_zip.dart';
import '../services/settings_service.dart';
import '../state/library_controller.dart';

class SettingsDialog extends StatefulWidget {
  const SettingsDialog({super.key});

  @override
  State<SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<SettingsDialog> {
  late final TextEditingController _sevenZipCtrl;
  String? _sevenZipStatus;

  @override
  void initState() {
    super.initState();
    final s = context.read<SettingsService>();
    _sevenZipCtrl = TextEditingController(text: s.sevenZipPath);
  }

  @override
  void dispose() {
    _sevenZipCtrl.dispose();
    super.dispose();
  }

  Future<void> _detect() async {
    final p = SevenZip.detect();
    if (!mounted) return;
    if (p == null) {
      setState(() => _sevenZipStatus = '未找到 7-Zip，请手动选择或前往 7-zip.org 安装');
      return;
    }
    _sevenZipCtrl.text = p;
    await context.read<SettingsService>().setSevenZipPath(p);
    if (!mounted) return;
    setState(() => _sevenZipStatus = '已找到：$p');
  }

  Future<void> _browse() async {
    final r = await FilePicker.platform.pickFiles(
      dialogTitle: '选择 7z.exe',
      type: FileType.custom,
      allowedExtensions: const ['exe'],
      lockParentWindow: true,
    );
    if (!mounted) return;
    final p = r?.files.single.path;
    if (p == null) return;
    _sevenZipCtrl.text = p;
    await context.read<SettingsService>().setSevenZipPath(p);
    if (!mounted) return;
    setState(() => _sevenZipStatus = '已设置：$p');
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<SettingsService>();
    final c = context.read<LibraryController>();

    return AlertDialog(
      title: const Text('设置'),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ---------- 7-Zip ----------
              const _Section('7-Zip 引擎（rar / 7z 必需）'),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _sevenZipCtrl,
                      decoration: const InputDecoration(
                        isDense: true,
                        border: OutlineInputBorder(),
                        hintText: r'C:\Program Files\7-Zip\7z.exe',
                      ),
                      style: const TextStyle(fontSize: 12),
                      onSubmitted: (v) => s.setSevenZipPath(v.trim()),
                    ),
                  ),
                  const SizedBox(width: 6),
                  OutlinedButton(
                      onPressed: _browse, child: const Text('浏览')),
                  const SizedBox(width: 6),
                  OutlinedButton(
                      onPressed: _detect, child: const Text('自动探测')),
                ],
              ),
              if (_sevenZipStatus != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(_sevenZipStatus!,
                      style: const TextStyle(fontSize: 11)),
                ),

              const Divider(height: 24),

              // ---------- ZIP 引擎 ----------
              const _Section('ZIP 解码引擎'),
              SwitchListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: const Text('使用内置纯 Dart ZIP 引擎（更快）'),
                subtitle: const Text(
                    '关闭则走 7z.exe。若中文文件名乱码，请关闭本开关',
                    style: TextStyle(fontSize: 11)),
                value: s.useDartZipEngine,
                onChanged: (v) => s.setUseDartZipEngine(v),
              ),

              const Divider(height: 24),

              // ---------- 缩略图 ----------
              const _Section('缩略图'),
              _SliderRow(
                label: '解码宽度',
                value: s.thumbWidth.toDouble(),
                min: 160,
                max: 640,
                divisions: 24,
                suffix: 'px',
                onChanged: (v) => s.setThumbWidth(v.round()),
              ),
              _SliderRow(
                label: '并发读取数',
                value: s.concurrency.toDouble(),
                min: 1,
                max: 12,
                divisions: 11,
                suffix: ' 个',
                onChanged: (v) => s.setConcurrency(v.round()),
              ),
              _SliderRow(
                label: '内存缓存上限',
                value: s.memoryCacheCount.toDouble(),
                min: 100,
                max: 1500,
                divisions: 28,
                suffix: ' 张',
                onChanged: (v) => s.setMemoryCacheCount(v.round()),
              ),

              const Divider(height: 24),

              // ---------- 磁盘缓存 ----------
              Row(
                children: [
                  const Expanded(
                      child: Text('缩略图磁盘缓存（跨会话复用）')),
                  Switch(
                    value: s.diskCacheEnabled,
                    onChanged: (v) => s.setDiskCacheEnabled(v),
                  ),
                ],
              ),
              _SliderRow(
                label: '磁盘缓存上限',
                value: s.diskCacheMaxFiles.toDouble(),
                min: 500,
                max: 20000,
                divisions: 39,
                suffix: ' 张',
                onChanged: (v) => s.setDiskCacheMaxFiles(v.round()),
              ),

              const Divider(height: 24),

              // ---------- 删除方式 ----------
              const _Section('删除方式'),
              Row(
                children: [
                  Expanded(
                    child: ChoiceChip(
                      label: const Center(
                          child: Text('移入回收站', style: TextStyle(fontSize: 12))),
                      selected: s.useRecycleBin,
                      onSelected: (_) => s.setUseRecycleBin(true),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ChoiceChip(
                      label: const Center(
                          child: Text('直接删除', style: TextStyle(fontSize: 12))),
                      selected: !s.useRecycleBin,
                      onSelected: (_) => s.setUseRecycleBin(false),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              const Text(
                '选「移入回收站」后，删除的文件可在系统的回收站里找回。'
                '网络/共享(UNC)路径不支持回收站，会自动按「直接删除」处理。',
                style: TextStyle(fontSize: 11),
              ),

              const Divider(height: 24),

              // ---------- 大图 ----------
              _SliderRow(
                label: '大图预览最大宽度',
                value: s.viewerWidth.toDouble(),
                min: 800,
                max: 4000,
                divisions: 16,
                suffix: 'px',
                onChanged: (v) => s.setViewerWidth(v.round()),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton.icon(
          icon: const Icon(Icons.delete_sweep_outlined, size: 18),
          label: const Text('清空缩略图缓存'),
          onPressed: () async {
            await c.clearCache();
            if (context.mounted) Navigator.pop(context);
          },
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('完成'),
        ),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  final String text;

  const _Section(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        text,
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
      ),
    );
  }
}

class _SliderRow extends StatelessWidget {
  final String label;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final String suffix;
  final ValueChanged<double> onChanged;

  const _SliderRow({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.suffix,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(width: 108, child: Text(label, style: const TextStyle(fontSize: 12))),
        Expanded(
          child: Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            divisions: divisions,
            onChanged: onChanged,
          ),
        ),
        SizedBox(
          width: 62,
          child: Text('${value.round()}$suffix',
              style: const TextStyle(fontSize: 11),
              textAlign: TextAlign.right),
        ),
      ],
    );
  }
}
