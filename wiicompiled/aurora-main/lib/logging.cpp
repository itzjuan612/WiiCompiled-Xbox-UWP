#include "logging.hpp"

#include <fmt/base.h>
#include <fmt/format.h>
#include <aurora/aurora.h>

#include <cstdio>
#include <string>
#include <string_view>

// See lib/window.cpp for the winapifamily.h story: without this include the
// WINAPI_FAMILY_PARTITION test below fails to compile on the native
// llvm-mingw toolchain (the macro is neither predefined nor on this TU's
// include path since the windows.h include moved below it).
#if defined(_WIN32)
#include <winapifamily.h>
#endif

#if defined(_WIN32) && WINAPI_FAMILY_PARTITION(WINAPI_PARTITION_DESKTOP)
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#include <windows.h>
#endif

namespace aurora {
extern AuroraConfig g_config;

void Module::show_fatal_dialog(const char* module, std::string_view message) noexcept {
  try {
    std::string body = "Aurora stopped because of a fatal renderer error";
    if (module != nullptr && module[0] != '\0') {
      body += " in ";
      body += module;
    }
    body += ":\n\n";
    body.append(message.data(), message.size());
    body += "\n\nSee the console and log files for more details.";
#if defined(_WIN32) && WINAPI_FAMILY_PARTITION(WINAPI_PARTITION_DESKTOP)
    ::MessageBoxA(nullptr, body.c_str(), "Aurora fatal error",
                  MB_OK | MB_ICONERROR | MB_SETFOREGROUND | MB_TASKMODAL);
#else
    // Non-Windows, and the Windows App (Store/UWP) partition (MessageBoxA is desktop-tier and
    // absent): keep the console/log diagnostic instead of a native dialog.
    std::fprintf(stderr, "[aurora] fatal dialog: %s\n", body.c_str());
#endif
  } catch (...) {
    // Fatal reporting must never hide the original abort.
  }
}

void log_internal(const AuroraLogLevel level, const char* module, const char* message,
                  const unsigned int len) noexcept {
  if (module == nullptr) {
    module = "";
  }
  if (g_config.logCallback == nullptr) {
    fmt::println(stderr, "[{}] [{}] {}", level, module, std::string_view(message, len));
  } else {
    g_config.logCallback(level, module, message, len);
  }
}
} // namespace aurora

auto fmt::formatter<AuroraLogLevel>::format(const AuroraLogLevel level, format_context& ctx) const
    -> format_context::iterator {
  std::string_view name = "unknown";
  switch (level) {
  case LOG_DEBUG:
    name = "debug";
    break;
  case LOG_INFO:
    name = "info";
    break;
  case LOG_WARNING:
    name = "warning";
    break;
  case LOG_ERROR:
    name = "error";
    break;
  case LOG_FATAL:
    name = "fatal";
    break;
  default:
    break;
  }
  return formatter<std::string_view>::format(name, ctx);
}
