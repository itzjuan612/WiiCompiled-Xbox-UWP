#include "pipeline.hpp"

#include "../webgpu/gpu.hpp"
#include "gx_fmt.hpp"
#include "shader_info.hpp"
#include "tracy/Tracy.hpp"

#include <condition_variable>
#include <memory>
#include <mutex>
#include <stdexcept>

#include <absl/container/flat_hash_map.h>

namespace aurora::gx {
static Module Log("aurora::gx");

namespace {
struct ShaderConfigHash {
  size_t operator()(const ShaderConfig& config) const noexcept { return static_cast<size_t>(xxh3_hash(config)); }
};

struct CachedShaderModule {
  std::condition_variable ready;
  wgpu::ShaderModule module;
  bool compiling = true;
};

std::mutex sShaderModuleCacheMutex;
absl::flat_hash_map<ShaderConfig, std::shared_ptr<CachedShaderModule>, ShaderConfigHash> sShaderModuleCache;

wgpu::ShaderModule cached_shader_module(const ShaderConfig& config) {
  std::shared_ptr<CachedShaderModule> entry;
  {
    std::unique_lock lock{sShaderModuleCacheMutex};
    const auto it = sShaderModuleCache.find(config);
    if (it == sShaderModuleCache.end()) {
      entry = std::make_shared<CachedShaderModule>();
      sShaderModuleCache.emplace(config, entry);
    } else {
      entry = it->second;
      entry->ready.wait(lock, [&] { return !entry->compiling; });
      return entry->module;
    }
  }

  // A shader compile can throw (Dawn/DXC failing under the Series S memory ceiling during a busy
  // Retro WFC race is the common case). Left unhandled that both terminates the compiling thread
  // and poisons this cache entry (compiling stays true forever), so every other waiter on the same
  // config would then hang. Reset + wake waiters and drop the failed entry so a later frame can
  // retry, then rethrow so the caller records the miss.
  wgpu::ShaderModule module;
  try {
    module = build_shader(config);
    // build_shader is noexcept: under the Series S memory ceiling Dawn's CreateShaderModule now
    // logs its uncaptured error and returns a null handle instead of aborting. Treat that as a
    // compile failure so the catch below drops the poisoned entry (a later frame retries) and the
    // caller records a miss, rather than caching a dead module that every draw would reuse.
    if (!module.Get()) {
      throw std::runtime_error("shader module compilation failed (Dawn returned no module)");
    }
  } catch (...) {
    std::lock_guard lock{sShaderModuleCacheMutex};
    entry->compiling = false;
    entry->ready.notify_all();
    sShaderModuleCache.erase(config);
    throw;
  }
  {
    std::lock_guard lock{sShaderModuleCacheMutex};
    entry->module = module;
    entry->compiling = false;
  }
  entry->ready.notify_all();
  return module;
}
} // namespace

wgpu::RenderPipeline create_pipeline(const PipelineConfig& config) {
  ZoneScoped;
  const auto shader = cached_shader_module(config.shaderConfig);
  auto pipeline = build_pipeline(config, {}, shader, "GX Pipeline");
  // Same reasoning as cached_shader_module: a null pipeline is a recoverable per-config failure
  // (Dawn already logged it), not a reason to tear the process down. Throwing lets the compile
  // site drop this one pipeline so its draw is skipped this frame and retried when memory frees.
  if (!pipeline.Get()) {
    throw std::runtime_error("pipeline build failed (Dawn returned no pipeline)");
  }
  return pipeline;
}

void clear_shader_module_cache() {
  std::lock_guard lock{sShaderModuleCacheMutex};
  sShaderModuleCache.clear();
}

void render(const DrawData& data, const wgpu::RenderPassEncoder& pass, DrawEncodeState& state,
            bool requireReadyPipeline, const gfx::Range* uniformRangeOverride) {
  if (!gfx::bind_pipeline(data.pipeline, pass, state.currentPipeline, requireReadyPipeline)) {
    return;
  }

  // An interpolated presentation slot re-encodes the identical draw with only this range replaced; overriding here avoids copying the whole DrawData per draw per slot.
  const gfx::Range& uniformRange = uniformRangeOverride != nullptr ? *uniformRangeOverride : data.uniformRange;
  const std::array offsets{uniformRange.offset};
  pass.SetBindGroup(1, gfx::g_uniformBindGroup, offsets.size(), offsets.data());
  // Resolved when the draw was recorded; see GXBindGroups.
  if (data.bindGroups.resolvedTextureBindGroup != nullptr &&
      data.bindGroups.resolvedTextureBindGroup != state.boundTextureBindGroup) {
    wgpuRenderPassEncoderSetBindGroup(pass.Get(), 2, data.bindGroups.resolvedTextureBindGroup, 0, nullptr);
    state.boundTextureBindGroup = data.bindGroups.resolvedTextureBindGroup;
  }
  if (data.dstAlpha != UINT32_MAX) {
    const wgpu::Color color{0.f, 0.f, 0.f, data.dstAlpha / 255.f};
    pass.SetBlendConstant(&color);
  }
  if (!state.indexBufferBound) {
    // Bound once for the pass; draws select their range with firstIndex below.
    pass.SetIndexBuffer(gfx::g_indexBuffer, wgpu::IndexFormat::Uint16, 0, wgpu::kWholeSize);
    state.indexBufferBound = true;
  }
  pass.DrawIndexed(data.indexCount, data.instanceCount,
                   static_cast<uint32_t>(data.idxRange.offset / sizeof(uint16_t)));
}
} // namespace aurora::gx
