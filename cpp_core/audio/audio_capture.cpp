#include "audio_capture.h"

#include "ipc_loop.h"

#include <atomic>
#include <cmath>
#include <cstdio>
#include <cstring>
#include <mutex>
#include <thread>

#include <windows.h>

#include <Audioclient.h>
#include <mmdeviceapi.h>
#include <mmreg.h>
#include <ks.h>
#include <ksmedia.h>

#pragma comment(lib, "ole32.lib")
#pragma comment(lib, "uuid.lib")

namespace {

enum class SampleFmt { Float32, Pcm16, Pcm24, Pcm32, Unsupported };

struct WindowAcc {
  double sumsq = 0.0;
  uint64_t count = 0;
  float peak = 0.f;
};

struct PathState {
  IAudioClient *client = nullptr;
  IAudioCaptureClient *capture = nullptr;
  WAVEFORMATEX *mix = nullptr;
  SampleFmt fmt = SampleFmt::Unsupported;
  int channels = 0;
  UINT32 frame_bytes = 0;
  WindowAcc win{};
  bool active = false;
};

std::mutex g_mu;
WindowAcc g_sys_win{};
WindowAcc g_mic_win{};
std::atomic<MusicSource> g_source{MusicSource::System};
std::atomic<AudioStatus> g_status{AudioStatus::Ok};
std::atomic<bool> g_running{false};
std::atomic<bool> g_need_rebuild{true};
std::thread g_thread;

void set_status(AudioStatus st) {
  AudioStatus prev = g_status.exchange(st);
  if (prev != st) {
    printf("[audio] status %d -> %d\n", (int)prev, (int)st);
    // 为什么：让 UI 立刻看到 no_device / denied；无客户端时 push 为空操作
    ipc_push_runtime_status();
  }
}

SampleFmt detect_fmt(const WAVEFORMATEX *wfx) {
  if (wfx == nullptr)
    return SampleFmt::Unsupported;
  WORD tag = wfx->wFormatTag;
  WORD bits = wfx->wBitsPerSample;
  if (tag == WAVE_FORMAT_EXTENSIBLE &&
      wfx->cbSize >= 22) {
    const auto *ext = reinterpret_cast<const WAVEFORMATEXTENSIBLE *>(wfx);
    if (IsEqualGUID(ext->SubFormat, KSDATAFORMAT_SUBTYPE_IEEE_FLOAT))
      return SampleFmt::Float32;
    if (IsEqualGUID(ext->SubFormat, KSDATAFORMAT_SUBTYPE_PCM)) {
      bits = ext->Samples.wValidBitsPerSample
                 ? ext->Samples.wValidBitsPerSample
                 : wfx->wBitsPerSample;
      if (bits == 16)
        return SampleFmt::Pcm16;
      if (bits == 24)
        return SampleFmt::Pcm24;
      if (bits == 32)
        return SampleFmt::Pcm32;
    }
    return SampleFmt::Unsupported;
  }
  if (tag == WAVE_FORMAT_IEEE_FLOAT && bits == 32)
    return SampleFmt::Float32;
  if (tag == WAVE_FORMAT_PCM) {
    if (bits == 16)
      return SampleFmt::Pcm16;
    if (bits == 24)
      return SampleFmt::Pcm24;
    if (bits == 32)
      return SampleFmt::Pcm32;
  }
  return SampleFmt::Unsupported;
}

// 一帧多声道：取各声道绝对值的 max，累加到窗口
void accumulate_frames(WindowAcc *acc, const BYTE *data, UINT32 frames,
                       int channels, SampleFmt fmt, UINT32 /*frame_bytes*/,
                       bool silent) {
  if (acc == nullptr || frames == 0 || channels <= 0)
    return;
  if (silent || data == nullptr) {
    acc->count += frames;
    return;
  }
  for (UINT32 f = 0; f < frames; ++f) {
    float amp = 0.f;
    for (int c = 0; c < channels; ++c) {
      float v = 0.f;
      switch (fmt) {
      case SampleFmt::Float32: {
        const float *p =
            reinterpret_cast<const float *>(data) + f * channels + c;
        v = *p;
        break;
      }
      case SampleFmt::Pcm16: {
        const int16_t *p =
            reinterpret_cast<const int16_t *>(data) + f * channels + c;
        v = (float)*p / 32768.f;
        break;
      }
      case SampleFmt::Pcm24: {
        // 紧密打包 24-bit 小端
        const BYTE *p = data + (f * channels + c) * 3;
        int32_t s = (int32_t)(p[0] | (p[1] << 8) | (p[2] << 16));
        if (s & 0x800000)
          s |= ~0xFFFFFF;
        v = (float)s / 8388608.f;
        break;
      }
      case SampleFmt::Pcm32: {
        const int32_t *p =
            reinterpret_cast<const int32_t *>(data) + f * channels + c;
        v = (float)*p / 2147483648.f;
        break;
      }
      default:
        break;
      }
      const float a = v < 0.f ? -v : v;
      if (a > amp)
        amp = a;
    }
    acc->sumsq += (double)amp * (double)amp;
    ++acc->count;
    if (amp > acc->peak)
      acc->peak = amp;
  }
}

void release_path(PathState *p) {
  if (p == nullptr)
    return;
  if (p->capture) {
    p->capture->Release();
    p->capture = nullptr;
  }
  if (p->client) {
    p->client->Stop();
    p->client->Release();
    p->client = nullptr;
  }
  if (p->mix) {
    CoTaskMemFree(p->mix);
    p->mix = nullptr;
  }
  p->fmt = SampleFmt::Unsupported;
  p->channels = 0;
  p->frame_bytes = 0;
  p->active = false;
  p->win = WindowAcc{};
}

HRESULT open_path(IMMDeviceEnumerator *enumerator, EDataFlow flow, bool loopback,
                  PathState *out, AudioStatus *err_st) {
  if (out == nullptr)
    return E_POINTER;
  release_path(out);
  if (err_st)
    *err_st = AudioStatus::Error;

  IMMDevice *dev = nullptr;
  HRESULT hr =
      enumerator->GetDefaultAudioEndpoint(flow, eConsole, &dev);
  if (FAILED(hr) || !dev) {
    if (err_st)
      *err_st = (hr == E_NOTFOUND) ? AudioStatus::NoDevice : AudioStatus::Error;
    return hr;
  }

  IAudioClient *client = nullptr;
  hr = dev->Activate(__uuidof(IAudioClient), CLSCTX_ALL, nullptr,
                     (void **)&client);
  dev->Release();
  if (FAILED(hr) || !client) {
    if (err_st)
      *err_st =
          (hr == E_ACCESSDENIED) ? AudioStatus::Denied : AudioStatus::Error;
    return hr;
  }

  WAVEFORMATEX *mix = nullptr;
  hr = client->GetMixFormat(&mix);
  if (FAILED(hr) || !mix) {
    client->Release();
    if (err_st)
      *err_st = AudioStatus::Error;
    return hr;
  }

  SampleFmt fmt = detect_fmt(mix);
  if (fmt == SampleFmt::Unsupported) {
    CoTaskMemFree(mix);
    client->Release();
    if (err_st)
      *err_st = AudioStatus::Error;
    return E_FAIL;
  }

  DWORD flags = AUDCLNT_STREAMFLAGS_LOOPBACK;
  if (!loopback)
    flags = 0;
  // 共享模式；loopback 必须挂在 render 端点上
  hr = client->Initialize(AUDCLNT_SHAREMODE_SHARED, flags, 10000000, 0, mix,
                          nullptr);
  if (FAILED(hr)) {
    CoTaskMemFree(mix);
    client->Release();
    if (err_st) {
      if (hr == E_ACCESSDENIED)
        *err_st = AudioStatus::Denied;
      else if (hr == AUDCLNT_E_DEVICE_INVALIDATED || hr == E_NOTFOUND)
        *err_st = AudioStatus::NoDevice;
      else
        *err_st = AudioStatus::Error;
    }
    return hr;
  }

  IAudioCaptureClient *cap = nullptr;
  hr = client->GetService(__uuidof(IAudioCaptureClient), (void **)&cap);
  if (FAILED(hr) || !cap) {
    client->Release();
    CoTaskMemFree(mix);
    if (err_st)
      *err_st =
          (hr == E_ACCESSDENIED) ? AudioStatus::Denied : AudioStatus::Error;
    return hr;
  }

  hr = client->Start();
  if (FAILED(hr)) {
    cap->Release();
    client->Release();
    CoTaskMemFree(mix);
    if (err_st)
      *err_st =
          (hr == E_ACCESSDENIED) ? AudioStatus::Denied : AudioStatus::Error;
    return hr;
  }

  out->client = client;
  out->capture = cap;
  out->mix = mix;
  out->fmt = fmt;
  out->channels = (int)mix->nChannels;
  out->frame_bytes = mix->nBlockAlign;
  out->active = true;
  out->win = WindowAcc{};
  if (err_st)
    *err_st = AudioStatus::Ok;
  return S_OK;
}

HRESULT poll_path(PathState *p) {
  if (p == nullptr || !p->active || !p->capture)
    return S_OK;
  for (;;) {
    UINT32 packet = 0;
    HRESULT hr = p->capture->GetNextPacketSize(&packet);
    if (FAILED(hr))
      return hr;
    if (packet == 0)
      break;

    BYTE *data = nullptr;
    UINT32 frames = 0;
    DWORD flags = 0;
    hr = p->capture->GetBuffer(&data, &frames, &flags, nullptr, nullptr);
    if (FAILED(hr))
      return hr;

    const bool silent = (flags & AUDCLNT_BUFFERFLAGS_SILENT) != 0;
    accumulate_frames(&p->win, data, frames, p->channels, p->fmt,
                      p->frame_bytes, silent);

    hr = p->capture->ReleaseBuffer(frames);
    if (FAILED(hr))
      return hr;
  }
  return S_OK;
}

void merge_win_locked(WindowAcc *dst, const WindowAcc &src) {
  dst->sumsq += src.sumsq;
  dst->count += src.count;
  if (src.peak > dst->peak)
    dst->peak = src.peak;
}

// —— 默认设备变更通知：eConsole 角色变化时重建 ——
class NotifyClient : public IMMNotificationClient {
public:
  ULONG AddRef() override { return 1; }
  ULONG Release() override { return 1; }
  HRESULT QueryInterface(REFIID riid, void **ppv) override {
    if (ppv == nullptr)
      return E_POINTER;
    if (riid == __uuidof(IUnknown) || riid == __uuidof(IMMNotificationClient)) {
      *ppv = static_cast<IMMNotificationClient *>(this);
      return S_OK;
    }
    *ppv = nullptr;
    return E_NOINTERFACE;
  }
  HRESULT OnDeviceStateChanged(LPCWSTR, DWORD) override { return S_OK; }
  HRESULT OnDeviceAdded(LPCWSTR) override { return S_OK; }
  HRESULT OnDeviceRemoved(LPCWSTR) override { return S_OK; }
  HRESULT OnPropertyValueChanged(LPCWSTR, const PROPERTYKEY) override {
    return S_OK;
  }
  HRESULT OnDefaultDeviceChanged(EDataFlow flow, ERole role,
                                 LPCWSTR) override {
    if (role != eConsole)
      return S_OK;
    const MusicSource src = g_source.load();
    const bool care_render =
        src == MusicSource::System || src == MusicSource::Both;
    const bool care_capture =
        src == MusicSource::Mic || src == MusicSource::Both;
    if ((flow == eRender && care_render) ||
        (flow == eCapture && care_capture)) {
      g_need_rebuild.store(true);
      printf("[audio] default device changed, rebuild\n");
    }
    return S_OK;
  }
};

NotifyClient g_notify;

void flush_path_wins(PathState *sys, PathState *mic) {
  std::lock_guard<std::mutex> lock(g_mu);
  if (sys && sys->active) {
    merge_win_locked(&g_sys_win, sys->win);
    sys->win = WindowAcc{};
  }
  if (mic && mic->active) {
    merge_win_locked(&g_mic_win, mic->win);
    mic->win = WindowAcc{};
  }
}

void audio_thread_main() {
  HRESULT hr = CoInitializeEx(nullptr, COINIT_MULTITHREADED);
  const bool com_ok = SUCCEEDED(hr) || hr == S_FALSE;
  if (!com_ok) {
    set_status(AudioStatus::Error);
    return;
  }

  IMMDeviceEnumerator *enumerator = nullptr;
  hr = CoCreateInstance(__uuidof(MMDeviceEnumerator), nullptr, CLSCTX_ALL,
                        __uuidof(IMMDeviceEnumerator), (void **)&enumerator);
  if (FAILED(hr) || !enumerator) {
    set_status(AudioStatus::Error);
    CoUninitialize();
    return;
  }

  enumerator->RegisterEndpointNotificationCallback(&g_notify);

  PathState sys{};
  PathState mic{};
  int backoff_ms = 500;

  while (g_running.load()) {
    if (g_need_rebuild.exchange(false)) {
      release_path(&sys);
      release_path(&mic);

      const MusicSource src = g_source.load();
      AudioStatus worst = AudioStatus::Ok;
      bool any_ok = false;

      if (src == MusicSource::System || src == MusicSource::Both) {
        AudioStatus st = AudioStatus::Error;
        hr = open_path(enumerator, eRender, true, &sys, &st);
        if (SUCCEEDED(hr) && sys.active) {
          any_ok = true;
        } else {
          if (st == AudioStatus::Denied ||
              (worst != AudioStatus::Denied && st == AudioStatus::NoDevice) ||
              worst == AudioStatus::Ok)
            worst = st;
          printf("[audio] system open failed hr=0x%08lx st=%d\n",
                 (unsigned long)hr, (int)st);
        }
      }
      if (src == MusicSource::Mic || src == MusicSource::Both) {
        AudioStatus st = AudioStatus::Error;
        hr = open_path(enumerator, eCapture, false, &mic, &st);
        if (SUCCEEDED(hr) && mic.active) {
          any_ok = true;
        } else {
          if (st == AudioStatus::Denied ||
              (worst != AudioStatus::Denied && st == AudioStatus::NoDevice) ||
              worst == AudioStatus::Ok)
            worst = st;
          printf("[audio] mic open failed hr=0x%08lx st=%d\n",
                 (unsigned long)hr, (int)st);
        }
      }

      if (any_ok) {
        set_status(AudioStatus::Ok);
        backoff_ms = 500;
      } else {
        set_status(worst);
        Sleep((DWORD)backoff_ms);
        if (backoff_ms < 2000) {
          backoff_ms *= 2;
          if (backoff_ms > 2000)
            backoff_ms = 2000;
        }
        g_need_rebuild.store(true);
        continue;
      }
    }

    hr = S_OK;
    if (sys.active) {
      hr = poll_path(&sys);
      if (FAILED(hr)) {
        printf("[audio] system poll hr=0x%08lx\n", (unsigned long)hr);
        release_path(&sys);
        g_need_rebuild.store(true);
      }
    }
    if (mic.active) {
      HRESULT hr2 = poll_path(&mic);
      if (FAILED(hr2)) {
        printf("[audio] mic poll hr=0x%08lx\n", (unsigned long)hr2);
        release_path(&mic);
        g_need_rebuild.store(true);
        hr = hr2;
      }
    }

    flush_path_wins(&sys, &mic);
    Sleep(10);
  }

  flush_path_wins(&sys, &mic);
  release_path(&sys);
  release_path(&mic);
  enumerator->UnregisterEndpointNotificationCallback(&g_notify);
  enumerator->Release();
  CoUninitialize();
}

void join_thread() {
  if (g_thread.joinable())
    g_thread.join();
}

} // namespace

