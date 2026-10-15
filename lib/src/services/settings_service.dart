import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'seven_zip.dart';

/// 全局设置（持久化到 SharedPreferences）
class SettingsService extends ChangeNotifier {
  static const _kSevenZip = 'seven_zip_path';
  static const _kZipEngine = 'zip_engine'; // 'dart' | '7z'
  static const _kThumbWidth = 'thumb_width';
  static const _kConcurrency = 'concurrency';
  static const _kMemCache = 'mem_cache_count';
  static const _kDiskCache = 'disk_cache_enabled';
  static const _kDiskCacheMax = 'disk_cache_max_files';
  static const _kRecycleBin = 'use_recycle_bin';
  static const _kGridExtent = 'grid_extent';
  static const _kViewerWidth = 'viewer_width';
  static const _kImageSort = 'image_sort';
  static const _kImageSortAsc = 'image_sort_asc';

  SettingsService._(this._prefs);

  final SharedPreferences _prefs;

  static Future<SettingsService> load() async {
    final prefs = await SharedPreferences.getInstance();
    final s = SettingsService._(prefs);
    // 首次运行时自动探测 7z.exe
    if ((prefs.getString(_kSevenZip) ?? '').isEmpty) {
      final detected = SevenZip.detect();
      if (detected != null) {
        await prefs.setString(_kSevenZip, detected);
      }
    }
    return s;
  }

  /// 7-Zip 可执行文件路径
  String get sevenZipPath => _prefs.getString(_kSevenZip) ?? '';

  Future<void> setSevenZipPath(String v) async {
    await _prefs.setString(_kSevenZip, v);
    notifyListeners();
  }

  /// zip 使用纯 Dart 引擎（快）还是 7-Zip 引擎（对非 UTF-8 文件名更友好）
  bool get useDartZipEngine => (_prefs.getString(_kZipEngine) ?? 'dart') == 'dart';

  Future<void> setUseDartZipEngine(bool v) async {
    await _prefs.setString(_kZipEngine, v ? 'dart' : '7z');
    notifyListeners();
  }

  /// 缩略图解码宽度（px）
  int get thumbWidth => _prefs.getInt(_kThumbWidth) ?? 320;

  Future<void> setThumbWidth(int v) async {
    await _prefs.setInt(_kThumbWidth, v);
    notifyListeners();
  }

  /// 并发读取数量
  int get concurrency => _prefs.getInt(_kConcurrency) ?? 4;

  Future<void> setConcurrency(int v) async {
    await _prefs.setInt(_kConcurrency, v);
    notifyListeners();
  }

  /// 内存 LRU 缓存的 ui.Image 数量上限
  int get memoryCacheCount => _prefs.getInt(_kMemCache) ?? 500;

  Future<void> setMemoryCacheCount(int v) async {
    await _prefs.setInt(_kMemCache, v);
    notifyListeners();
  }

  bool get diskCacheEnabled => _prefs.getBool(_kDiskCache) ?? true;

  Future<void> setDiskCacheEnabled(bool v) async {
    await _prefs.setBool(_kDiskCache, v);
    notifyListeners();
  }

  int get diskCacheMaxFiles => _prefs.getInt(_kDiskCacheMax) ?? 4000;

  Future<void> setDiskCacheMaxFiles(int v) async {
    await _prefs.setInt(_kDiskCacheMax, v);
    notifyListeners();
  }

  /// 删除时是否先送回收站
  bool get useRecycleBin => _prefs.getBool(_kRecycleBin) ?? false;

  Future<void> setUseRecycleBin(bool v) async {
    await _prefs.setBool(_kRecycleBin, v);
    notifyListeners();
  }

  /// 网格单元最大宽度
  double get gridExtent => _prefs.getDouble(_kGridExtent) ?? 200.0;

  Future<void> setGridExtent(double v) async {
    await _prefs.setDouble(_kGridExtent, v);
    notifyListeners();
  }

  /// 大图预览的最大解码宽度（0 = 原图）
  int get viewerWidth => _prefs.getInt(_kViewerWidth) ?? 2000;

  Future<void> setViewerWidth(int v) async {
    await _prefs.setInt(_kViewerWidth, v);
    notifyListeners();
  }

  // ---------------- 图片网格排序（会被记忆） ----------------

  /// 0=名称 1=日期 2=随机，取值见 `ImageSort`
  int get imageSortIndex => _prefs.getInt(_kImageSort) ?? 0;

  Future<void> setImageSortIndex(int v) async {
    await _prefs.setInt(_kImageSort, v);
    notifyListeners();
  }

  bool get imageSortAscending => _prefs.getBool(_kImageSortAsc) ?? true;

  Future<void> setImageSortAscending(bool v) async {
    await _prefs.setBool(_kImageSortAsc, v);
    notifyListeners();
  }
}
