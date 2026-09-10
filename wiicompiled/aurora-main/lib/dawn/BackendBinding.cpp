#include "BackendBinding.hpp"

#include <memory>

#if !defined(SDL_PLATFORM_MACOS) && !defined(SDL_PLATFORM_IOS) && !defined(SDL_PLATFORM_TVOS)
#include <SDL3/SDL_video.h>
#endif

namespace aurora::webgpu::utils {
std::shared_ptr<wgpu::ChainedStruct> SetupWindowAndGetSurfaceDescriptorCocoa(SDL_Window* window);

std::shared_ptr<wgpu::ChainedStruct> SetupWindowAndGetSurfaceDescriptor(SDL_Window* window) {
#if defined(SDL_PLATFORM_MACOS) || defined(SDL_PLATFORM_IOS) || defined(SDL_PLATFORM_TVOS)
  return SetupWindowAndGetSurfaceDescriptorCocoa(window);
#else
  const auto props = SDL_GetWindowProperties(window);
#if defined(SDL_PLATFORM_ANDROID)
  std::shared_ptr<wgpu::SurfaceSourceAndroidNativeWindow> desc =
      std::make_shared<wgpu::SurfaceSourceAndroidNativeWindow>();
  desc->window = SDL_GetPointerProperty(props, SDL_PROP_WINDOW_ANDROID_WINDOW_POINTER, nullptr);
  return std::move(desc);
#elif defined(SDL_PROP_WINDOW_WINRT_WINDOW_POINTER)
  // UWP / Windows Store: there is no HWND — the window is a CoreWindow. The
  // SternXD/SDL3-uwp WinRT driver exposes it on the SDL window as
  // SDL_PROP_WINDOW_WINRT_WINDOW_POINTER (an IInspectable*). Guard on that
  // property macro rather than WINAPI_FAMILY because it is defined only when
  // the UWP fork's SDL_video.h is in use, so this branch is a guaranteed
  // no-op on the native (vanilla-SDL / HWND) build.
  std::shared_ptr<wgpu::SurfaceDescriptorFromWindowsCoreWindow> desc =
      std::make_shared<wgpu::SurfaceDescriptorFromWindowsCoreWindow>();
  desc->coreWindow =
      SDL_GetPointerProperty(props, SDL_PROP_WINDOW_WINRT_WINDOW_POINTER, nullptr);
  return std::move(desc);
#elif defined(SDL_PLATFORM_WIN32)
  std::shared_ptr<wgpu::SurfaceSourceWindowsHWND> desc = std::make_shared<wgpu::SurfaceSourceWindowsHWND>();
  desc->hwnd = SDL_GetPointerProperty(props, SDL_PROP_WINDOW_WIN32_HWND_POINTER, nullptr);
  desc->hinstance = SDL_GetPointerProperty(props, SDL_PROP_WINDOW_WIN32_INSTANCE_POINTER, nullptr);
  return std::move(desc);
#elif defined(SDL_PLATFORM_LINUX)
  const char* driver = SDL_GetCurrentVideoDriver();
  if (SDL_strcmp(driver, "wayland") == 0) {
    std::shared_ptr<wgpu::SurfaceSourceWaylandSurface> desc = std::make_shared<wgpu::SurfaceSourceWaylandSurface>();
    desc->display = SDL_GetPointerProperty(props, SDL_PROP_WINDOW_WAYLAND_DISPLAY_POINTER, nullptr);
    desc->surface = SDL_GetPointerProperty(props, SDL_PROP_WINDOW_WAYLAND_SURFACE_POINTER, nullptr);
    return std::move(desc);
  }
  if (SDL_strcmp(driver, "x11") == 0) {
    std::shared_ptr<wgpu::SurfaceSourceXlibWindow> desc = std::make_shared<wgpu::SurfaceSourceXlibWindow>();
    desc->display = SDL_GetPointerProperty(props, SDL_PROP_WINDOW_X11_DISPLAY_POINTER, nullptr);
    desc->window = SDL_GetNumberProperty(props, SDL_PROP_WINDOW_X11_WINDOW_NUMBER, 0);
    return std::move(desc);
  }
#endif
  return nullptr;
#endif
}

} // namespace aurora::webgpu::utils
