import 'dart:io';

import 'package:flutter/foundation.dart';

import '../models.dart';
import 'entry_cache.dart';
import 'seven_zip.dart';
import 'settings_service.dart';
import 'zip_reader.dart';

/// 压缩包读取门面（Facade）。
///
/// 对上层只暴露两个能力：
///   - [listImages]：只列出包内图片条目（不解压）
///   - [readImageBytes]：只取某张图片的原始字节（不解压整个包）
///
/// zip 默认走纯 Dart 随机访问（无进程开销），rar/7z 走 7z.exe。
class ArchiveService {
  final SettingsService settings;
  final EntryCache entryCache;

  ArchiveService({
    required this.settings,
    required this.entryCache,
  });

  SevenZip? _sevenZipCache;
  String? _sevenZipPathFor;

  SevenZip? get _sevenZip {
    final p = settings.sevenZipPath;
    if (p.isEmpty) return null;
    if (_sevenZipPathFor != p || _sevenZipCache == null) {
      _sevenZipCache = SevenZip(p);
      _sevenZipPathFor = p;
    }
    return _sevenZipCache;
  }

  bool get sevenZipReady => _sevenZip != null && File(settings.sevenZipPath).existsSync();

  bool _useDartZip(ArchiveItem item) =>
      item.kind == ArchiveKind.zip && settings.useDartZipEngine;

  /// zip 中央目录缓存（LRU，最多 8 个包）
  final Map<String, ZipIndex> _zipIndexes = <String, ZipIndex>{};
  final List<String> _zipIndexOrder = <String>[];

  void _pushZipIndex(String path, ZipIndex idx) {
    _zipIndexes[path] = idx;
    _zipIndexOrder
      ..remove(path)
      ..add(path);
    while (_zipIndexOrder.length > 8) {
      _zipIndexes.remove(_zipIndexOrder.removeAt(0));
    }
  }

  Future<ZipIndex?> _peekZipIndex(String path) async {
    final cached = _zipIndexes[path];
    if (cached != null) {
      _zipIndexOrder
        ..remove(path)
        ..add(path);
      return cached;
    }
    return null;
  }

  /// 列出包内图片（优先读磁盘缓存）
  Future<List<ImageEntry>> listImages(ArchiveItem item) async {
    // 1) 磁盘缓存
    final cached = await entryCache.read(item.path, item.signature);
    if (cached != null) return cached;

    List<ImageEntry> entries;
    if (_useDartZip(item)) {
      try {
        final idx = await ZipReader.readIndex(item.path);
        _pushZipIndex(item.path, idx);
        entries = idx.images;
      } catch (e) {
        // 纯 Dart 引擎失败（加密 / 分卷 / 非常见算法）→ 回退 7-Zip
        final sz = _sevenZip;
        if (sz == null) rethrow;
        entries = await sz.listImages(item.path);
      }
    } else {
      final sz = _sevenZip;
      if (sz == null) {
        throw StateError(
            '未配置 7-Zip 路径，无法读取 ${item.name}。请在设置中指定 7z.exe。');
      }
      entries = await sz.listImages(item.path);
    }
    await entryCache.write(item.path, item.signature, entries);
    return entries;
  }

  /// 只读取一张图片的原始字节
  Future<Uint8List> readImageBytes(ArchiveItem item, ImageEntry entry) async {
    if (_useDartZip(item)) {
      var idx = await _peekZipIndex(item.path);
      if (idx == null) {
        try {
          idx = await ZipReader.readIndex(item.path);
          _pushZipIndex(item.path, idx);
        } catch (_) {
          idx = null;
        }
      }
      final zi = idx?.byName[entry.name];
      if (zi != null) {
        // 在后台 isolate 里 seek + inflate，主线程保持流畅
        return compute(zipReadEntryTask, ZipReadTaskArgs(item.path, zi));
      }
    }
    final sz = _sevenZip;
    if (sz == null) {
      throw StateError('未配置 7-Zip 路径，无法读取 ${entry.name}');
    }
    return sz.readEntryBytes(item.path, entry.name);
  }

  /// 读取原图用于大图预览（zip 直接走 dart，7z 走进程）
  Future<Uint8List> readFullBytes(ArchiveItem item, ImageEntry entry) =>
      readImageBytes(item, entry);
}
