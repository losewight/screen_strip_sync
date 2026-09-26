# Screen Strip Sync

Windows PC **screen-to-LED** host — an **unofficial, customized upper control system** for Mijia light-chasing ambience LED strips（米家追光氛围灯带）.

> **中文说明（默认）**：[README.md](./README.md)

Captures the display (DXGI), samples colors, and drives a USB serial LED strip from an always-on `helper.exe` tray process. The Flutter UI is optional and can be closed without stopping the lights.

## Compatibility

Unofficial customized host for **米家追光氛围灯带** / **米家追光灯带 Pro** (non-official naming).  
Validated on firmware `2.1.8_0039` only. Other models/firmware are not guaranteed.  
Not affiliated with Xiaomi, Mijia, Signify, or Philips. Those names and trademarks belong to their respective owners.

## Docs

| Doc | Topic |
| --- | --- |
| [README.md](./README.md) | Full Chinese README (default) |
| [reference/灯带串口通信协议.md](./reference/灯带串口通信协议.md) | Device serial protocol |
| [reference/进程间IPC协议.md](./reference/进程间IPC协议.md) | UI ↔ helper IPC |
| [reference/项目注意事项与踩坑.md](./reference/项目注意事项与踩坑.md) | Caveats & debugging |

## Build (dev)

```text
cmake --build cpp_core/build --config Release
flutter build windows --release
```

Run `helper.exe` (tray). UI binary: `screen_strip_sync.exe`. Keep them in the same folder for distribution.

Optional installer: `packaging/pack.ps1` (requires Inno Setup 6).

## Reporting bugs

1. In the UI open **设置 → 导出诊断信息**. This writes `screen_strip_sync_diag_*.txt` to your Desktop (local only; nothing is uploaded).
2. Open a GitHub issue with the **Bug report** template and attach that file.
3. You can also open the helper log folder from the same settings page (`helper.log` next to `helper.exe`).

Do not paste full screen captures into the diagnostics flow—the export contains config, status, and log tails only.

## Acknowledgments

Some ideas were informed by the open-source project [HyperHDR](https://github.com/awawa-dev/HyperHDR) (e.g. letterbox detection and dark-scene anti-flicker). This software is an independent implementation and is not affiliated with HyperHDR.

## License

[Apache License 2.0](./LICENSE).
