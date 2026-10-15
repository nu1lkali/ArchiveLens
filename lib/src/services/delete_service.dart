import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
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

    // 用户勾选了回收站，且不是 UNC 网络路径
    final recycleRequested = toRecycleBin && !_isUnc(path);

    // ---- 1. 回收站 ----
    if (recycleRequested) {
      final recycled = await _sendToRecycleBin(path);
      if (recycled) {
        return const DeleteOutcome(true, '已移入回收站');
      }
      // 回收站不可用（极少情况），继续走彻底删除，但结果提示里说明
    }

    // ---- 2. Dart 直接删除 ----
    String lastError = '';
    try {
      await file.delete();
      if (!await file.exists()) {
        return _ok(recycleRequested);
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
        return _ok(recycleRequested);
      }
      lastError =
          '${r.stderr}'.trim().isEmpty ? lastError : '${r.stderr}'.trim();
    } catch (e) {
      lastError = e.toString();
    }

    return DeleteOutcome(false, '删除失败：$lastError');
  }

  /// 结果文案：如果本来想进回收站但失败了，要如实告知，不能伪装成回收站
  static DeleteOutcome _ok(bool recycleRequested) => DeleteOutcome(
        true,
        recycleRequested
            ? '回收站不可用，已从磁盘彻底删除'
            : '已从磁盘彻底删除',
      );

  static bool _isUnc(String p) => p.startsWith(r'\\');

  /// 送回收站：优先用原生 Win32 SHFileOperation（最稳），失败再退 PowerShell
  static Future<bool> _sendToRecycleBin(String path) async {
    if (Platform.isWindows) {
      try {
        if (_sendToRecycleBinWin(path)) return true;
      } catch (e) {
        debugPrint('recycle(win) failed: $e');
      }
    }
    return _sendToRecycleBinPowerShell(path);
  }

  /// Win32：SHFileOperationW(FILEOP_DELETE | FOF_ALLOWUNDO)，把文件移入回收站
  static bool _sendToRecycleBinWin(String path) {
    final shell32 = DynamicLibrary.open('shell32.dll');
    final shFileOperation = shell32.lookupFunction<
        Int32 Function(Pointer<_SHFILEOPSTRUCTW>),
        int Function(Pointer<_SHFILEOPSTRUCTW>)>('SHFileOperationW');

    // pFrom 必须是双空结尾
    final pFrom = ('$path\x00').toNativeUtf16();
    final structPtr = calloc<_SHFILEOPSTRUCTW>();
    final struct = structPtr.ref;
    struct.hwnd = nullptr;
    struct.wFunc = 3; // FO_DELETE
    struct.pFrom = pFrom;
    struct.pTo = nullptr;
    struct.fFlags = 0x40 | 0x10 | 0x4 | 0x400; // ALLOWUNDO | NOCONFIRMATION | SILENT | NOERRORUI
    struct.fAnyOperationsAborted = 0;
    struct.hNameMappings = nullptr;
    struct.lpszProgressTitle = nullptr;

    final result = shFileOperation(structPtr);
    calloc.free(pFrom);
    calloc.free(structPtr);

    // 成功且原路径已不存在，说明已进入回收站
    return result == 0 && !File(path).existsSync();
  }

  static Future<bool> _sendToRecycleBinPowerShell(String path) async {
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
      debugPrint('recycle(ps) failed: $e');
      return false;
    }
  }
}

/// SHFILEOPSTRUCTW —— 与 Windows SDK 定义一致（64 位布局）
final class _SHFILEOPSTRUCTW extends Struct {
  external Pointer<Void> hwnd;
  @Uint32()
  external int wFunc;
  external Pointer<Utf16> pFrom;
  external Pointer<Utf16> pTo;
  @Uint32()
  external int fFlags;
  @Uint32()
  external int fAnyOperationsAborted;
  external Pointer<Void> hNameMappings;
  external Pointer<Utf16> lpszProgressTitle;
}
