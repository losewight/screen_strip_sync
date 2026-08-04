#pragma once

// HKCU\...\Run\ZeerayHelper = "<helper绝对路径>" --autostart
// helper 是唯一写方；JSON startOnBoot 为逻辑真源。

// 按 enabled 写或删注册表项
bool autostart_apply(bool enabled);

// 启动时：对照当前 GetModuleFileName，纠漂移 / 补缺 / 清孤儿
bool autostart_reconcile(bool enabled_from_json);
