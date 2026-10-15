import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';

import '../models.dart';
import '../services/archive_service.dart';
import '../services/delete_service.dart';
import '../services/entry_cache.dart';
import '../services/index_store.dart';
import '../services/scan_service.dart';
import '../services/settings_service.dart';
import '../services/thumbnail_service.dart';

enum LibraryFilter { all, liked, disliked, unmarked }

enum SortMode { name, size, count, modified }

/// 全局状态管理（Provider）。
///
/// 持有：
///   - 扫描得到的压缩包索引列表
///   - 每个包的标记状态
///   - 当前打开的包 + 包内图片
///   - 批量勾选集合
class LibraryController extends ChangeNotifier {
  final SettingsService settings;

  late ArchiveService archiveService;
  late EntryCache entryCache;
  ThumbnailService? thumbnailService;
  late IndexStore indexStore;

  final ScanService _scanService = ScanService();
  StreamSubscription? _scanSub;

  LibraryController(this.settings);

  // ---------------- 基础状态 ----------------
  String root = '';
  final List<ArchiveItem> _all = <ArchiveItem>[];
  final Set<String> _selected = <String>{};

  bool scanning = false;
  int dirsScanned = 0;
  int filesSeen = 0;
  String? errorMessage;
  String statusMessage = '请选择要扫描的根目录';

  ArchiveItem? current;

  String search = '';
  LibraryFilter filter = LibraryFilter.all;
  SortMode sortMode = SortMode.name;
  bool sortAscending = true;

  /// 右侧图片网格的排序方式（持久化在 SettingsService 里，重启自动恢复）
  ImageSort get imageSort {
    final i = settings.imageSortIndex;
    return i >= 0 && i < ImageSort.values.length ? ImageSort.values[i] : ImageSort.name;
  }

  bool get imageSortAscending => settings.imageSortAscending;

  /// 随机排序的种子。用固定种子保证重建 Widget 时顺序不乱
  int imageSortSeed = 1;

  /// 每次切换压缩包都会自增，用于让「上一包还没加载完的缩略图」作废
  int generation = 0;

  Timer? _saveTimer;

  List<ArchiveItem> get all => List.unmodifiable(_all);

  Set<String> get selected => _selected;

  int get totalCount => _all.length;

  int get likedCount =>
      _all.where((e) => e.status == MarkStatus.liked).length;

  int get dislikedCount =>
      _all.where((e) => e.status == MarkStatus.disliked).length;

  int get totalSize => _all.fold(0, (a, b) => a + b.fileSize);

  // ---------------- 初始化 ----------------
  Future<void> init() async {
    final base = await getApplicationSupportDirectory();
    final dir = Directory('${base.path}${Platform.pathSeparator}archive_lens');
    entryCache = await EntryCache.open(dir);
    indexStore = await IndexStore.open(dir);
    archiveService = ArchiveService(settings: settings, entryCache: entryCache);
    thumbnailService = await ThumbnailService.create(
      settings: settings,
      archiveService: archiveService,
      baseDir: dir,
    );

    // 恢复上次的扫描结果
    final snap = await indexStore.load();
    if (snap != null && snap.items.isNotEmpty) {
      root = snap.root;
      _all
        ..clear()
        ..addAll(snap.items);
      statusMessage =
          '已载入上次的索引（${_all.length} 个包），可点击「重新扫描」刷新';
      notifyListeners();
      unawaited(_verifyExistence());
    }
    settings.addListener(_onSettingsChanged);
  }

  void _onSettingsChanged() {
    // 只需要让 UI 刷新：ArchiveService 每次读取时都会重新读 settings
    // （7z 路径 / zip 引擎都做了自动比对），不需要重建服务，
    // 否则每次改排序都会白白丢掉 zip 中央目录缓存。
    notifyListeners();
  }

