import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import '../models.dart';
import '../utils/format.dart';
import 'archive_service.dart';
import 'settings_service.dart';

/// 缩略图加载服务 —— 整个程序流畅度的关键。
///
/// 三级缓存：
///   1. 内存 LRU（ui.Image，已解码，直接上屏，零解码开销）
///   2. 磁盘缓存（PNG 字节，跨会话复用，避免反复 spawn 7z 进程）
///   3. 压缩包源（zip：后台 isolate seek+inflate；rar/7z：7z e -so）
///
/// 同时做了两件重要的事：
///   - 并发限流（默认 4），避免一次性开几十个进程 / isolate 把磁盘打满；
///   - 同一 key 的请求合并，列表快速回滚时不会重复读取。
class ThumbnailService {
  final SettingsService settings;
  final ArchiveService archiveService;

  final Directory? _diskDir;

  /// 内存 LRU：key → 已解码的 ui.Image
  final LinkedHashMap<String, ui.Image> _mem = LinkedHashMap<String, ui.Image>();

  /// 正在进行的请求（请求合并）
  final Map<String, Future<ui.Image?>> _inflight = {};

  int _writeCounter = 0;

  ThumbnailService({
    required this.settings,
    required this.archiveService,
    Directory? diskDir,
  }) : _diskDir = diskDir;

  static Future<ThumbnailService> create({
    required SettingsService settings,
    required ArchiveService archiveService,
    required Directory baseDir,
  }) async {
    final d = Directory('${baseDir.path}${Platform.pathSeparator}thumbs');
    if (!await d.exists()) {
      await d.create(recursive: true);
    }
    final s = ThumbnailService(
      settings: settings,
      archiveService: archiveService,
      diskDir: d,
    );
    unawaited(s._trimDiskCache());
    return s;
  }

  // ---------------- 并发限流 ----------------
  final List<Completer<void>> _waiters = <Completer<void>>[];
  int _used = 0;

  Future<void> _acquire() async {
    if (_used < settings.concurrency) {
      _used++;
      return;
    }
    final c = Completer<void>();
    _waiters.add(c);
    await c.future;
  }

  void _release() {
    if (_waiters.isNotEmpty) {
      _waiters.removeAt(0).complete(); // 把「名额」直接交给下一个
    } else {
      _used--;
    }
  }

  // ---------------- 对外 API ----------------

  String cacheKeyFor(String archivePath, String signature, ImageEntry entry) =>
      cacheKeyOf('$archivePath|$signature|${entry.name}|${settings.thumbWidth}');

  /// 从内存缓存里直接取（同步，用于首帧避免闪烁）
  ui.Image? peek(String key) {
    final v = _mem.remove(key);
    if (v == null) return null;
    _mem[key] = v; // 移到队尾 = 最近使用
    return v;
  }

  /// 加载缩略图。返回的 ui.Image 所有权归本服务，调用方**不要** dispose。
  Future<ui.Image?> load({
    required ArchiveItem item,
    required ImageEntry entry,
  }) {
    final key = cacheKeyFor(item.path, item.signature, entry);
    final cached = peek(key);
    if (cached != null) return Future<ui.Image?>.value(cached);

    final running = _inflight[key];
    if (running != null) return running;

    final future = _loadInternal(key, item, entry);
    _inflight[key] = future;
    return future;
  }

  Future<ui.Image?> _loadInternal(
      String key, ArchiveItem item, ImageEntry entry) async {
    try {
      await _acquire();
      // 再查一次内存（排队期间可能已被别人加载好）
      final again = peek(key);
      if (again != null) return again;

      final width = settings.thumbWidth;

      // 1) 磁盘缓存
      if (settings.diskCacheEnabled) {
        final disk = await _readDisk(key);
        if (disk != null) {
          final img = await _decode(disk, width);
          if (img != null) {
            _putMem(key, img);
            return img;
          }
        }
      }

      // 2) 源：只解压这一张
      final bytes = await archiveService.readImageBytes(item, entry);
      if (bytes.isEmpty) return null;

      final img = await _decode(bytes, width);
      if (img == null) return null;
      _putMem(key, img);

      // 3) 异步落盘（不阻塞返回）
      if (settings.diskCacheEnabled) {
        unawaited(_writeDisk(key, img));
      }
      return img;
    } catch (e) {
      return Future<ui.Image?>.error(e);
    } finally {
      _release();
      _inflight.remove(key);
    }
  }

