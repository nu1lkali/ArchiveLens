# ArchiveLens — 安装 C++ 生成工具（不含 Visual Studio IDE）
#
# 用法：右键「使用 PowerShell 运行」或以管理员身份执行
#   powershell -ExecutionPolicy Bypass -File tool\install_buildtools.ps1
#
# 为什么只装这些：
#   flutter_tools\lib\src\windows\visual_studio.dart 里写死了 vswhere 的 -requires：
#     - workload:  Microsoft.VisualStudio.Workload.VCTools   (Build Tools 的 C++ workload)
#     - component: Microsoft.VisualStudio.Component.VC.Tools.x86.x64  (MSVC v143)
#     - component: Microsoft.VisualStudio.Component.VC.CMake.Project  (VS 自带 cmake.exe)
#   再加一个 Windows SDK（C++ 编译需要 windows.h 等头文件和库）。
#   其余 VS IDE 外壳 / .NET 全套 / 测试工具 / 分析器一律不装。

$ErrorActionPreference = 'Stop'

$InstallPath = 'C:\VS2022BT'
$Bootstrapper = Join-Path $env:TEMP 'vs_buildtools.exe'

# 如果你的 C 盘很紧张，可以把 $InstallPath 改到别的盘（例如 'D:\VS2022BT'）
# 注意：Windows SDK 无论如何都会装到 C:\Program Files (x86)\Windows Kits

Write-Host '==> 下载 VS Build Tools 2022 引导程序（约 3MB）...' -ForegroundColor Cyan
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
if (-not (Test-Path $Bootstrapper)) {
    try {
        # -UseBasicParsing 避开 PS 5.1 依赖 IE 引擎导致的 "response content cannot be parsed"
        Invoke-WebRequest -Uri 'https://aka.ms/vs/17/release/vs_buildtools.exe' `
                          -OutFile $Bootstrapper -UseBasicParsing
    } catch {
        Write-Host '' -ForegroundColor Yellow
        Write-Host "自动下载失败：$($_.Exception.Message)" -ForegroundColor Yellow
        Write-Host '请手动下载 https://aka.ms/vs/17/release/vs_buildtools.exe' -ForegroundColor Yellow
        Write-Host "并放到 $Bootstrapper ，然后重新运行本脚本。" -ForegroundColor Yellow
        exit 1
    }
} else {
    Write-Host "    已存在 $Bootstrapper ，跳过下载" -ForegroundColor DarkGray
}

# 注意组件 ID 的格式（踩过坑）：
#   正确：Microsoft.VisualStudio.Component.Windows11SDK.22621
#   错误：Microsoft.VisualStudio.Component.Windows11SDK.10.0.22621.0   ← 安装器会静默跳过！
# 版本号短格式才有效。可用版本可用这条命令确认：
#   (Get-Content "$env:ProgramData\Microsoft\VisualStudio\Packages\_Instances\*\catalog.json") -match 'Windows1[01]SDK\.\d+'
$Components = @(
    'Microsoft.VisualStudio.Workload.VCTools'
    'Microsoft.VisualStudio.Component.VC.Tools.x86.x64'
    'Microsoft.VisualStudio.Component.Windows11SDK.22621'
    'Microsoft.VisualStudio.Component.VC.CMake.Project'
)

$Args = @('--wait', '--passive', '--norestart', '--nocache')
foreach ($c in $Components) { $Args += "--add"; $Args += $c }
$Args += '--installPath'; $Args += $InstallPath

Write-Host '==> 开始安装（约 2.5~3GB 下载，请耐心）...' -ForegroundColor Cyan
Write-Host "    组件: $($Components -join ', ')" -ForegroundColor DarkGray
& $Bootstrapper $Args
if ($LASTEXITCODE -ne 0) {
    Write-Host "安装失败，退出码 $LASTEXITCODE" -ForegroundColor Red
    exit $LASTEXITCODE
}

Write-Host ''
Write-Host '==> 校验：vswhere 能否找到满足 Flutter 要求的工具链' -ForegroundColor Cyan
$vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
if (Test-Path $vswhere) {
    # 用数组 + splatting，避免反引号续行在编码异常时踩坑
    $vsArgs = @(
        '-latest', '-products', '*', '-format', 'value',
        '-requires',
        'Microsoft.VisualStudio.Workload.VCTools',
        'Microsoft.VisualStudio.Component.VC.Tools.x86.x64',
        'Microsoft.VisualStudio.Component.VC.CMake.Project',
        '-property', 'installationPath'
    )
    $found = & $vswhere @vsArgs
    if ($found) {
        Write-Host "    OK: $found" -ForegroundColor Green
    } else {
        Write-Host '    vswhere 未匹配到，请确认组件是否装全' -ForegroundColor Yellow
    }
} else {
    Write-Host '    未找到 vswhere.exe' -ForegroundColor Yellow
}

Write-Host ''
Write-Host '==> 校验 Windows SDK 头文件/库是否真的装上了' -ForegroundColor Cyan
# 只装到 Microsoft.VisualStudio.Component.Windows10SDK（无版本号）时，
# Windows Kits\10 下只会有 Catalogs 和 Redist，缺 Include/Lib —— 编译阶段必炸，这里提前拦住。
$kitRoot = Join-Path ${env:ProgramFiles(x86)} 'Windows Kits\10'
$sdkOk = (Test-Path (Join-Path $kitRoot 'Include')) -and (Test-Path (Join-Path $kitRoot 'Lib'))
if ($sdkOk) {
    $ver = Get-ChildItem (Join-Path $kitRoot 'Include') -Directory | Select-Object -ExpandProperty Name
    Write-Host "    OK: $kitRoot\Include  [$($ver -join ', ')]" -ForegroundColor Green
} else {
    Write-Host '    缺少 Include / Lib，SDK 主体没装上！' -ForegroundColor Red
    Write-Host '    请补装（把 22621 换成你机器上实际支持的版本）：' -ForegroundColor Yellow
    Write-Host '        & "$env:TEMP\vs_buildtools.exe" --wait --passive --installPath C:\VS2022BT --add Microsoft.VisualStudio.Component.Windows11SDK.22621' -ForegroundColor Yellow
    Write-Host '    若 22621 无效，试 26100 或 19041（确认可用版本见脚本顶部注释）。' -ForegroundColor Yellow
}

Write-Host ''
Write-Host '完成。请重新打开一个终端（刷新环境变量），然后执行：' -ForegroundColor Green
Write-Host '    cd D:\project\archive_lens' -ForegroundColor White
Write-Host '    flutter doctor -v' -ForegroundColor White
Write-Host '    flutter build windows --release' -ForegroundColor White
