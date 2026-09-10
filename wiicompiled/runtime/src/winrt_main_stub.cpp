// UWP app entry for the MSVC/UWP (Option B) build.
//
// Entry chain (proven by build15+build16 link experiments):
//   PE entry (mainCRTStartup) -> vccorlib140 climain -> the C++/CX app entry
//   "?main@@YAHP$01E$AAV?$Array@PE$AAVString@Platform@@$00@Platform@@@Z",
//   i.e. int main(Platform::Array<Platform::String^>^) - the function below.
//
// The body forwards to SDL_RunApp (SternXD/SDL3-uwp fork,
// src/main/winrt/SDL_sysmain_runapp.cpp): Windows::Foundation::Initialize
// (RO_INIT_MULTITHREADED) + SDL_WinRTInitNonXAMLApp -> CoreApplication::Run
// with the fork's IFrameworkView (SDL_WinRTApp). That view creates/activates
// the CoreWindow, pumps its dispatcher (SDL's event layer hooks into
// ProcessEvents), and on the view thread invokes the C-style entry point
// passed here -> RuntimeMain (main.cpp): CPU-baseline guard, SEH installers,
// config, aurora + SDL window, guest runtime. When RuntimeMain returns, the
// view completes, SDL_RunApp returns and the process exits with its code.
//
// SDL_RunApp's 4th arg is the XAML panel pointer; null = the Direct3D
// (CoreWindow-only) host, which is the fork's own Xbox path.
//
// Deliberately NOT including <SDL3/SDL_main.h>: this fork's copy always
// compiles in SDL_main_impl.h's WinMain (even with SDL_MAIN_HANDLED), which
// adds an unsatisfiable plain-C "SDL_main" reference (build16 LNK2019). The
// declaration below matches the fork's own definition byte-for-byte
// (SDL_sysmain_runapp.cpp: extern "C" int SDL_RunApp(int, char**,
// SDL_main_func, void*), SDL_main_func = int (SDLCALL*)(int, char**) - a
// single x64 calling convention, so the spelling is exact).
//
// This TU is the ONLY C++/CX file in the product: it is compiled as its own
// OBJECT library with /ZW /std:c++14 (mirroring the fork's winrt TUs,
// SDL-uwp/CMakeLists.txt 521-523) and must never join the plain C++20
// product sources (see the REMOVE_ITEM in CMakeLists.txt). The global
// SDL_MAIN_HANDLED define on this compile line is correct: it keeps every
// OTHER SDL header from redefining main, and this TU declares SDL_RunApp
// itself instead of relying on the header's dispatch. platformobject.h is
// absent from this machine's MSVC include dir, so no box() is used here.

extern "C" int SDL_RunApp(int argc, char** argv, int (*mainFunction)(int, char**), void* reserved);

// C++-mangled on purpose: RuntimeMain in main.cpp has C++ linkage.
extern int RuntimeMain(int argc, char** argv);

int main(Platform::Array<Platform::String^>^ args) {
    (void)args;
    return SDL_RunApp(0, nullptr, &RuntimeMain, nullptr);
}
