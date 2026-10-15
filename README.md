# ArchiveLens

<div align="center">

**本地图片压缩包管理与筛选工具** · Flutter Windows 桌面端

不解压原包，直接浏览 zip / rar / 7z 里的图片，看完不想要的整包删掉

</div>

---

## 它能解决什么问题

你有上千个文件夹、每个里面一堆图片压缩包（每个包动辄上千张图），想快速翻一遍、把不要的整包删掉。
常规做法是挨个解压预览——又慢又占磁盘。

ArchiveLens **不解压任何东西**：直接读压缩包内部的目录结构，只在滚动到你眼前时才把那一张图解码成
缩略图。内存占用跟"包里有多少张图"基本无关。

## 特性

- **按需加载** —— 只在图片进入视口时才读取，滚动流畅，不爆内存
- **支持 zip / rar / 7z / cbz / cbr / cb7** —— zip 走内置引擎（无需外部程序），rar/7z 调用 7-Zip
- **不写临时文件** —— 单张图直接从压缩包流式读出，不落盘
- **本地 + 网络路径** —— 支持 `\\NAS\share` 这类 UNC 路径，也可以把文件夹拖到窗口上
- **标记与批量清理** —— 喜欢 / 待删标记，勾选多个批量操作，一键物理删除
- **大图预览** —— 点击放大，方向键翻页，滚轮缩放
- **三种排序** —— 名称（自然排序）/ 日期 / 随机，选择会被记住

## 快速开始

### 直接使用

从 Releases 下载 zip，解压后运行 `archive_lens.exe` 即可（绿色软件，无需安装）。

> 首次使用请在「设置」里确认 7-Zip 路径——**读取 rar / 7z 必须依赖它**，zip 则不需要。

### 从源码构建

前置：

| 依赖 | 说明 |
| --- | --- |
| Flutter SDK | 3.13+ |
| Visual Studio **Build Tools** 2022 | 只需 C++ 工具链，**不用装完整 VS IDE**。安装时勾选 `MSVC v143 生成工具`、`Windows 11 SDK`、`C++ CMake tools for Windows`、`C++ 桌面开发` workload |
| 7-Zip | 运行时依赖（rar / 7z） |

```bat
git clone <your-repo>
cd archive_lens

flutter pub get
flutter run -d windows            :: 调试运行
flutter build windows --release   :: 产物在 build\windows\runner\Release\
```

> Windows 上若 `flutter pub get` 报 `Cannot create link`，说明没开「开发者模式」。
> 设置 → 隐私和安全性 → 开发者模式，打开即可（或用管理员权限运行）。
> 更多环境问题见 [docs/BUILD_NOTES.md](docs/BUILD_NOTES.md)。

## 使用

### 扫描目录

左上角填路径后点「扫描」，或点 `···` 用文件夹对话框选，也支持直接填 UNC 路径。
最简单的办法：**把文件夹从资源管理器拖到窗口上**，会自动识别并开始扫描。

### 图片排序

右侧网格右上角切换，**选择会记住**：

| 方式 | 说明 |
| --- | --- |
| 名称 | 自然排序，`img2` 排在 `img10` 前面 |
| 日期 | 按包内记录的修改时间 |
| 随机 | 固定种子打乱，滚动时顺序稳定；点「换一批」换一批 |

### 快捷键

按 `F1` 随时查看（底部状态栏也有入口）。

| 按键 | 功能 | 按键 | 功能 |
| --- | --- | --- | --- |
| `Ctrl + O` | 选择根目录 | `L` | 标记喜欢 |
| `Ctrl + R` / `F5` | 重新扫描 | `D` / `Delete` | 标记待删 |
| `Ctrl + F` | 聚焦搜索框 | `Alt + ↑` / `↓` | 上一个 / 下一个包 |
| `Ctrl + A` | 全选当前列表 | `1` / `2` / `3` | 名称 / 日期 / 随机排序 |
| `Esc` | 清空选择 | `R` | 换一批随机顺序 |
| `Ctrl + Shift + D` | 一键清理所有待删 | `Ctrl + ,` | 设置 |
| `F1` / `?` | 快捷键帮助 | `←` `→` | 大图预览翻页 |

### 标记与清理

- 单包：右侧顶部「喜欢 / 标记待删 / 直接删除」
- 批量：左侧勾选多个 → 「批量标记」→ 底部「一键清理已标记」
- 删除默认**直接从磁盘抹掉**；设置在「设置」里可改成先送回收站（UNC 网络路径不支持，会自动降级）

## 性能

实测（1000 张图的包）：

| 指标 | 结果 |
| --- | --- |
| 解析包内目录 | 18 ms |
| 随机读取单张图 | 1.1 ms |
| 连读 500 张后的内存增量 | ≈ 4 MB（不累积） |

关键做法：zip 用自建的中央目录解析 + `seek` 随机访问，只 inflate 你要看的那一张（在后台 isolate 里做）；
rar/7z 用 `7z e -so` 把单张打到 stdout。缩略图走「内存 LRU → 磁盘缓存 → 压缩包源」三级，并限制并发。

## 已知限制

- **中文文件名**：ZIP 的编码取决于标志位，程序按 UTF-8 优先。老 GBK 包可能乱码，到「设置 → ZIP 解码引擎」关掉内置引擎改用 7-Zip
- **加密 / 分卷包**：内置引擎会失败并自动回退 7-Zip，两者都没有则报错
- **7z 单文件提取**：7-Zip 的文件参数按通配符解析，文件名含 `* ? [ ]` 时可能异常
- **回收站**：UNC 路径不支持，自动降级为彻底删除
- **rar/7z 速度**：每次要启动一个 7-Zip 进程，约 50~100ms/张，靠磁盘缓存和预取缓解

## 项目结构

```
lib/
├── main.dart                        入口
└── src/
    ├── models.dart                  数据模型
    ├── utils/format.dart            格式化、缓存 key
    ├── services/
    │   ├── zip_reader.dart          ★ 内置 ZIP 随机访问（中央目录 / ZIP64 / raw deflate）
    │   ├── seven_zip.dart           ★ 7z.exe 列表与单文件提取
    │   ├── archive_service.dart     引擎选择门面
    │   ├── thumbnail_service.dart   ★ 三级缓存 + 并发限流
    │   ├── scan_service.dart        递归扫描
    │   ├── drop_service.dart        拖放（配合 native 层）
    │   ├── delete_service.dart      删除 / 回收站
    │   ├── entry_cache.dart         包内条目缓存
    │   ├── index_store.dart         索引与标记持久化
    │   └── settings_service.dart    设置
    ├── state/library_controller.dart 全局状态
    └── ui/                          界面（主页面 / 侧边栏 / 网格 / 预览 / 设置 / 快捷键）
windows/runner/                      Windows 外壳（拖放支持在这里）
tool/                                压测与冒烟脚本
```

## 数据存放

| 内容 | 位置 |
| --- | --- |
| 扫描索引、标记 | `%APPDATA%\...\archive_lens\library.json` |
| 包内条目缓存 | `...\archive_lens\entries\` |
| 缩略图缓存 | `...\archive_lens\thumbs\` |

## 许可

[MIT](LICENSE) © ArchiveLens contributors
