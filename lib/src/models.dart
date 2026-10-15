import 'dart:io';

/// 压缩包类型
enum ArchiveKind { zip, rar, sevenZ, unknown }

/// 标记状态：正常 / 喜欢 / 不喜欢（待删除）
enum MarkStatus { normal, liked, disliked }

/// 支持的图片扩展名（小写，带点）
const Set<String> kImageExtensions = {
  '.jpg',
  '.jpeg',
  '.png',
  '.webp',
  '.bmp',
  '.gif',
  '.jfif',
  '.avif',
  '.heic',
};

/// 支持的压缩包扩展名（小写，带点）
const Set<String> kArchiveExtensions = {
  '.zip',
  '.rar',
  '.7z',
  '.cbz',
  '.cbr',
  '.cb7',
};

/// 根据文件名判断压缩包类型
ArchiveKind kindOfPath(String path) {
  final ext = _ext(path);
  switch (ext) {
    case '.zip':
    case '.cbz':
      return ArchiveKind.zip;
    case '.rar':
    case '.cbr':
      return ArchiveKind.rar;
    case '.7z':
    case '.cb7':
      return ArchiveKind.sevenZ;
    default:
      return ArchiveKind.unknown;
  }
}

bool isArchiveFile(String path) => kArchiveExtensions.contains(_ext(path));

bool isImageName(String name) => kImageExtensions.contains(_ext(name));

String _ext(String p) {
  final i = p.lastIndexOf('.');
  if (i < 0) return '';
  return p.substring(i).toLowerCase();
}

/// 压缩包内的一张图片。
///
/// 注意：这里**只保存元信息**（文件名 + 解压后大小 + 修改时间），不保存任何像素数据，
/// 因此 1000 张图 × 1000 个包 的索引也只有几十 MB 量级，且大部分是字符串。
class ImageEntry {
  /// 包内完整路径（分隔符可能是 `/` 或 `\`，取决于压缩包）
  final String name;

  /// 解压后大小（字节）。-1 表示未知
  final int size;

  /// 包内记录的修改时间。解析不到时为 null
  final DateTime? modified;

  const ImageEntry({
    required this.name,
    required this.size,
    this.modified,
  });

  /// 用于显示的文件名
  String get baseName {
    final n = name.replaceAll('\\', '/');
    final i = n.lastIndexOf('/');
    return i < 0 ? n : n.substring(i + 1);
  }

  Map<String, dynamic> toJson() => {
        'n': name,
        's': size,
        if (modified != null) 'm': modified!.millisecondsSinceEpoch,
      };

  factory ImageEntry.fromJson(Map<dynamic, dynamic> m) => ImageEntry(
        name: m['n'] as String,
        size: (m['s'] as num).toInt(),
        modified: m['m'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch((m['m'] as num).toInt()),
      );

  @override
  String toString() => 'ImageEntry($name, $size)';
}

/// 右侧图片网格的排序方式
enum ImageSort { name, date, random }

/// 一个压缩包的索引记录。
///
/// [images] 默认为 null —— 只有在用户点开这个包时才惰性列出包内文件，
/// 这样扫描 1000+ 个包时不会去做 1000 次内部列表读取。
class ArchiveItem {
  /// 绝对（或 UNC）路径
  final String path;

  /// 文件名（含扩展名）
  final String name;

  final ArchiveKind kind;

  /// 压缩包自身占用的磁盘大小
  final int fileSize;

  final DateTime modified;

  /// 包内图片列表，null = 尚未列出
  List<ImageEntry>? _images;

  /// 标记状态（正常 / 喜欢 / 待删）
  MarkStatus status = MarkStatus.normal;

  /// 列出失败时的错误信息
  String? listError;

  /// 是否正在列出包内图片
  bool listing = false;

  ArchiveItem({
    required this.path,
    required this.name,
    required this.kind,
    required this.fileSize,
    required this.modified,
    List<ImageEntry>? images,
    this.status = MarkStatus.normal,
  }) : _images = images;

  List<ImageEntry>? get images => _images;

  int get imageCount => _images?.length ?? -1;

  bool get isListed => _images != null;

  void setImages(List<ImageEntry> v) {
    _images = v;
    listError = null;
    listing = false;
  }

  /// 用于磁盘缓存签名：大小 + 修改时间，用于判断缓存是否过期
  String get signature => '${fileSize}_${modified.millisecondsSinceEpoch}';

  /// 磁盘上的父目录（用于分组显示）
  String get parentDir {
    final p = path.replaceAll('\\', '/');
    final i = p.lastIndexOf('/');
    return i < 0 ? p : p.substring(0, i);
  }

  Map<String, dynamic> toJson() => {
        'p': path,
        'n': name,
        'k': kind.index,
        's': fileSize,
        'm': modified.millisecondsSinceEpoch,
        'st': status.index,
      };

  factory ArchiveItem.fromJson(Map<dynamic, dynamic> m) => ArchiveItem(
        path: m['p'] as String,
        name: m['n'] as String,
        kind: ArchiveKind.values[(m['k'] as num).toInt()],
        fileSize: (m['s'] as num).toInt(),
        modified:
            DateTime.fromMillisecondsSinceEpoch((m['m'] as num).toInt()),
        status: MarkStatus.values[(m['st'] as num? ?? 0).toInt()],
      );

  /// 从文件系统实体快速构造
  static ArchiveItem fromFile(File f, FileStat st) {
    final p = f.path;
    final n = p.replaceAll('\\', '/');
    final i = n.lastIndexOf('/');
    return ArchiveItem(
      path: p,
      name: i < 0 ? n : n.substring(i + 1),
      kind: kindOfPath(p),
      fileSize: st.size,
      modified: st.modified,
    );
  }
}
