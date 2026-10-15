import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import '../models.dart';

class ArchiveFormatException implements Exception {
  final String message;
  const ArchiveFormatException(this.message);
  @override
  String toString() => 'ArchiveFormatException: $message';
}

/// ZIP 内部文件的元信息 + 随机访问所需偏移
class ZipEntryInfo {
  final String name;
  final int method;
  final int compressedSize;
  final int uncompressedSize;
  final int localHeaderOffset;
  final int crc;
  final bool isDirectory;

  /// 条目记录的修改时间（由 MS-DOS 日期时间解析），解析失败为 null
  final DateTime? modified;

  const ZipEntryInfo({
    required this.name,
    required this.method,
    required this.compressedSize,
    required this.uncompressedSize,
    required this.localHeaderOffset,
    required this.crc,
    required this.isDirectory,
    this.modified,
  });
}

/// 一个 zip 的中央目录解析结果（只有头信息，没有像素数据）
class ZipIndex {
  final List<ZipEntryInfo> entries;
  final Map<String, ZipEntryInfo> byName;

  ZipIndex(this.entries) : byName = {for (final e in entries) e.name: e};

  List<ImageEntry> get images => entries
      .where((e) => !e.isDirectory && isImageName(e.name))
      .map((e) => ImageEntry(
            name: e.name,
            size: e.uncompressedSize,
            modified: e.modified,
          ))
      .toList(growable: false);
}

/// 纯 Dart 实现的 ZIP **随机访问**读取器。
///
/// 设计目标（对应性能要求）：
/// 1. 只解析「中央目录」，不读取任何文件数据 → 列出 1000 个条目只花几毫秒、几十 KB；
/// 2. 读取单张图片时，直接 `seek` 到该条目的本地头偏移，只 inflat 这一张图 →
///    内存峰值 = 一张图的大小，与包内图片总数无关；
/// 3. 不依赖任何外部进程（对比 7z.exe 每次要 spawn 一个进程）。
class ZipReader {
  static const int _sigLocalFileHeader = 0x04034b50;
  static const int _sigCentralFileHeader = 0x02014b50;
  static const int _sigEndOfCentralDir = 0x06054b50;
  static const int _sigZip64EndOfCentralDir = 0x06064b50;
  static const int _sigZip64Locator = 0x07064b50;

  /// 读取中央目录，返回索引（不解压任何内容）
  static Future<ZipIndex> readIndex(String path) async {
    final file = File(path);
    final raf = await file.open(mode: FileMode.read);
    try {
      final fileLength = await raf.length();
      if (fileLength < 22) {
        throw const ArchiveFormatException('文件过小，不是有效 zip');
      }

      // ---- 1. 从文件尾部定位 EOCD（End Of Central Directory） ----
      final tailLength = math.min(fileLength, 65557 + 64);
      await raf.setPosition(fileLength - tailLength);
      final tail = await raf.read(tailLength);

      var eocd = -1;
      for (var i = tail.length - 22; i >= 0; i--) {
        if (_u32(tail, i) == _sigEndOfCentralDir) {
          eocd = i;
          break;
        }
      }
      if (eocd < 0) {
        throw const ArchiveFormatException('未找到 EOCD 记录，不是有效 zip');
      }

      var totalEntries = _u16(tail, eocd + 10);
      var cdSize = _u32(tail, eocd + 12);
      var cdOffset = _u32(tail, eocd + 16);

      // ---- 2. 处理 ZIP64（>4GB 或 >65535 个文件） ----
      if (cdOffset == 0xFFFFFFFF ||
          cdSize == 0xFFFFFFFF ||
          totalEntries == 0xFFFF) {
        final absEocd = fileLength - tailLength + eocd;
        final locatorPos = absEocd - 20;
        if (locatorPos >= 0) {
          await raf.setPosition(locatorPos);
          final loc = await raf.read(20);
          if (_u32(loc, 0) == _sigZip64Locator) {
            final z64Offset = _u64(loc, 8);
            await raf.setPosition(z64Offset);
            final z64 = await raf.read(56);
            if (_u32(z64, 0) == _sigZip64EndOfCentralDir) {
              totalEntries = _u64(z64, 32);
              cdSize = _u64(z64, 40);
              cdOffset = _u64(z64, 48);
            }
          }
        }
      }

      if (cdSize <= 0 || cdOffset < 0 || cdOffset + cdSize > fileLength) {
        // 有些 zip 的 EOCD 里 cdSize 不可靠，退化为「读到文件尾」
        cdSize = fileLength - cdOffset;
        if (cdSize <= 0) {
          throw const ArchiveFormatException('中央目录偏移非法');
        }
      }

      // ---- 3. 读取并解析中央目录（只有头，几十 KB~几 MB） ----
      await raf.setPosition(cdOffset);
      final cd = await raf.read(cdSize);
      return ZipIndex(_parseCentralDirectory(cd, totalEntries));
    } finally {
      await raf.close();
    }
  }

