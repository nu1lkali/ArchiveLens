import 'dart:async';
import 'dart:io';

import '../models.dart';

class ScanUpdate {
  /// 新发现的一个压缩包
  final ArchiveItem? item;

  /// 已遍历的目录数
  final int dirsScanned;

  /// 已遍历的文件数
  final int filesSeen;

  const ScanUpdate({
    this.item,
    required this.dirsScanned,
    required this.filesSeen,
  });
}

/// 递归扫描根目录，找出所有压缩包。
///
/// 用「显式目录栈 + list(non-recursive)」而不是 list(recursive:true)，
/// 这样某个子目录无权限时只跳过该目录，不会让整个扫描失败。
class ScanService {
  bool _cancelled = false;

  void cancel() => _cancelled = true;

  Stream<ScanUpdate> scan(String root) async* {
    _cancelled = false;
    final start = Directory(root);
    if (!await start.exists()) {
      throw FileSystemException('目录不存在', root);
    }

    final stack = <Directory>[start];
    var dirs = 0;
    var files = 0;

    while (stack.isNotEmpty && !_cancelled) {
      final dir = stack.removeLast();
      dirs++;

      Stream<FileSystemEntity> listing;
      try {
        listing = dir.list(followLinks: false);
      } catch (_) {
        continue; // 无权限 / 路径不存在 → 跳过
      }

      try {
        await for (final entity in listing) {
          if (_cancelled) break;
          if (entity is Directory) {
            stack.add(entity);
          } else if (entity is File) {
            files++;
            if (!isArchiveFile(entity.path)) continue;
            try {
              final st = await entity.stat();
              if (st.type != FileSystemEntityType.file) continue;
              yield ScanUpdate(
                item: ArchiveItem.fromFile(entity, st),
                dirsScanned: dirs,
                filesSeen: files,
              );
            } catch (_) {
              // stat 失败（例如文件被占用），跳过
            }
          }
          // 每 200 个文件让出一次事件循环，保证 UI 不卡
          if (files % 200 == 0) {
            await Future<void>.delayed(Duration.zero);
          }
        }
      } catch (_) {
        // 遍历过程中目录被删除 / 无权限
      }
    }
  }
}
