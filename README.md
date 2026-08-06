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

## License

See repository license file when published.
