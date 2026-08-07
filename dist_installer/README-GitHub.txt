GitHub Release 产物（本目录 dist_installer/）

- ScreenStripSync-*-windows-x64-Setup.exe  … Inno 安装包（推荐）
- ScreenStripSync-*-windows-x64.zip         … 绿色版（解压后运行后台服务；文件名 helper.exe）
- SHA256SUMS.txt

说明：
- 本项目无代码签名，Windows 可能提示「未知发布者」，杀毒软件也可能误报。
- 关于 32 位（x86）：当前 Flutter stable（桌面 Windows）只提供 x64 引擎与工具链，
  本项目依赖 DXGI 抓屏 + Flutter 界面，无法产出可用的 Windows x86 安装包。
  请在 64 位 Windows 10 及以上使用。
