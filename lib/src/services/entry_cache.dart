import 'dart:convert';
import 'dart:io';

import '../models.dart';
import '../utils/format.dart';

/// 包内图片列表的磁盘缓存。
///
/// 1000+ 个包，如果每次点开都要重新列一遍（zip 几 ms，7z 要 spawn 一个进程 ~100ms），
/// 体验很差。这里把「包内条目列表」按包缓存成单独的小文件，
/// 用 (大小+修改时间) 做签名判断缓存是否过期。
class EntryCache {
  final Directory _dir;

  EntryCache(this._dir);

  static Future<EntryCache> open(Directory base) async {
    final d = Directory('${base.path}${Platform.pathSeparator}entries');
    if (!await d.exists()) {
      await d.create(recursive: true);
    }
    return EntryCache(d);
  }

  String _fileFor(String archivePath, String signature) {
    final key = cacheKeyOf('$archivePath|$signature');
    // 分两层目录，避免单目录下文件过多
    return '${_dir.path}${Platform.pathSeparator}${key.substring(0, 2)}'
        '${Platform.pathSeparator}$key.json';
  }

  Future<List<ImageEntry>?> read(String archivePath, String signature) async {
    final f = File(_fileFor(archivePath, signature));
    if (!await f.exists()) return null;
    try {
      final text = await f.readAsString();
      final m = jsonDecode(text) as Map<String, dynamic>;
      if (m['sig'] != signature) return null;
      final raw = (m['e'] as List).cast<dynamic>();
      return raw
          .map((e) => ImageEntry(
                name: (e as List)[0] as String,
                size: (e[1] as num).toInt(),
              ))
          .toList(growable: false);
    } catch (_) {
      return null;
    }
  }

  Future<void> write(
      String archivePath, String signature, List<ImageEntry> entries) async {
    try {
      final f = File(_fileFor(archivePath, signature));
      if (!await f.parent.exists()) {
        await f.parent.create(recursive: true);
      }
      final body = jsonEncode({
        'sig': signature,
        'e': [for (final e in entries) [e.name, e.size]],
      });
      await f.writeAsString(body);
    } catch (_) {
      // 缓存写失败不影响主流程
    }
  }
}