  static List<ZipEntryInfo> _parseCentralDirectory(
      Uint8List cd, int totalEntries) {
    final out = <ZipEntryInfo>[];
    var pos = 0;
    final limit = cd.length - 4;
    while (pos < limit && out.length < (totalEntries > 0 ? totalEntries : 1 << 30)) {
      if (_u32(cd, pos) != _sigCentralFileHeader) {
        // 遇到无法识别的记录就停止，避免死循环
        break;
      }
      final flags = _u16(cd, pos + 8);
      final method = _u16(cd, pos + 10);
      final dosTime = _u16(cd, pos + 12);
      final dosDate = _u16(cd, pos + 14);
      final crc = _u32(cd, pos + 16);
      var compressedSize = _u32(cd, pos + 20);
      var uncompressedSize = _u32(cd, pos + 24);
      final nameLen = _u16(cd, pos + 28);
      final extraLen = _u16(cd, pos + 30);
      final commentLen = _u16(cd, pos + 32);
      final diskStart = _u16(cd, pos + 34);
      final externalAttrs = _u32(cd, pos + 38);
      var localHeaderOffset = _u32(cd, pos + 42);

      // ZIP64 扩展字段（0x0001），仅包含值为 0xFFFFFFFF 的那些字段
      if (extraLen > 0) {
        var ep = pos + 46 + nameLen;
        final epEnd = ep + extraLen;
        while (ep + 4 <= epEnd && ep + 4 <= cd.length) {
          final headerId = _u16(cd, ep);
          final dataSize = _u16(cd, ep + 2);
          var dp = ep + 4;
          if (headerId == 0x0001) {
            if (uncompressedSize == 0xFFFFFFFF && dp + 8 <= cd.length) {
              uncompressedSize = _u64(cd, dp);
              dp += 8;
            }
            if (compressedSize == 0xFFFFFFFF && dp + 8 <= cd.length) {
              compressedSize = _u64(cd, dp);
              dp += 8;
            }
            if (localHeaderOffset == 0xFFFFFFFF && dp + 8 <= cd.length) {
              localHeaderOffset = _u64(cd, dp);
              dp += 8;
            }
            if (diskStart == 0xFFFF && dp + 4 <= cd.length) {
              dp += 4;
            }
          }
          ep += 4 + dataSize;
        }
      }

      final rawName = Uint8List.sublistView(cd, pos + 46, pos + 46 + nameLen);
      final name = _decodeName(rawName, flags);

      final isDirectory =
          name.endsWith('/') || name.endsWith('\\') || (externalAttrs & 0x10) != 0;

      out.add(ZipEntryInfo(
        name: name,
        method: method,
        compressedSize: compressedSize,
        uncompressedSize: uncompressedSize,
        localHeaderOffset: localHeaderOffset,
        crc: crc,
        isDirectory: isDirectory,
        modified: _dosDateTime(dosDate, dosTime),
      ));

      pos += 46 + nameLen + extraLen + commentLen;
    }
    return out;
  }

  /// 解析 ZIP 里的 MS-DOS 日期时间
  ///   日期：bits 0-4 日，5-8 月，9-15 年（相对 1980）
  ///   时间：bits 0-4 秒/2，5-10 分，11-15 时
  static DateTime? _dosDateTime(int dosDate, int dosTime) {
    if (dosDate == 0 && dosTime == 0) return null;
    final year = ((dosDate >> 9) & 0x7F) + 1980;
    final month = (dosDate >> 5) & 0x0F;
    final day = dosDate & 0x1F;
    final hour = (dosTime >> 11) & 0x1F;
    final minute = (dosTime >> 5) & 0x3F;
    final second = (dosTime & 0x1F) * 2;
    if (year < 1980 || month < 1 || month > 12 || day < 1 || day > 31) {
      return null;
    }
    try {
      return DateTime(year, month, day, hour, minute, second);
    } catch (_) {
      return null;
    }
  }

