import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../models.dart';
import '../utils/format.dart';
import 'zip_reader.dart' show ArchiveFormatException;

/// 7-Zip 命令行后端。
///
/// 负责处理 .rar / .7z（Dart 侧没有纯 Dart 的 rar 解码器），
/// 也可以在 zip 文件名乱码时作为 zip 的备用引擎。
///
/// 关键命令：
///   - 列出：`7z l -slt -sccUTF-8 -y <archive>`
///   - 取单张：`7z e -so -y <archive> <entryName>`  → 数据走 stdout，不落盘
class SevenZip {
  final String executable;

  const SevenZip(this.executable);

  static bool isAvailable(String exe) => exe.isNotEmpty && File(exe).existsSync();

  /// 常见的 7-Zip 安装位置
  static List<String> candidatePaths() {
    final pf = Platform.environment['ProgramFiles'] ?? r'C:\Program Files';
    final pf86 = Platform.environment['ProgramFiles(x86)'] ?? r'C:\Program Files (x86)';
    final localAppData =
        Platform.environment['LOCALAPPDATA'] ?? r'C:\Users\Public\AppData\Local';
    final exeDir = File(Platform.resolvedExecutable).parent.path;
    return <String>[
      '$pf\\7-Zip\\7z.exe',
      '$pf86\\7-Zip\\7z.exe',
      '$localAppData\\Programs\\7-Zip\\7z.exe',
      '$exeDir\\7z\\7z.exe',
      '$exeDir\\..\\7z\\7z.exe',
      r'C:\Program Files\7-Zip\7z.exe',
      r'C:\Program Files (x86)\7-Zip\7z.exe',
    ];
  }

  /// 自动探测 7z.exe
  static String? detect() {
    for (final p in candidatePaths()) {
      if (File(p).existsSync()) return p;
    }
    return null;
  }

  /// UNC / 网络盘路径下，子进程的工作目录不能是 UNC，否则会启动失败，
  /// 这里统一把工作目录固定到系统目录。
  String get _workingDirectory =>
      Platform.environment['SystemRoot'] ?? r'C:\Windows';

  /// 列出包内所有图片条目（不解压）
  Future<List<ImageEntry>> listImages(String archivePath) async {
    final result = await Process.run(
      executable,
      <String>['l', '-slt', '-sccUTF-8', '-y', archivePath],
      workingDirectory: _workingDirectory,
      stdoutEncoding: null, // 二进制读取，避免 Windows OEM 代码页破坏 UTF-8
      stderrEncoding: null,
      runInShell: false,
    );
    final stdout = safeDecode(_asBytes(result.stdout));
    if (result.exitCode != 0) {
      final stderr = safeDecode(_asBytes(result.stderr));
      throw ArchiveFormatException(
          '7z 列出失败 (code=${result.exitCode}): ${stderr.trim().isEmpty ? stdout.trim() : stderr.trim()}');
    }
    return _parseSlt(stdout);
  }

  /// 解析 `-slt` 输出
  ///
  /// 形如：
  /// ```
  /// ----------
  /// Path = 001.jpg
  /// Folder = -
  /// Size = 123456
  /// ```
  static List<ImageEntry> _parseSlt(String text) {
    final out = <ImageEntry>[];
    String? path;
    int? size;
    DateTime? modified;
    var isFolder = false;

    void flush() {
      final p = path;
      if (p != null && !isFolder && isImageName(p)) {
        out.add(ImageEntry(name: p, size: size ?? -1, modified: modified));
      }
      path = null;
      size = null;
      modified = null;
      isFolder = false;
    }

    for (final rawLine in const LineSplitter().convert(text)) {
      final line = rawLine.trimRight();
      if (line.startsWith('----------')) {
        flush();
        continue;
      }
      if (line.startsWith('Path = ')) {
        flush();
        path = line.substring(7);
      } else if (line.startsWith('Size = ')) {
        size = int.tryParse(line.substring(7).trim());
      } else if (line.startsWith('Modified = ')) {
        modified = _parseModified(line.substring(11).trim());
      } else if (line.startsWith('Folder = ')) {
        isFolder = line.substring(9).trim() == '+';
      } else if (line.startsWith('Attributes = ')) {
        final a = line.substring(13).trim();
        if (a.startsWith('D')) isFolder = true;
      }
    }
    flush();
    return out;
  }

  /// 7z -slt 的 Modified 形如 `2023-10-18 10:57:55`
  static DateTime? _parseModified(String v) {
    if (v.isEmpty) return null;
    // 归一化成 ISO-8601 交给 DateTime.tryParse
    final iso = v.replaceFirst(' ', 'T');
    final d = DateTime.tryParse(iso);
    if (d != null) return d;
    // 兜底：只取前 10 位的日期部分
    if (iso.length >= 10) {
      return DateTime.tryParse(iso.substring(0, 10));
    }
    return null;
  }

  /// 只把 [entryName] 这一张图解压到 stdout（不写临时文件）
  Future<Uint8List> readEntryBytes(
    String archivePath,
    String entryName, {
    int maxBytes = 128 * 1024 * 1024,
  }) async {
    final result = await Process.run(
      executable,
      <String>[
        'e',
        '-so', // 输出到 stdout
        '-y',
        '-sccUTF-8',
        archivePath,
        entryName,
      ],
      workingDirectory: _workingDirectory,
      stdoutEncoding: null,
      stderrEncoding: null,
      runInShell: false,
    );
    final bytes = _asBytes(result.stdout);
    if (result.exitCode != 0) {
      final stderr = safeDecode(_asBytes(result.stderr));
      throw ArchiveFormatException(
          '7z 读取失败 (code=${result.exitCode}): ${stderr.trim()}');
    }
    if (bytes.isEmpty) {
      throw const ArchiveFormatException('7z 返回了空数据');
    }
    if (bytes.length > maxBytes) {
      return Uint8List.sublistView(bytes, 0, maxBytes);
    }
    return bytes;
  }

  static Uint8List _asBytes(Object? v) {
    if (v is Uint8List) return v;
    if (v is List<int>) return Uint8List.fromList(v);
    if (v is String) return Uint8List.fromList(utf8.encode(v));
    return Uint8List(0);
  }
}
