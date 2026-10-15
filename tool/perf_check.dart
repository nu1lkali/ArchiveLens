// 压测：单包 1000 张图时的索引耗时、随机读取耗时与内存占用。
import 'dart:io';

import 'package:archive_lens/src/services/zip_reader.dart';

Future<void> main() async {
  final zipPath = r'D:\project\archive_lens\tool\_fixtures\test_1000.zip';
  final file = File(zipPath);
  if (!await file.exists()) {
    print('缺少测试包，请先运行: python tool/make_zip_big.py');
    return;
  }
  print('压缩包大小: ${(await file.length()) ~/ 1024} KB');

  // 1. 索引
  final sw = Stopwatch()..start();
  final index = await ZipReader.readIndex(zipPath);
  sw.stop();
  print('readIndex: ${index.entries.length} 条 / 图片 ${index.images.length} 张,'
      ' 耗时 ${sw.elapsedMilliseconds} ms');

  final rss0 = ProcessInfo.currentRss;

  // 2. 顺序读取 300 张（模拟滚动一屏又一屏）
  final images = index.images;
  final sw2 = Stopwatch()..start();
  var bytesTotal = 0;
  final n = 300;
  for (var i = 0; i < n; i++) {
    final e = images[i];
    final info = index.byName[e.name]!;
    final b = await ZipReader.readEntryBytes(zipPath, info);
    bytesTotal += b.length;
  }
  sw2.stop();
  final rss1 = ProcessInfo.currentRss;

  print('顺序读取 $n 张: 耗时 ${sw2.elapsedMilliseconds} ms'
      ' (平均 ${(sw2.elapsedMilliseconds / n).toStringAsFixed(1)} ms/张),'
      ' 累计 ${bytesTotal ~/ 1024 / 1024} MB');
  print('内存 RSS: 前 ${rss0 ~/ 1024 / 1024} MB → 后 ${rss1 ~/ 1024 / 1024} MB'
      ' (增量 ${(rss1 - rss0) ~/ 1024 / 1024} MB)');

  // 3. 随机跳跃读取 200 次
  final sw3 = Stopwatch()..start();
  for (var i = 0; i < 200; i++) {
    final e = images[(i * 37 + 13) % images.length];
    final info = index.byName[e.name]!;
    await ZipReader.readEntryBytes(zipPath, info);
  }
  sw3.stop();
  print('随机跳跃 200 次: 耗时 ${sw3.elapsedMilliseconds} ms'
      ' (平均 ${(sw3.elapsedMilliseconds / 200).toStringAsFixed(1)} ms/次)');
  print('最终 RSS: ${ProcessInfo.currentRss ~/ 1024 / 1024} MB');
}
