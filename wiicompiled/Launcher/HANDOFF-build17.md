# HANDOFF: MKWii "WiiCompiled" → UWP (Xbox Series) — MSVC/Option B, build15 → build17

**Status: the UWP app RUNS as a packaged Appx — shell activation → CoreWindow → RuntimeMain → guest PPC core executes → crashes at the first fixed-address guest-memory mapping (MapViewOfFile3FromApp → ERROR_INVALID_PARAMETER 87). B7 (real entry) is DONE and verified live. B8 (packaging+deploy) is DONE and verified live on this desktop. The single remaining blocker is one memory-mapping call in `runtime/src/guest_flat_memory.cpp` (its App-partition branch), then repackage+redeploy.**

**Git:** root `C:\MKWii`, HEAD = `1a354e7`. Everything since build15 is **UNCOMMITTED**:
- `wiicompiled/runtime/src/winrt_main_stub.cpp` (NEW, untracked) — the B7 entry, see §2.
- `wiicompiled/runtime/src/guest_flat_memory.cpp` — the current 87 fix attempt (App-partition map now `AllocationType=0`); **does not work**, see §3 for what to try next. Revert or iterate from here.
- `wiicompiled/runtime/cmake/PublicProducts.cmake` — stub target now has explicit SDL include dirs (see §2).
- `wiicompiled/runtime/CMakeLists.txt` — REMOVE_ITEM of the stub from the src glob (build16 fix) + the CRT wiring from build15. (`git status` showed these 3 modified + 1 untracked; the build15 changes from the prior handoff §4 are still uncommitted too if HEAD hasn't moved — verify with `git status`.)
- Native Clang build: verified green at `native-build/WiiCompiled.exe` (ninja exit 0, 09/09 07:26). All edits remain toolchain-gated no-ops on Clang.
- New evidence dir: `Launcher/uwp-appx/` (package layout, AppxManifest.xml, mkwii-dev.pfx/.cer, deploy-elevated.ps1, deploy-result.txt) and `Launcher/uwp-smoke/flat_probe.cpp` + `flat-probe.bat`.

---

## 1. MISSION (unchanged)

Port WiiCompiled (Wii U emulator runtime + Aurora + Dawn, 29065 translated shards) to a UWP app for Xbox Series (Developer Mode) using MSVC v143 + SternXD/SDL3-uwp fork (C++/CX). Native Clang/llvm-mingw build MUST stay working. Build driver `Launcher\build-uwp-msvc.ps1 -Target WiiCompiled`; build dir `native-build-uwp`; CMake 4.3.3 portable; `-Target WiiCompiled` only. All toolchain constraints from the prior handoffs stand (junctions C:\msvcinc/C:\msvclib, no space paths in flags, UWP defines, Clang ASM wrapper, no `__x86_64__` in the shim, no `.CRT$` pragmas, ESET = first suspect for odd file errors).

## 2. WHAT B7 IS NOW (DONE, verified live)

**Entry chain (proven by link experiments build15/16 + a live packaged run):**
```
PE mainCRTStartup → vccorlib140 climain → int main(Platform::Array<Platform::String^>^)   [winrt_main_stub.cpp]
  → SDL_RunApp(0, nullptr, &RuntimeMain, nullptr)        [fork SDL_sysmain_runapp.cpp]
  → Windows::Foundation::Initialize(RO_INIT_MULTITHREADED) + SDL_WinRTInitNonXAMLApp
  → CoreApplication::Run(SDL_WinRTApp IFrameworkView)     [fork SDL_winrtapp_direct3d.cpp]
  → CoreWindow created/activated, dispatcher pumped
  → view thread calls RuntimeMain (main.cpp) → full runtime
```
**Key facts learned (do not rediscover):**
1. `winrt_main_stub.cpp` is the ONLY C++/CX TU (`mkw_winrt_main_stub` OBJECT, `/ZW -std:c++14`), excluded from the `src/*.cpp` glob by an explicit `REMOVE_ITEM` in `runtime/CMakeLists.txt` (build16: without it, the unity C++20 TU hits C2653 'Platform'; native Clang would reject the syntax too — REMOVE_ITEM applies on both toolchains).
2. Do **NOT** `#include <SDL3/SDL_main.h>` in the stub: this fork's SDL_main.h always compiles in SDL_main_impl.h's WinRT branch (`WinMain → SDL_RunApp(0,NULL,SDL_main,NULL)`), which adds an unsatisfiable **undecorated** `SDL_main` reference (build16 LNK2019; the C++/CX-renamed `?SDL_main@@…` doesn't match). The stub declares SDL_RunApp itself: `extern "C" int SDL_RunApp(int, char**, int(*)(int,char**), void*)` — byte-matches the fork's definition (SDL_main_func = `int (SDLCALL*)(int,char**)`; single x64 convention so the spelling is exact).
3. The stub target needed explicit include dirs in `PublicProducts.cmake` (it doesn't link SDL targets so inherits nothing): `SDL-uwp/include` + `native-build-uwp/_deps/sdl-build/include-revision`. Keep.
4. `RuntimeMain` is the real entry called on the CoreWindow/view thread; its MSVC branch already runs the CPU-baseline guard + SEH installers (this is why the packaged crash produced full `crash_seh.txt` artifacts — the guards work).
5. Unpackaged double-click = `0xC000027B` (stowed WinRT exception): `CoreApplication::Run` needs package identity. **The Appx path is not optional for testing.**

## 3. THE BLOCKER (what's left)

**Packaged live-run evidence (logs in `%LOCALAPPDATA%\Packages\e2f1c9a4-6b3d-4e8f-9a2c-1d5b7f0e8a31_estjbgtbkb84t\AC\WiiCompiled\Logs\base_*`):**
- Config.toml loads, transcript live, guest core starts, GX HLE calls execute (SCCheckStatus/GX SetTmemConfig frames in the host stack).
- Then: `Runtime error: Unable to map guest region 0x0 (+0x1800000) into the flat reservation (GetLastError=87)` → clean fatal path (SEH dump written, exit).

**Root-cause state:** in `guest_flat_memory.cpp`:
- `EnsureReservation`: `VirtualAlloc2FromApp(MEM_RESERVE, 4GiB+granule @ kFixedFlatGuestBase)` — **works in the AppContainer** (the crash happens later). NOTE: it is a PLAIN reservation (the App branch deliberately skips MEM_RESERVE_PLACEHOLDER; comment claims FromApp rejects placeholder flags — **this claim is UNVERIFIED**).
- `MapGuestView` → `MapViewOfFile3FromApp(section, GetCurrentProcess(), target, off, size, allocType, PAGE_READWRITE, nullptr, 0)` → **87 for BOTH `MEM_RESERVE` and `0` (committed) allocType** (current code = `0`, build17, still 87).
- Sections themselves are plain `CreateFileMappingW(INVALID_HANDLE_VALUE,…)` + host alias via plain `MapViewOfFile` — both fine in AppContainer (app passed them).
- Desktop `MapViewOfFile3` docs say `MEM_RESERVE` is a valid allocType ("maps a reserved view"), but the App-partition `*FromApp` behavior differs. The canonical desktop recipe for "map into a reserved region" (MS docs Scenario 1) uses **placeholders**: `VirtualAlloc2(MEM_RESERVE|MEM_RESERVE_PLACEHOLDER)` → `VirtualFree(MEM_RELEASE|MEM_PRESERVE_PLACEHOLDER)` split → `MapViewOfFile3(MEM_REPLACE_PLACEHOLDER)`.
- **Desktop probe caveat:** `Launcher/uwp-smoke/flat_probe.cpp` (run via `flat-probe.bat`) shows ALL `*FromApp` calls return 87 from a plain DESKTOP process (the FromApp entry points validate the caller, not just the partition) — so this probe **cannot** A/B the App-partition behavior. To iterate you must go through the packaged app (see §4 redeploy loop, ~2 min).

**Hypotheses to try, in order:**
1. **Full placeholder pattern under FromApp** (test whether the code comment "FromApp doesn't take placeholder flags" is actually false): `EnsureReservation` App branch → `MEM_RESERVE | MEM_RESERVE_PLACEHOLDER`; `SplitPlaceholder` App branch → `VirtualFreeEx(GetCurrentProcess(), addr, size, MEM_RELEASE | MEM_PRESERVE_PLACEHOLDER)`; `MapGuestView` App branch → `kMemReplacePlaceholder` (i.e. make the App branches identical to desktop, using the FromApp entry points + `VirtualFreeEx`/`VirtualProtectEx` where the plain forms are non-importable). One-line-per-branch change; highest prior.
2. If placeholders are truly rejected: **no fixed-base mapping at all** — reserve WITHOUT fixed base is impossible for this design (translated code uses a compiled-in flat base). Then consider: map views at offset 0 into a large section covering the whole 4GiB guest space (single section, single map at reservation time, then `ProtectRange`/commit-on-demand within it), or `VirtualAlloc2FromApp` with `MemExtendedParameterAddressRequirements` (BaseAddress=NULL + address requirements) — but note the fixed-base requirement likely rules this out; document before spending a day.
3. Last resort: `MapViewOfFileFromApp` (the classic FromApp map, no fixed address) cannot place at `kFixedFlatGuestBase`; don't chase it.
- After any fix: rebuild (incremental ~2 min), repackage+redeploy (§4), launch, check the newest `AC\WiiCompiled\Logs\base_*\console.log`. The next expected failure (if any) is in the same class for `CommitPlaceholder` (MMIO window / stray commits) — apply the same resolution.

## 4. B8 — REDEPLOY LOOP (DONE once; reusable, ~2 min)

```bat
:: 1) copy fresh exe (after build)
copy /y C:\MKWii\wiicompiled\native-build-uwp\WiiCompiled.exe C:\MKWii\wiicompiled\Launcher\uwp-appx\package\
:: 2) pack + sign (signtool needs the pfx; password <PFX_PASSWORD>)
C:\WindowsSDK\bin\10.0.28000.0\x64\makeappx.exe pack /d C:\MKWii\wiicompiled\Launcher\uwp-appx\package /p C:\MKWii\wiicompiled\Launcher\uwp-appx\WiiCompiled_0.1.0.0_x64.appx /o
C:\WindowsSDK\bin\10.0.28000.0\x64\signtool.exe sign /fd SHA256 /a /f C:\MKWii\wiicompiled\Launcher\uwp-appx\mkwii-dev.pfx /p <PFX_PASSWORD> C:\MKWii\wiicompiled\Launcher\uwp-appx\WiiCompiled_0.1.0.0_x64.appx
:: 3) deploy (same identity ⇒ must remove first, or bump Version in AppxManifest.xml)
powershell -NoProfile -Command "Remove-AppxPackage -Package 'e2f1c9a4-6b3d-4e8f-9a2c-1d5b7f0e8a31_0.1.0.0_neutral__estjbgtbkb84t'; Add-AppxPackage -Path C:\MKWii\wiicompiled\Launcher\uwp-appx\WiiCompiled_0.1.0.0_x64.appx"
:: 4) launch + verify
powershell -NoProfile -Command "Start-Process 'shell:AppsFolder\e2f1c9a4-6b3d-4e8f-9a2c-1d5b7f0e8a31_estjbgtbkb84t!App'; Start-Sleep 12; Get-Process WiiCompiled -ErrorAction SilentlyContinue"
```
Package facts (all proven): identity `e2f1c9a4-6b3d-4e8f-9a2c-1d5b7f0e8a31_0.1.0.0_neutral__estjbgtbkb84t`, family `…_estjbgtbkb84t`, AUMID `…estjbgtbkb84t!App`, install root `C:\Program Files\WindowsApps\…`. Cert: `CN=MKWii`, thumbprint `337D316382E21927DD21138DC20235F83EAB3461`, pfx password `<PFX_PASSWORD>`; already in LocalMachine TrustedPeople+Root (imported via the elevated `deploy-elevated.ps1` — UAC prompt; also user Root store) — **no admin needed for redeploy of same-publisher packages**. Manifest gotchas fixed: `Resource Language` must be `en-us` (NOT `x-generate`, which fails registration with 0x80070057 unless makepri is run); logo assets need base-name copies next to the `.scale-200` ones (already in `package/Assets`). Payload: exe + webgpu_dawn/libpng16/z.dll + 7 onecore CRT DLLs (vccorlib140, vcruntime140, vcruntime140_1, msvcp140, msvcp140_1/_2, msvcp140_atomic_wait) from `E:\Program Files\Microsoft Visual Studio\2022\Community\VC\Redist\MSVC\14.44.35112\onecore\x64\Microsoft.VC143.CRT`. AppData lands (virtualized) in `…\Packages\<family>\AC\WiiCompiled\` — Config.toml auto-created there; logs under `AC\WiiCompiled\Logs\base_*`.

## 5. OPEN QUESTIONS (answer in order)
1. Does the full placeholder pattern (`MEM_RESERVE_PLACEHOLDER` reserve + `VirtualFreeEx` split + `MEM_REPLACE_PLACEHOLDER` map, all via `*FromApp`/`Ex` forms) work inside the AppContainer? (§3 hypothesis 1 — try first, it's the desktop-canonical recipe.)
2. After guest RAM maps: does `CommitPlaceholder`'s App branch (`VirtualAlloc2FromApp(MEM_COMMIT)` over the plain reservation) work, or need the same treatment?
3. Does `VirtualProtectEx` (the App-branch `ProtectRange`) behave for the guest-protection scheme (it's on the startup path only after mapping succeeds)?
4. Window/audio/input on desktop packaged: SDL-uwp's CoreWindow path should surface a window once the runtime gets past memory init — if the window appears but rendering is black, check Dawn's `wgpu::SurfaceDescriptorFromWindowsCoreWindow` wiring (field `coreWindow`, IInspectable*) gets the real CoreWindow from the SDL-uwp driver.
5. (Xbox) `Add-AppxPackage` via Device Portal / Xbox Dev Mode partner steps + `gameInput` capability; LOCALAPPDATA presence + package scoping on the console (decides host_platform.cpp's data-dir path).

## 6. CONSTRAINTS (restate)
- Never break the native Clang build: every edit `_MSC_VER`/`WINAPI_FAMILY_PARTITION`-gated or a proven no-op. `native-build/` untouched. `dependencies/SDL` (vanilla) untouched; prefer first-party fixes over touching the SDL-uwp fork.
- Do NOT reintroduce `C:\mkwcrtlib`; do NOT `lib.exe /DEF:<dll>` (ESET LNK1107 — use dumpbin→text-def if ever needed).
- The manual link repro (`uwp-smoke/test23.bat` pattern against `native-build-uwp/CMakeFiles/WiiCompiled.rsp`) only works while an .rsp exists; after a successful build ninja deletes it — re-verify links via incremental builds instead (they're ~2 min).
- Desktop probes of `*FromApp` memory APIs are NOT representative (they fail caller-validation outside an AppContainer) — iterate through the packaged app.
