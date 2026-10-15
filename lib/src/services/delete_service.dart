import 'dart:io';

import 'package:flutter/foundation.dart';

class DeleteOutcome {
  final bool ok;
  final String message;

  const DeleteOutcome(this.ok, this.message);
}

/// 物理删除 / 移入回收站
class DeleteService {
  /// [toRecycleBin] 为 true 时优先送回收站；UNC 网络路径不支持回收站，会自动降级为彻底删除。
  static Future<DeleteOutcome> deleteFile(
    String path, {
    required bool toRecycleBin,
  }) async {
    final file = File(path);
    if (!await file.exists()) {
      return const DeleteOutcome(false, '文件不存在（可能已被删除）');
    }

    // ---- 1. 回收站 ----
    if (toRecycleBin && !_isUnc(path)) {
      final recycled = await _sendToRecycleBin(path);
      if (recycled) {
        return const DeleteOutcome(true, '已移入回收站');
      }
      // 失败则继续走彻底删除
    }

    // ---- 2. Dart 直接删除 ----
    String lastError = '';
    try {
      await file.delete();
      if (!await file.exists()) {
        return const DeleteOutcome(true, '已从磁盘彻底删除');
      }
    } catch (e) {
      lastError = e.toString();
    }

    // ---- 3. 只读 / 被占用 → cmd 强删 ----
    try {
      final r = await Process.run(
        'cmd',
        <String>['/c', 'del', '/f', '/q', path],
        runInShell: false,
      );
      if (r.exitCode == 0 && !await file.exists()) {
        return const DeleteOutcome(true, '已从磁盘彻底删除（cmd 强删）');
      }
      lastError = '${r.stderr}'.trim().isEmpty ? lastError : '${r.stderr}'.trim();
    } catch (e) {
      lastError = e.toString();
    }

    return DeleteOutcome(false, '删除失败：$lastError');
  }

  static bool _isUnc(String p) => p.startsWith(r'\\');

  static Future<bool> _sendToRecycleBin(String path) async {
    try {
      final tmp = Directory.systemTemp;
      final script = File(
          '${tmp.path}${Platform.pathSeparator}archive_lens_recycle.ps1');
      await script.writeAsString('''
param([string]\$Target)
Add-Type -AssemblyName Microsoft.VisualBasic
[Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile(\$Target,'OnlyErrorDialogs','SendToRecycleBin')
''');
      final r = await Process.run(
        'powershell',
        <String>[
          '-NoProfile',
          '-NonInteractive',
          '-ExecutionPolicy',
          'Bypass',
          '-File',
          script.path,
          '-Target',
          path,
        ],
        runInShell: false,
      );
      if (r.exitCode != 0) return false;
      return !await File(path).exists();
    } catch (e) {
      debugPrint('recycle failed: $e');
      return false;
    }
  }
}
