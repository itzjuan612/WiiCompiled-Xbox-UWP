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
- **Retro Rewind** is supported as a second packaged product, including its **online (Retro-WFC)**
  play: it boots, applies its Riivolution overlays, and connects to the Retro-WFC server for
  matchmaking and races.
- The **desktop UWP** target renders correctly as well.

## Retro Rewind

The upstream project builds Retro Rewind as a separate static product (`RetroRewind.exe`) from the
mod's `Code.pul`. This port does the same and ships both executables in one package:

- `AppxManifest.xml` declares **two applications** — `WiiCompiled.exe` and `RetroRewind.exe` — so
  the base game and the mod are both launchable and share one app data directory (and therefore the
  same save/NAND).
- Export a Retro Rewind install to the console (e.g. `E:\RetroRewind\RetroRewind6`) and set
  `[paths] retro_rewind_root` plus `overlay_roots` in `Config.toml`:

  ```toml
  [paths]
  retro_rewind_root = "E:\\RetroRewind\\RetroRewind6"
  overlay_roots = ["E:\\RetroRewind"]
  ```
> [!NOTE]
> PC users: The packaged (Xbox / Windows app) build runs inside a sandbox and may only write inside its
> own app data folder. Retro Rewind's `riivolution` save redirect writes *next to the pack*, so
> a pack that lives outside app data is read-only to that build. Nothing has been saved there
> yet and the redirect is skipped, keeping the save in the configured NAND; if the folder
> already holds a save the build stops with an error naming it rather than silently abandoning
> it. Fix it by moving the pack into the app's data folder, using the unpackaged desktop build,
> or granting write access:
>
> ```powershell
> icacls "<pack>\riivolution" /grant *S-1-15-2-1:(OI)(CI)M
> ```

- Online play is enabled at translation time via the signed Retro-WFC payload; the runtime's
  `[OSReport] WWFC_NOTICE: Payload version …` line confirms it is active. No host rewriting is done in
  the socket layer — the payload redirects the Nintendo WFC hostnames itself.

### Building Retro Rewind

Before configuring the UWP build, generate the Retro Rewind translation (see
`wiicompiled/Launcher/LocalBuild.ps1` for the canonical argument list). The rough sequence, run from
`wiicompiled/` with the translator CLI:

```powershell
# 1. base translation (records mod-patch awareness)
dotnet translator\src\Translator.Cli\bin\Release\net8.0\Translator.Cli.dll translate-recursive 0x800060A4 `
  --project projects\mkwii\recomp.yml --outdir generated\functions `
  --output-metadata generated\base_translation_output.json `
  --production-source-bundle generated\base_translation_sources.bin `
  --no-function-files --prune-stale --threads 16

# 2. base manifest
dotnet ...\Translator.Cli.dll emit-base-manifest --project projects\mkwii\recomp.yml `
  --out build\base --functions-dir generated\functions `
  --translation-output-metadata generated\base_translation_output.json --region P

# 3. translate the mod (downloads + validates the signed Retro-WFC payload)
dotnet ...\Translator.Cli.dll translate-mod --project projects\mkwii\recomp.yml --profile retro-rewind `
  --base-manifest build\base\mkwii_base_manifest.json `
  --base-translation-output-metadata generated\base_translation_output.json `
  --code-pul "<RetroRewind6>\Binaries\Code.pul" --mod-root "<RetroRewind6>" `
  --mod-name "Retro Rewind" --region P --out build\mods\retro_rewind_full_cpp `
  --prefer-cached-inputs --emit-cpp --threads 16 `
  --retro-wfc-payload http://nas.play.rwfc.net/payload?g=RMCPD00

# 4. data init + build shards
dotnet ...\Translator.Cli.dll generate-data-init --project projects\mkwii\recomp.yml
dotnet ...\Translator.Cli.dll emit-build-shards --project projects\mkwii\recomp.yml `
  --base-metadata generated\base_translation_output.json --base-functions-dir generated\functions `
  --native-source-dir runtime\src --out generated\build_shards `
  --resolved-profile build\mods\retro_rewind_full_cpp\resolved_dispatch_profile.json `
  --retro-cpp-dir build\mods\retro_rewind_full_cpp\cpp
```

Then configure and build both products:

```powershell
.\Launcher\configure-uwp-msvc.ps1
.\Launcher\build-uwp-msvc.ps1 -Target mkw_release
```


## Installing on an Xbox (Developer Mode)

This repository ships **source only** — no prebuilt package, because an appx contains the statically
recompiled game code built from your own disc. Build it yourself (see [Building](#building)), then
sideload to a console in Developer Mode.

1. **Enable Developer Mode** on the console (Xbox Dev Mode app) and note the console's IP address.
2. **Turn on Device Portal** (Dev Home → Remote Access) and sign in at `https://<console-ip>:11443`
   with your console credentials. The browser will warn about the console's self-signed certificate;
   that is expected.
3. **Sign your package with a certificate you trust.** The appx is self-signed, so the console must
   trust the signing certificate before it will install:
   - Generate a self-signed code-signing certificate (subject can be anything, e.g. `CN=MKWii`) and
     sign the appx with it. `wiicompiled/Launcher/uwp-appx/deploy-elevated.ps1` takes `-PfxPath`,
     `-PfxPassword`, and `-AppxPath` for exactly this.
   - Install the matching `.cer` into the console's **Trusted People** and **Trusted Root** stores
     (on a PC, import it once with `Import-Certificate`; for the console, deploy a package signed by
     it, or import the certificate through Device Portal).
4. **Treat the app as a Game** (required for its full memory budget). In Device Portal → Settings set
   **`DefaultUWPContentTypeToGame = true`**, then reboot the console. Skipping this leaves the app
   registered as an *App* with a small commit budget, which causes crashes during a race.
5. **Deploy** the appx via Device Portal → Apps → Deploy App (or `WinAppDeployCmd`), then launch
   **WiiCompiled** or **Retro Rewind** from the console. A re-deploy of a *higher* version preserves
   the app data / save; a fresh install creates it.
6. **Supply game data on an external USB drive** (see `[paths]` below) and point the config at it.

## Configuration

The runtime seeds a fresh user `Config.toml` from `Config.default.toml` shipped next to the
executable, then falls back to a built-in template. The important section is `[paths]`:

```toml
[paths]
dvd_root = "E:\\DATA"                        # extracted Mario Kart Wii PAL DATA directory
retro_rewind_root = "E:\\RetroRewind\\RetroRewind6"
overlay_roots = ["E:\\RetroRewind"]
```

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

### Retro Rewind product

- **Trailing labels before `}` are now portable.** The mod's C++ emitter could place a continuation
  label immediately before a block's closing brace. That is valid C but ill-formed C++ — Clang
  tolerated it, MSVC rejects it (`C2059: syntax error: '}'`). The translator now emits a null
  statement after such a label.
- **The `.S` data blob avoids MSVC C/C++ flags.** The Retro Rewind translated data blob (`.S`) was
  compiled as part of `mkw_retro_rewind_functions`, so the Clang ASM wrapper received MSVC-only flags
  and failed. On UWP it is now built in its own option-free object target, mirroring the base
  product.
- **RetroRewind gets the C++/CX entry stub.** The CoreWindow entry stub is a per-executable entry
  point, so `RetroRewind` builds it too.

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
