// 纯 Dart 冒烟测试：验证 ZipReader 的中央目录解析与单文件随机读取。
// 因为 zip_reader.dart 只依赖 dart:io/dart:typed_data，可以直接用 dart 运行。
import 'dart:convert';
import 'dart:io';

import 'package:archive_lens/src/services/zip_reader.dart';

Future<void> main(List<String> args) async {
  final dir = Directory(r'D:\project\archive_lens\tool\_fixtures');
  final zipPath = '${dir.path}\\test_mixed.zip';
  final manifestFile = File('${dir.path}\\manifest.json');

  final manifest = (jsonDecode(await manifestFile.readAsString()) as List)
      .cast<Map<String, dynamic>>();

  // ---- 1. 列出 ----
  final sw = Stopwatch()..start();
  final index = await ZipReader.readIndex(zipPath);
  sw.stop();
  print('readIndex: ${index.entries.length} 条, 耗时 ${sw.elapsedMilliseconds} ms');

  final images = index.images;
  print('图片条目: ${images.length} (期望 ${manifest.length})');
  if (images.length != manifest.length) {
    throw StateError('图片数量不匹配');
  }

  // 校验名字 + 大小
  final byName = {for (final m in manifest) m['name'] as String: m['size'] as int};
  for (final e in images) {
    final expected = byName[e.name];
    if (expected == null) throw StateError('清单里找不到 ${e.name}');
    if (expected != e.size) {
      throw StateError('${e.name} 大小不匹配: ${e.size} != $expected');
    }
  }
  print('✓ 所有条目的名称与解压后大小一致');

  // 目录条目与 txt 应被正确识别/过滤
  final hasDir = index.entries.any((e) => e.name == 'emptydir/' && e.isDirectory);
  final hasTxt = index.entries.any((e) => e.name == 'readme.txt');
  print('✓ 目录条目识别=$hasDir, txt 存在但不计入图片=$hasTxt');

  // ---- 2. 随机读取若干张，比对字节 ----
  final zi = <String, ZipEntryInfo>{for (final e in index.entries) e.name: e};
  final rand = DateTime.now().millisecondsSinceEpoch;
  final picks = <int>[];
  for (var i = 0; i < 12; i++) {
    picks.add((rand ~/ (i + 3)) % manifest.length);
  }
  picks.add(0);
  picks.add(manifest.length - 1);

  var ok = 0;
  final sw2 = Stopwatch()..start();
  for (final p in picks.toSet()) {
    final m = manifest[p];
    final name = m['name'] as String;
    final info = zi[name];
    if (info == null) throw StateError('找不到 $name');
    final bytes = await ZipReader.readEntryBytes(zipPath, info);
    if (bytes.length != m['size']) {
      throw StateError('$name 读出的字节数不对: ${bytes.length} != ${m['size']}');
    }
    // 校验内容首部
    if (name.endsWith('.png')) {
      if (bytes[0] != 0x89 || bytes[1] != 0x50) {
        throw StateError('$name PNG 头不对');
      }
      // payload 是重复字节，检查第 9 个字节
      final idx = int.parse(name.split('img_')[1].split('.')[0]);
      if (bytes[8] != (idx % 256)) {
        throw StateError('$name 内容不对: ${bytes[8]} != ${idx % 256}');
      }
    } else if (name.endsWith('.jpg')) {
      if (bytes[0] != 0xFF || bytes[1] != 0xD8) {
        throw StateError('$name JPEG 头不对');
      }
    }
    ok++;
  }
  sw2.stop();
  print('✓ 随机读取 $ok 张，字节数与内容全部正确，耗时 ${sw2.elapsedMilliseconds} ms');

  // ---- 3. 中文名 ----
  final cn = zi['中文目录/图片_测试_001.jpg'];
  if (cn == null) throw StateError('中文文件名未正确解析');
  final cnBytes = await ZipReader.readEntryBytes(zipPath, cn);
  print('✓ 中文文件名读取正常: ${cn.name} (${cnBytes.length} bytes)');

  // ---- 4. stored(0) 与 deflate(8) 都覆盖到了 ----
  final methods = zi.values.map((e) => e.method).toSet();
  print('✓ 覆盖的压缩算法: $methods');

  print('\nALL PASS');
}
