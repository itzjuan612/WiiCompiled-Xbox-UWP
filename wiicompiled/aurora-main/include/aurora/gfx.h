#ifndef AURORA_GFX_H
#define AURORA_GFX_H

#ifdef __cplusplus
#include <cstddef>
#include <cstdint>

extern "C" {
#else
#include "stddef.h"
#include "stdint.h"
#endif

#ifndef NDEBUG
#define AURORA_GFX_DEBUG_GROUPS
#endif

void aurora_push_debug_group(const char* label);
void aurora_pop_debug_group();

typedef struct {
  uint32_t queuedPipelines;
  uint32_t createdPipelines;
  uint32_t drawCallCount;
  uint32_t mergedDrawCallCount;
  uint32_t lastVertSize;
  uint32_t lastUniformSize;
  uint32_t lastIndexSize;
  uint32_t lastStorageSize;
  uint32_t lastTextureUploadSize;
  uint32_t presentedFrameCount;
  uint32_t interpolatedFrameCount;
  // Texture uploads that did not fit the staging region and had to be streamed through a
  // transient buffer of their own. Cumulative since init, so a screen that bursts them once is
  // still visible to a low-frequency sampler: read the delta between samples, not the value.
  uint64_t totalSpilledUploads;
  uint64_t totalSpilledBytes;
  // How much the emulated CPU spends stalled inside the renderer, and the EFB texture copies that
  // usually cause it (each one can force a mid-frame submit and a wait for the frame worker).
  // Cumulative since init, so the delta between two coarse samples is what matters.
  uint64_t totalWorkerWaitUs;
  uint64_t totalWorkerWaits;
  uint64_t totalTexCopies;
  uint64_t totalPersistentTexCopies;
  // Wall time the EFB->texture copy resolves spent on the thread that issued them (the emulated CPU
  // thread), so it looks like emulated work from the outside.
  uint64_t totalCopyResolveUs;
  // FIFO drains: each one decodes a batch of GX commands on the calling thread and lets the current
  // frame be sealed/encoded, so a screen that forces many per frame pays for all of them serially.
  uint64_t totalFifoDrains;
  uint64_t totalFifoDrainUs;
  // Raw bridge draws (menu/HUD g3d). Each grabs renderer_gpu_mutex to push vertices and record the
  // draw, so when the async frame worker holds that lock to seal/encode, the producing thread blocks
  // here. A screen with hundreds of draws/frame can serialise entirely behind the worker.
  uint64_t totalRawDrawLockUs;
  uint64_t totalRawDraws;
  // Full guarded region of a raw draw (lock held through push_verts + record). Subtracting the
  // lock-wait above isolates the recording work from lock contention.
  uint64_t totalRawDrawUs;
  // EFB->RAM read-backs the guest demanded. Each one finishes the frame still being recorded on the
  // producer thread (mid-frame submit, wait for the frame worker, resume), so a few per frame is a
  // large stall even though it looks like emulated-CPU time from the outside.
  uint64_t totalEfbReadbacks;
  uint64_t totalEfbReadbackUs;
  // Texture uploads dropped because the staging map/allocation returned a null base (memory
  // pressure on the shared Xbox CPU/GPU heap). Non-zero means an upload was skipped to avoid
  // writing through a null pointer - the old failure mode was a hard access violation here.
  uint64_t totalNullMapWrites;
} AuroraStats;

typedef struct {
  uint64_t totalPresentCount;
  uint32_t sampleCount;
  double framesPerSecond;
  double averageFrameTimeMs;
  double p95FrameTimeMs;
  double jitterMs;
  // framesPerSecond with duplicated presentation slots scaled out, so this is the rate of frames
  // that carried new motion. Equal to framesPerSecond when every slot replayed real interpolation.
  double effectiveFramesPerSecond;
} AuroraPresentTiming;

const AuroraStats* aurora_get_stats();
void aurora_get_present_timing(AuroraPresentTiming* timing);

// Free bytes left in the app's memory budget (GlobalMemoryStatusEx ullAvailPhys). On Xbox UWP this
// is the remaining app target, so it reads as the margin before the OS/allocator starts failing.
uint64_t aurora_available_physical_memory();

// Interpolation health: the per-frame fields describe the last sealed frame, the counters
// accumulate since it was configured. This answers "output FPS dropped but the game held 60".
typedef struct {
  uint32_t targetFps;          // configured target, 0 when interpolation is off
  uint32_t targetSamples;      // slots the pacing controller currently aims for
  uint32_t activeSamples;      // slots latched for the latest sealed frame
  uint32_t candidates;         // perspective draws in the latest sealed frame
  uint32_t matchable;          // candidates whose identity also existed last frame
  uint32_t matches;            // draws matched to the previous frame
  uint32_t eligible;           // latest frame inserted interpolated slots
  uint32_t replaySafe;         // latest frame could replay its command stream
  uint64_t framesSealed;
  uint64_t framesLowMatch;
  uint64_t framesReplayUnsafe;
  uint64_t slotReductions;
  uint64_t lateSealDrops;
} AuroraFrameInterpolationDiagnostics;

void aurora_get_frame_interpolation_diagnostics(AuroraFrameInterpolationDiagnostics* diagnostics);

// Generates transform-interpolated perspective frames between consecutive 60 Hz logical frames.
// Supported targets are 0 (off), 120, 180 and 240. Guest simulation and VI timing are unchanged.
void aurora_set_frame_interpolation_fps(uint32_t targetFps);
uint32_t aurora_get_frame_interpolation_fps();

// Newly encountered GX pipelines compile on the bounded worker queue. Draws whose pipeline is not
// ready are skipped rather than stalling submission, and pick it up once compilation finishes.
void aurora_set_skip_unready_pipelines(bool enabled);
bool aurora_get_skip_unready_pipelines();
uint32_t aurora_get_queued_pipeline_count();

// Controls whether display copies bypass the Wii's vertical copy filter.
void aurora_set_disable_copy_filter(bool disabled);
bool aurora_get_disable_copy_filter();

// Guest-RAM write tracking. `generation` changes whenever guest RAM covering a host range was
// written (or returns AURORA_GUEST_WRITE_UNTRACKED); `notify` reports writes aurora made itself.
#define AURORA_GUEST_WRITE_UNTRACKED UINT64_MAX
typedef uint64_t (*AuroraGuestWriteGenerationCallback)(const void* hostPtr, size_t size);
typedef void (*AuroraGuestWriteNotifyCallback)(const void* hostPtr, size_t size);
void aurora_set_guest_write_hooks(AuroraGuestWriteGenerationCallback generation,
                                  AuroraGuestWriteNotifyCallback notify);

#ifdef __cplusplus
}
#endif

#endif
