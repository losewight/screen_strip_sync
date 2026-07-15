#include <cstdint>

#define ZEERAY_EXPORT __declspec(dllexport)

extern "C"
{
  ZEERAY_EXPORT int32_t zeeray_get_version()
  {
    return 100;
  }
}