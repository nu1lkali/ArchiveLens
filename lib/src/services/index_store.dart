import 'dart:convert';
import 'dart:io';

import '../models.dart';

class LibrarySnapshot {
  final String root;
  final DateTime savedAt;
  final List<ArchiveItem> items;

  LibrarySnapshot({
    required this.root,
    required this.savedAt,
    required this.items,
  });
}

/// 扫描索引 + 标记状态的持久化。
///
/// 只存元信息（路径 / 大小 / 修改时间 / 标记），不存包内图片，
/// 所以 1000+ 个包的索引文件也只有几百 KB。
class IndexStore {
  final Directory dir;

  IndexStore(this.dir);

  static Future<IndexStore> open(Directory base) async {
    if (!await base.exists()) {
      await base.create(recursive: true);
    }
    return IndexStore(base);
  }

  File get _file => File('${dir.path}${Platform.pathSeparator}library.json');

  Future<LibrarySnapshot?> load() async {
    final f = _file;
    if (!await f.exists()) return null;
    try {
      final m = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      final items = (m['items'] as List)
          .cast<Map<String, dynamic>>()
          .map(ArchiveItem.fromJson)
          .toList();
      return LibrarySnapshot(
        root: m['root'] as String? ?? '',
        savedAt: DateTime.fromMillisecondsSinceEpoch(
            (m['savedAt'] as num?)?.toInt() ?? 0),
        items: items,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> save(String root, List<ArchiveItem> items) async {
    try {
      final body = jsonEncode({
        'root': root,
        'savedAt': DateTime.now().millisecondsSinceEpoch,
        'items': [for (final i in items) i.toJson()],
      });
      await _file.writeAsString(body);
    } catch (_) {
      // 忽略写入失败
    }
  }
}