void audio_start(MusicSource src) {
  audio_stop();
  g_source.store(src);
  {
    std::lock_guard<std::mutex> lock(g_mu);
    g_sys_win = WindowAcc{};
    g_mic_win = WindowAcc{};
  }
  g_need_rebuild.store(true);
  g_running.store(true);
  g_thread = std::thread(audio_thread_main);
}

void audio_stop() {
  if (!g_running.exchange(false) && !g_thread.joinable())
    return;
  g_running.store(false);
  join_thread();
  {
    std::lock_guard<std::mutex> lock(g_mu);
    g_sys_win = WindowAcc{};
    g_mic_win = WindowAcc{};
  }
}

void audio_restart(MusicSource src) {
  if (!g_running.load()) {
    audio_start(src);
    return;
  }
  g_source.store(src);
  g_need_rebuild.store(true);
}

void audio_take_window(float *out_rms, float *out_peak) {
  float rms = 0.f, peak = 0.f;
  WindowAcc sys{}, mic{};
  {
    std::lock_guard<std::mutex> lock(g_mu);
    sys = g_sys_win;
    mic = g_mic_win;
    g_sys_win = WindowAcc{};
    g_mic_win = WindowAcc{};
  }

  const MusicSource src = g_source.load();
  auto finish = [](const WindowAcc &w, float *r, float *p) {
    if (w.count == 0) {
      *r = 0.f;
      *p = 0.f;
      return;
    }
    *r = (float)std::sqrt(w.sumsq / (double)w.count);
    *p = w.peak;
  };

  float r0 = 0.f, p0 = 0.f, r1 = 0.f, p1 = 0.f;
  if (src == MusicSource::System || src == MusicSource::Both)
    finish(sys, &r0, &p0);
  if (src == MusicSource::Mic || src == MusicSource::Both)
    finish(mic, &r1, &p1);

  if (src == MusicSource::Both) {
    rms = r0 > r1 ? r0 : r1;
    peak = p0 > p1 ? p0 : p1;
  } else if (src == MusicSource::Mic) {
    rms = r1;
    peak = p1;
  } else {
    rms = r0;
    peak = p0;
  }

  if (out_rms)
    *out_rms = rms;
  if (out_peak)
    *out_peak = peak;
}

AudioStatus audio_status() { return g_status.load(); }
