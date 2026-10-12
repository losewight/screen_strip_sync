#pragma once

#include "dxgi_capture.h"

#include <dxgi1_2.h>

// 唯一选屏点；写入当前 g_output_info。调用方负责 Release *out。
DxgiErr dxgi_select_capture_output(IDXGIAdapter *adapter, IDXGIOutput1 **out);

// 配置要抓的屏（set 后未 init 前可读）；shutdown 不清。
const char *dxgi_wanted_output();

// 最近一次 select 写入的结果；device_name 空表示尚未选中。
const CaptureOutputInfo &dxgi_selected_output_info();

void dxgi_clear_output_info();
void dxgi_log_capture_output();
