Release 产物（本目录）

- ScreenStripSync-1.0.2-windows-x64-Setup.exe  … Inno 安装包（有 ISCC 时）
- ScreenStripSync-1.0.2-windows-x64.zip         … 绿色版（解压后运行 helper.exe）
- SHA256SUMS.txt

关于 32 位（x86）：
当前 Flutter stable（桌面 Windows）只提供 x64 引擎与工具链，本项目依赖 DXGI Desktop
Duplication + Flutter UI，无法产出可用的 Windows x86 安装包。请在 64 位 Windows 10/11 上使用。