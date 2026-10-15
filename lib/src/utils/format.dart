import 'dart:convert';
import 'dart:typed_data';

/// 人类可读的文件大小
String formatBytes(int bytes, {int decimals = 1}) {
  if (bytes < 0) return '-';
  if (bytes < 1024) return '$bytes B';
  const units = ['KB', 'MB', 'GB', 'TB'];
  var v = bytes / 1024.0;
  var i = 0;
  while (v >= 1024 && i < units.length - 1) {
    v /= 1024;
    i++;
  }
  return '${v.toStringAsFixed(decimals)} ${units[i]}';
}

/// 64 位 FNV-1a 哈希（用于生成缓存文件名，避免引入 crypto 依赖）
String fnv1a64Hex(String input) {
  const mask = 0xFFFFFFFFFFFFFFFF;
  var hash = 0xcbf29ce484222325; // FNV offset basis
  for (final unit in input.codeUnits) {
    hash ^= unit & 0xFF;
    // 低字节优先处理（兼容非 BMP 字符）
    hash = (hash * 0x100000001b3) & mask;
    final high = (unit >> 8) & 0xFF;
    if (high != 0) {
      hash ^= high;
      hash = (hash * 0x100000001b3) & mask;
    }
  }
  return hash.toRadixString(16).padLeft(16, '0');
}

/// 组合两个方向的哈希，降低碰撞概率到可忽略级别
String cacheKeyOf(String input) {
  final a = fnv1a64Hex(input);
  final b = fnv1a64Hex(String.fromCharCodes(input.codeUnits.reversed));
  return '$a$b';
}

/// 把任意字节安全地转成字符串（用于 7z 输出解析）
String safeDecode(List<int> bytes) =>
    const Utf8Decoder(allowMalformed: true).convert(bytes is Uint8List
        ? bytes
        : Uint8List.fromList(bytes));