  /// 读取大图（不限制到缩略图宽度）
  Future<ui.Image?> loadFull(ArchiveItem item, ImageEntry entry) async {
    final bytes = await archiveService.readFullBytes(item, entry);
    final maxW = settings.viewerWidth;
    if (maxW <= 0) return _decode(bytes, 1 << 20);
    return _decode(bytes, maxW);
  }

  // ---------------- 内部实现 ----------------

  Future<ui.Image?> _decode(Uint8List bytes, int targetWidth) async {
    try {
      final codec = await ui.instantiateImageCodec(
        bytes,
        targetWidth: targetWidth,
        allowUpscaling: false,
      );
      final frame = await codec.getNextFrame();
      codec.dispose();
      return frame.image;
    } catch (_) {
      return null;
    }
  }

  void _putMem(String key, ui.Image img) {
    _mem[key] = img;
    final cap = settings.memoryCacheCount;
    while (_mem.length > cap) {
      final oldestKey = _mem.keys.first;
      final removed = _mem.remove(oldestKey);
      removed?.dispose();
    }
  }

  File _diskFile(String key) => File(
      '${_diskDir!.path}${Platform.pathSeparator}${key.substring(0, 2)}'
      '${Platform.pathSeparator}$key.png');

  Future<Uint8List?> _readDisk(String key) async {
    try {
      final f = _diskFile(key);
      if (!await f.exists()) return null;
      return await f.readAsBytes();
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeDisk(String key, ui.Image img) async {
    try {
      final bd = await img.toByteData(format: ui.ImageByteFormat.png);
      if (bd == null) return;
      final f = _diskFile(key);
      if (!await f.parent.exists()) {
        await f.parent.create(recursive: true);
      }
      await f.writeAsBytes(
          bd.buffer.asUint8List(bd.offsetInBytes, bd.lengthInBytes),
          flush: false);

      // 每写入 300 张，检查一次缓存总量
      if (++_writeCounter >= 300) {
        _writeCounter = 0;
        unawaited(_trimDiskCache());
      }
    } catch (_) {
      // 落盘失败无所谓
    }
  }

  /// 磁盘缓存超过上限时，按修改时间删除最旧的一半
  Future<void> _trimDiskCache() async {
    final dir = _diskDir;
    if (dir == null || !settings.diskCacheEnabled) return;
    try {
      final entries = <FileSystemEntity>[];
      await for (final sub in dir.list(followLinks: false)) {
        if (sub is Directory) {
          await for (final f in sub.list(followLinks: false)) {
            if (f is File) entries.add(f);
          }
        } else if (sub is File) {
          entries.add(sub);
        }
      }
      if (entries.length <= settings.diskCacheMaxFiles) return;
      final stats = <MapEntry<File, int>>[];
      for (final e in entries) {
        final st = await e.stat();
        stats.add(MapEntry(e as File, st.modified.millisecondsSinceEpoch));
      }
      stats.sort((a, b) => a.value.compareTo(b.value));
      final removeCount = stats.length - (settings.diskCacheMaxFiles * 0.75).round();
      for (var i = 0; i < removeCount && i < stats.length; i++) {
        await stats[i].key.delete();
      }
    } catch (_) {}
  }

  Future<void> clearDiskCache() async {
    final dir = _diskDir;
    if (dir == null) return;
    try {
      if (await dir.exists()) await dir.delete(recursive: true);
      await dir.create(recursive: true);
    } catch (_) {}
  }

  void clearMemory() {
    for (final img in _mem.values) {
      img.dispose();
    }
    _mem.clear();
  }

  void dispose() {
    clearMemory();
    _inflight.clear();
  }
}