  /// 后台校验文件是否还存在，移除已不存在的记录
  Future<void> _verifyExistence() async {
    final missing = <String>{};
    for (final item in _all) {
      if (!await File(item.path).exists()) missing.add(item.path);
    }
    if (missing.isEmpty) return;
    _all.removeWhere((e) => missing.contains(e.path));
    _selected.removeWhere(missing.contains);
    if (current != null && missing.contains(current!.path)) {
      current = null;
    }
    statusMessage = '已移除 ${missing.length} 个不存在的记录';
    notifyListeners();
    _scheduleSave();
  }

  void _deferClearMemory() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      thumbnailService?.clearMemory();
    });
  }

  @override
  void dispose() {
    _scanSub?.cancel();
    _saveTimer?.cancel();
    settings.removeListener(_onSettingsChanged);
    thumbnailService?.dispose();
    super.dispose();
  }

  // ---------------- 扫描 ----------------
  Future<void> scan(String path) async {
    await _scanSub?.cancel();
    root = path;
    _all.clear();
    _selected.clear();
    current = null;
    _deferClearMemory();
    scanning = true;
    dirsScanned = 0;
    filesSeen = 0;
    errorMessage = null;
    statusMessage = '正在扫描 $path ...';
    notifyListeners();

    // 保留已有的标记状态（按路径）
    final oldMarks = <String, MarkStatus>{};
    final snap = await indexStore.load();
    if (snap != null) {
      for (final i in snap.items) {
        if (i.status != MarkStatus.normal) oldMarks[i.path] = i.status;
      }
    }

    var lastNotify = DateTime.now().millisecondsSinceEpoch;
    _scanSub = _scanService.scan(path).listen(
      (u) {
        final it = u.item;
        if (it != null) {
          it.status = oldMarks[it.path] ?? MarkStatus.normal;
          _all.add(it);
        }
        dirsScanned = u.dirsScanned;
        filesSeen = u.filesSeen;

        // 限流刷新：最多每 200ms 通知一次，避免列表疯狂重建
        final now = DateTime.now().millisecondsSinceEpoch;
        if (now - lastNotify > 200) {
          lastNotify = now;
          statusMessage = '扫描中：${_all.length} 个包 / $dirsScanned 个目录';
          notifyListeners();
        }
      },
      onError: (e) {
        scanning = false;
        errorMessage = '扫描出错：$e';
        statusMessage = '扫描失败';
        notifyListeners();
      },
      onDone: () {
        scanning = false;
        statusMessage =
            '扫描完成：共 ${_all.length} 个压缩包，遍历 $dirsScanned 个目录 / $filesSeen 个文件';
        notifyListeners();
        _scheduleSave();
      },
      cancelOnError: true,
    );
  }

  void cancelScan() {
    _scanService.cancel();
    _scanSub?.cancel();
    scanning = false;
    statusMessage = '已取消扫描（保留已找到的 ${_all.length} 个包）';
    notifyListeners();
    _scheduleSave();
  }

  // ---------------- 过滤 / 排序 ----------------
  List<ArchiveItem> get visible {
    final q = search.trim().toLowerCase();
    final list = _all.where((e) {
      if (q.isNotEmpty && !e.name.toLowerCase().contains(q)) return false;
      switch (filter) {
        case LibraryFilter.all:
          return true;
        case LibraryFilter.liked:
          return e.status == MarkStatus.liked;
        case LibraryFilter.disliked:
          return e.status == MarkStatus.disliked;
        case LibraryFilter.unmarked:
          return e.status == MarkStatus.normal;
      }
    }).toList();

    int cmpName(ArchiveItem a, ArchiveItem b) =>
        a.name.toLowerCase().compareTo(b.name.toLowerCase());

    list.sort((a, b) {
      int c;
      switch (sortMode) {
        case SortMode.name:
          c = cmpName(a, b);
          break;
        case SortMode.size:
          c = a.fileSize.compareTo(b.fileSize);
          break;
        case SortMode.count:
          c = a.imageCount.compareTo(b.imageCount);
          break;
        case SortMode.modified:
          c = a.modified.compareTo(b.modified);
          break;
      }
      return sortAscending ? c : -c;
    });
    return list;
  }

  /// 当前压缩包按 [imageSort] 排好序后的图片列表（带缓存，避免每帧重排）
  List<ImageEntry> get orderedImages {
    final item = current;
    final src = item?.images;
    if (item == null || src == null) return const <ImageEntry>[];

    final key = '${item.path}|${src.length}|${imageSort.index}'
        '|$imageSortAscending|$imageSortSeed';
    if (key == _orderedKey && _orderedCache != null) return _orderedCache!;

    final sorted = _sortImages(src);
    _orderedKey = key;
    _orderedCache = sorted;
    return sorted;
  }

  String? _orderedKey;
  List<ImageEntry>? _orderedCache;

  List<ImageEntry> _sortImages(List<ImageEntry> src) {
    final list = List<ImageEntry>.of(src);
    switch (imageSort) {
      case ImageSort.name:
        list.sort((a, b) => _naturalCompare(a.name, b.name));
        break;
      case ImageSort.date:
        final fallback = DateTime.fromMillisecondsSinceEpoch(0);
        list.sort((a, b) =>
            (a.modified ?? fallback).compareTo(b.modified ?? fallback));
        break;
      case ImageSort.random:
        // 固定种子 → 同一 seed 下顺序稳定，滚动/重建不会跳变
        list.shuffle(Random(imageSortSeed));
        break;
    }
    if (!imageSortAscending && imageSort != ImageSort.random) {
      return list.reversed.toList(growable: false);
    }
    return list;
  }

  void setImageSort(ImageSort s) {
    if (imageSort == s) return;
    unawaited(settings.setImageSortIndex(s.index));
    notifyListeners();
  }

  void setImageSortAscending(bool asc) {
    if (imageSortAscending == asc) return;
    unawaited(settings.setImageSortAscending(asc));
    notifyListeners();
  }

  /// 换一批随机顺序
  void reshuffleImages() {
    unawaited(settings.setImageSortIndex(ImageSort.random.index));
    imageSortSeed = DateTime.now().microsecondsSinceEpoch & 0x7FFFFFFF;
    notifyListeners();
  }

  void setSearch(String v) {
    search = v;
    notifyListeners();
  }

  void setFilter(LibraryFilter f) {
    filter = f;
    notifyListeners();
  }

  void setSort(SortMode m, {bool? asc}) {
    if (asc != null) sortAscending = asc;
    if (m == sortMode && asc == null) {
      sortAscending = !sortAscending;
    } else {
      sortMode = m;
    }
    notifyListeners();
  }

  // ---------------- 打开压缩包 ----------------
  Future<void> openArchive(ArchiveItem item) async {
    if (current?.path == item.path && item.isListed) return;
    current = item;
    generation++; // 让旧包的缩略图加载作废
    // 等新一帧构建完再释放旧包的缩略图，避免仍在上屏的 ui.Image 被 dispose
    _deferClearMemory();
    item.listing = true;
    item.listError = null;
    statusMessage = '正在列出 ${item.name} 的内容...';
    notifyListeners();

    try {
      final entries = await archiveService.listImages(item);
      item.setImages(entries);
      _orderedKey = null;
      _orderedCache = null;
      statusMessage = '${item.name}：${entries.length} 张图片';
    } catch (e) {
      item.listing = false;
      item.listError = e.toString();
      statusMessage = '列出失败：${item.name} → $e';
    }
    notifyListeners();
  }

  /// 在当前过滤结果里打开上/下一个压缩包
  Future<void> openRelative(int delta) async {
    final list = visible;
    if (list.isEmpty) return;
    final idx = current == null
        ? -1
        : list.indexWhere((e) => e.path == current!.path);
    final next =
        idx < 0 ? 0 : (idx + delta).clamp(0, list.length - 1).toInt();
    if (next == idx) return;
    await openArchive(list[next]);
  }

  /// 自然排序：img2 < img10
  static int _naturalCompare(String a, String b) {
    var i = 0;
    var j = 0;
    while (i < a.length && j < b.length) {
      final ca = a.codeUnitAt(i);
      final cb = b.codeUnitAt(j);
      if (_isDigit(ca) && _isDigit(cb)) {
        var na = 0;
        var nb = 0;
        while (i < a.length && _isDigit(a.codeUnitAt(i))) {
          na = na * 10 + (a.codeUnitAt(i) - 48);
          i++;
        }
        while (j < b.length && _isDigit(b.codeUnitAt(j))) {
          nb = nb * 10 + (b.codeUnitAt(j) - 48);
          j++;
        }
        if (na != nb) return na - nb;
      } else {
        final la = a[i].toLowerCase();
        final lb = b[j].toLowerCase();
        if (la != lb) return la.compareTo(lb);
        i++;
        j++;
      }
    }
    return a.length - b.length;
  }

  static bool _isDigit(int c) => c >= 48 && c <= 57;

  // ---------------- 标记 ----------------
  void setStatus(ArchiveItem item, MarkStatus s) {
    item.status = item.status == s ? MarkStatus.normal : s;
    notifyListeners();
    _scheduleSave();
  }

  void toggleSelection(String path) {
    if (_selected.contains(path)) {
      _selected.remove(path);
    } else {
      _selected.add(path);
    }
    notifyListeners();
  }

  void selectAllVisible() {
    final vis = visible.map((e) => e.path);
    _selected.addAll(vis);
    notifyListeners();
  }

  void clearSelection() {
    _selected.clear();
    notifyListeners();
  }

  void markSelected(MarkStatus s) {
    if (_selected.isEmpty) return;
    for (final item in _all) {
      if (_selected.contains(item.path)) item.status = s;
    }
    notifyListeners();
    _scheduleSave();
  }

  /// 把所有「不喜欢」重置为正常
  void clearAllMarks() {
    for (final item in _all) {
      item.status = MarkStatus.normal;
    }
    notifyListeners();
    _scheduleSave();
  }

  // ---------------- 删除 ----------------
  /// 一键清理：删除所有标记为「不喜欢」的压缩包
  Future<String> deleteDisliked({bool? toRecycleBin}) async {
    final targets =
        _all.where((e) => e.status == MarkStatus.disliked).toList();
    return _deleteItems(targets, toRecycleBin: toRecycleBin);
  }

  /// 删除当前勾选的压缩包
  Future<String> deleteSelected({bool? toRecycleBin}) async {
    final targets =
        _all.where((e) => _selected.contains(e.path)).toList();
    return _deleteItems(targets, toRecycleBin: toRecycleBin);
  }

  Future<String> deleteOne(ArchiveItem item, {bool? toRecycleBin}) =>
      _deleteItems(<ArchiveItem>[item], toRecycleBin: toRecycleBin);

  Future<String> _deleteItems(List<ArchiveItem> targets,
      {bool? toRecycleBin}) async {
    if (targets.isEmpty) return '没有需要删除的压缩包';
    final recycle = toRecycleBin ?? settings.useRecycleBin;

    var ok = 0;
    var fail = 0;
    final failedPaths = <String>[];

    for (final item in targets) {
      final r = await DeleteService.deleteFile(
        item.path,
        toRecycleBin: recycle,
      );
      if (r.ok) {
        ok++;
        _all.removeWhere((e) => e.path == item.path);
        _selected.remove(item.path);
        if (current?.path == item.path) current = null;
      } else {
        fail++;
        failedPaths.add(item.name);
        errorMessage = '${item.name}: ${r.message}';
      }
    }

    notifyListeners();
    _scheduleSave();

    final buf = StringBuffer('删除完成：成功 $ok 个');
    if (fail > 0) {
      buf.write('，失败 $fail 个');
      if (failedPaths.length <= 3) buf.write('（${failedPaths.join('、')}）');
    }
    return buf.toString();
  }

  // ---------------- 持久化 ----------------
  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(seconds: 2), () async {
      await indexStore.save(root, _all);
    });
  }

  Future<void> clearCache() async {
    await thumbnailService?.clearDiskCache();
    _deferClearMemory();
    statusMessage = '缩略图缓存已清空';
    notifyListeners();
  }
}
