# Screen Strip Sync

Windows PC **screen-to-LED** sync for Mijia light-chasing LED strips (unofficial).

Captures the display (DXGI), samples colors, and drives a USB serial LED strip from a always-on `helper.exe` tray process. The Flutter UI is optional and can be closed without stopping the lights.

## Compatibility

Unofficial driver for **米家追光灯带 Pro** (and similar CH340-based strips often sold under third-party names).  
Not affiliated with Xiaomi, Mijia, Signify, or Philips. Those names and trademarks belong to their respective owners.

## Build (dev)

```text
cmake --build cpp_core/build --config Release
flutter build windows --release
```

Run `helper.exe` (tray). UI binary: `screen_strip_sync.exe`.

## Reporting bugs

1. In the UI open **设置 → 导出诊断信息**. This writes `screen_strip_sync_diag_*.txt` to your Desktop (local only; nothing is uploaded).
2. Open a GitHub issue with the **Bug report** template and attach that file.
3. You can also open the helper log folder from the same settings page (`helper.log` next to `helper.exe`).

Do not paste full screen captures into the diagnostics flow—the export contains config, status, and log tails only.

## License

See repository license file when published.
