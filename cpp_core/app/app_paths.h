#pragma once

#include <cstddef>

// 可写数据目录：%LocalAppData%\Screen Strip Sync\
// 与安装位置无关；配置 / helper.log 均在此。

/// 确保数据目录存在；宽字符路径（内部用）。
bool data_dir_wide(wchar_t *out, size_t cap);

/// UTF-8 数据目录；失败返回 false。
bool data_dir_utf8(char *out, size_t cap);

/// `%LocalAppData%\Screen Strip Sync\helper.log`
bool helper_log_path(char *out, size_t cap);

/// `%LocalAppData%\Screen Strip Sync\screen_strip_sync_config.json`
bool config_file_path(char *out, size_t cap);

/// 若 AppData 无配置而 exe 旁有旧文件，复制 JSON / helper.log / crash.log。
void data_dir_migrate_from_exe_dir();
