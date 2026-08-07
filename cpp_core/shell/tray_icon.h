#pragma once

// 隐藏顶层窗：电源广播 + 托盘图标/菜单（合并原 power_watch）
void tray_start();
// 摘托盘图标并结束托盘线程消息循环（可重入）
void tray_stop();
