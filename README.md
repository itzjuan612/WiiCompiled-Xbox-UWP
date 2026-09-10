# WiiCompiled — UWP / Xbox Series port

A **Universal Windows Platform (UWP)** port of [WiiCompiled](https://github.com/patchzyy/Wiicompiled),
a native static-recompilation PC port of *Mario Kart Wii*. This fork targets **Xbox Series S|X in
Developer Mode** (and touches desktop UWP), rendering through Direct3D 12 via
[aurora](https://github.com/encounter/aurora) + [Dawn](https://dawn.googlesource.com/dawn).

> [!IMPORTANT]
> This repository contains **no Nintendo code, assets, or game data**. You must supply your own
> legally dumped copy of the PAL (`RMCP01`) version of the game. Nothing is uploaded anywhere; the
> static recompiler runs locally against your own disc image.

---

## What is this?

The upstream WiiCompiled project statically recompiles *Mario Kart Wii* to native code — there is no
emulator, interpreter, JIT, or PowerPC execution at runtime. This repository is a **platform port**
that makes that runtime build and run as a packaged UWP application on Xbox consoles, plus the
several host-side fixes that were required to make the MSVC/UWP target render correctly.

The upstream project, its full feature list, setup instructions, and the canonical build belong to
the WiiCompiled team — see **[`wiicompiled/README.md`](wiicompiled/README.md)**. Everything here
builds on that work; this document only covers what the UWP/Xbox port adds or changes.

## Status

- Boots and plays on **Xbox Series S** in Developer Mode at 60fps, running the full game (Grand Prix,
  time trials, cutscenes) from an external USB drive.
- Xbox pads and DualSense controllers are both mapped correctly.
- The **desktop UWP** target renders correctly as well.

## What the UWP port had to fix

Getting a desktop codebase running in the Xbox AppContainer surfaced a number of issues. Each of the
following is a real change in this repo:

### MSVC code generation

- **Paired-single lane helpers folded to zero.** MSVC `/O1` and `/O2` (with `/arch:AVX2`) mis-folded
  several `_mm_shuffle_ps`/`_mm_unpacklo_ps`-based helpers in `runtime/include/isa/ppc_isa_float.h`
  (`PPC_PsMerge*`, `PpcBroadcastPs0/1`, `PpcGetPs0/1`, `PpcPackPaired`) to literal zeros. This
  zeroed guest matrices and produced a black frame. They are rewritten as compiler-agnostic integer /
  `memcpy` bit-surgery, gated behind `_MSC_VER`, leaving the clang paths untouched.
- **Translated shards now build `/O2`.** The guest-code translation units were built `/O1` under MSVC;
  switching to `/O2` roughly doubled emulation speed (menus and races hit 60fps).

### Packaged-app (AppContainer) startup

- **Unbound stdout/stderr aborted the process.** Packaged Xbox apps start with `_fileno(stdout) == -1`
  and `GetStdHandle` NULL, so the transcript setup's `_dup(-1)` tripped the CRT invalid-parameter
  handler. `runtime/src/main.cpp` now binds an unbound stream directly to the run log and guards the
  transcript pipe against negative descriptors.

### Direct3D 12 / Dawn

- **PSO blob serialization removed the device.** The Xbox `SraKmd_arden` driver removes the D3D12
  device as a side effect of `ID3D12PipelineState::GetCachedBlob()`. Dawn now skips the blob-cache
  store when the `disable_blob_cache` toggle is enabled, which aurora sets on UWP.
- **Runtime-loaded DXC instead of legacy FXC.** Legacy FXC failed to compile some GX pipelines on
  Xbox with `E_OUTOFMEMORY`. The vendored Dawn is built with a `DAWN_USE_DXC_LOADER` option that
  enables Dawn's DXC code path (headers + runtime-loaded `dxcompiler.dll`/`dxil.dll`) without building
  DXC, and probed at adapter setup with a safe fallback to FXC when the DLLs are unavailable.

### Memory / stability

- **The app must register as a Game, not an App.** A clean redeploy registered the app as a UWP *App*
  with a small commit budget; a burst of first-use pipeline compiles then died with `std::bad_alloc`
  and a fault inside the console shader compiler. Setting the console preference
  `DefaultUWPContentTypeToGame = true` (Device Portal → Settings) + a reboot + redeploy gives the app
  the larger *Game* budget, after which the race completes.
- **Bounded texture cache growth** (UWP-scaled cache limits + releasing stale pinned handles) and a
  single pipeline-compile worker on UWP to cap transient memory.
- **THP movie texture reuse.** The intro cutscene re-initialized a texture object every frame;
  `resolve_static_texture` now re-uploads into the existing handle instead of minting a new GPU
  texture per frame (which previously exhausted D3D12 memory).

### Input

- **DualSense support under the WGI driver.** UWP uses SDL3's Windows.Gaming.Input backend, which
  presents pads with a rewritten GUID that can't match the built-in gamecontrollerdb entry, so the
  DualSense fell back to the hardcoded Xbox layout. The vendored SDL-uwp fork
  (`Launcher/artifacts/dependencies/SDL-uwp`, not tracked here) detects Sony VID/PID and emits a
  DualSense-correct mapping. The built-in `Config.default.toml` seeding below covers the rest.

### Configuration seeding

- The runtime seeds a fresh user `Config.toml` from a `Config.default.toml` shipped next to the
  executable (inside the appx), then falls back to the built-in template. This lets an installation
  ship sensible defaults. See `runtime/include/runtime_config.h`.

## Building

The build is driven from `wiicompiled/Launcher`:

```powershell
# UWP / Xbox (MSVC): configure once, then build
.\Launcher\configure-uwp-msvc.ps1
.\Launcher\build-uwp-msvc.ps1 -Target WiiCompiled
```

The resulting `WiiCompiled.exe` is packaged into a signed `.appx` and deployed to a console in
Developer Mode (see `wiicompiled/Launcher/HANDOFF-build17.md` for the historical UWP bring-up notes,
and `wiicompiled/README.md` for the upstream native build).

> [!NOTE]
> Building the UWP target requires the MSVC toolchain, the Windows SDK, and a device or emulator in
> Developer Mode. Xbox deployment is done via Device Portal (or `WinAppDeployCmd`).

## Credits

This port would not exist without the upstream projects it stands on. All of the real work below
belongs to their authors:

- **[WiiCompiled](https://github.com/patchzyy/Wiicompiled)** — the static-recompilation runtime this
  port adapts to UWP/Xbox. **GPL-3.0.**
- **[aurora](https://github.com/encounter/aurora)** by encounter — the GameCube/Wii GX rendering and
  windowing layer underneath everything. **MIT.**
- **[Dawn](https://dawn.googlesource.com/dawn)** — Google's WebGPU implementation, powering the D3D12
  backend. Includes **[Tint](https://dawn.googlesource.com/tint)** and the
  **[DirectXShaderCompiler](https://github.com/microsoft/DirectXShaderCompiler)** (DXC). **BSD-3-Clause / Apache-2.0.**
- **[Dolphin Emulator](https://github.com/dolphin-emu/dolphin)** — reference for Wii hardware
  behavior, and the source of the free DSP coefficient ROM and the unmodified WiiConnect24 bootstrap
  tree bundled with the runtime. **GPL-2.0+.**
- **[SDL](https://github.com/libsdl-org/SDL)** — windowing, input, and the WinRT/CoreWindow platform
  backend (via a vendored UWP fork). **Zlib.**
- **[Retro Rewind](https://wiki.tockdom.com/wiki/Retro_Rewind)** by ZPL and team — the mod
  distribution the upstream project supports.
- **[Wheel Wizard](https://github.com/TeamWheelWizard/WheelWizard)** — the mod manager the upstream
  project integrates with as a launch backend.
- Everyone in the static-recompilation community.

The bundled third-party components and their licenses — Abseil, ImGui, fmt, xxHash, zlib, libpng,
FreeType, Zstd, SQLite, Tracy, Crypto++, pugixml, toml11, libco, C++/WinRT, and others — are
enumerated in **[`wiicompiled/THIRD-PARTY-NOTICES.md`](wiicompiled/THIRD-PARTY-NOTICES.md)**.

## License

This project is licensed under the **[GNU General Public License, version 3](LICENSE)**, matching
upstream WiiCompiled. Any distribution making use of WiiCompiled must be licensed under GPL-3.0.

Not affiliated with, endorsed by, or associated with Nintendo. *Mario Kart Wii* is a trademark of
Nintendo. No Nintendo intellectual property is contained in, distributed with, or obtainable through
this project.