  /// ZIP 文件名编码：bit 11 表示 UTF-8；否则按 ANSI(CP437/GBK) 处理。
  ///
  /// Dart 没有内建 GBK 解码器，这里做「UTF-8 优先 + latin1 兜底」，
  /// 保证不会抛异常；若遇到中文乱码，可在设置里把 zip 引擎切成 7-Zip。
  static String _decodeName(Uint8List raw, int flags) {
    final isUtf8 = (flags & 0x800) != 0;
    if (isUtf8) {
      return const Utf8Decoder(allowMalformed: true).convert(raw);
    }
    // 先看是否是合法 UTF-8（没有替换字符）
    final asUtf8 = const Utf8Decoder(allowMalformed: true).convert(raw);
    if (!asUtf8.contains('\uFFFD')) return asUtf8;
    return String.fromCharCodes(raw);
  }

  /// 只解压 [entry] 这一张图，返回原始字节（jpeg/png/...）
  ///
  /// 这是整个程序的性能核心：seek → 读取 compressedSize 字节 → inflate。
  static Future<Uint8List> readEntryBytes(String path, ZipEntryInfo entry) async {
    final raf = await File(path).open(mode: FileMode.read);
    try {
      final fileLength = await raf.length();

      // 读本地文件头，得到真正的「文件名长度 + 扩展字段长度」，
      // 因为这两个值在中央目录和本地头里可能不一致。
      if (entry.localHeaderOffset + 30 > fileLength) {
        throw const ArchiveFormatException('本地头偏移越界');
      }
      await raf.setPosition(entry.localHeaderOffset);
      final head = await raf.read(30);
      if (_u32(head, 0) != _sigLocalFileHeader) {
        throw const ArchiveFormatException('本地文件头签名不匹配');
      }
      final nameLen = _u16(head, 26);
      final extraLen = _u16(head, 28);
      final dataOffset = entry.localHeaderOffset + 30 + nameLen + extraLen;

      var compSize = entry.compressedSize;
      Uint8List compressed;
      await raf.setPosition(dataOffset);

      if (compSize > 0 && dataOffset + compSize <= fileLength) {
        compressed = await raf.read(compSize);
      } else {
        // 流式生成的 zip（本地头没有大小，靠数据描述符收尾）：
        // 向后扫描到下一个 PK 签名，作为边界。
        final remaining = fileLength - dataOffset;
        final guess = entry.uncompressedSize > 0
            ? entry.uncompressedSize + 4096
            : 8 * 1024 * 1024;
        final readLen = math.min(remaining, math.max(guess, 65536));
        final buf = await raf.read(readLen);
        compressed = _trimToNextSignature(buf);
      }

      switch (entry.method) {
        case 0: // stored
          return compressed;
        case 8: // deflate
          return _inflate(compressed);
        default:
          throw ArchiveFormatException(
              '不支持的压缩算法 (method=${entry.method})，请在设置中改用 7-Zip 引擎');
      }
    } finally {
      await raf.close();
    }
  }

  static Uint8List _trimToNextSignature(Uint8List buf) {
    for (var i = 4; i + 4 <= buf.length; i++) {
      final v = _u32(buf, i);
      if (v == _sigLocalFileHeader || v == _sigCentralFileHeader) {
        return Uint8List.sublistView(buf, 0, i);
      }
    }
    return buf;
  }

  static Uint8List _inflate(Uint8List data) {
    try {
      final out = ZLibDecoder(raw: true).convert(data);
      return out is Uint8List ? out : Uint8List.fromList(out);
    } catch (_) {
      // 少数工具的 zip 里放的是带 zlib 头的数据，再试一次
      try {
        final out = ZLibDecoder().convert(data);
        return out is Uint8List ? out : Uint8List.fromList(out);
      } catch (e) {
        throw ArchiveFormatException('inflate 失败: $e');
      }
    }
  }

  // ---- 小端读取工具 ----
  static int _u16(Uint8List b, int o) => b[o] | (b[o + 1] << 8);

  static int _u32(Uint8List b, int o) =>
      b[o] | (b[o + 1] << 8) | (b[o + 2] << 16) | (b[o + 3] << 24);

  static int _u64(Uint8List b, int o) =>
      _u32(b, o) | (_u32(b, o + 4) * 0x100000000);
}

/// 供 `compute()` 使用的顶层任务（isolate 里做 inflate，不阻塞 UI 线程）
class ZipReadTaskArgs {
  final String path;
  final ZipEntryInfo entry;

  const ZipReadTaskArgs(this.path, this.entry);
}

/// 顶层函数：在后台 isolate 中解压单张图片
Future<Uint8List> zipReadEntryTask(ZipReadTaskArgs args) =>
    ZipReader.readEntryBytes(args.path, args.entry);
