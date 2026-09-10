// pres_test.exe - Xbox console presentation probe (Option C viability test)
//
// Answers, in one console run, three questions:
//   Q1 (load + imports): does a plain x86-64 PE built by our Clang/llvm-mingw
//      toolchain load on the console, and does the console provide the standard
//      d3d12.dll / dxgi.dll / user32.dll / gdi32.dll it imports?
//   Q2 (GPU render): does D3D12CreateDevice + a clear actually rasterize on the
//      console GPU? (Proven by reading a back buffer back to a BMP file.)
//   Q3 (present): does a CreateSwapChainForHwnd back buffer reach the TV?
//      (Needs a human looking at the screen - the test prints what to look for.)
//
// Everything observable is written to FILES in the current working directory
// (on the console that is the folder the exe is launched from, typically the
// SMB share): pres_test.log and pres_frame.bmp. No reliance on stdout.
//
// Build (native Win32 target - NOT the UWP wrapper):
//   x86_64-w64-mingw32-clang++ -O2 -static -static-libgcc -static-libstdc++ \
//       -o pres_test.exe pres_test.cpp -ld3d12 -ldxgi -luser32 -lgdi32
//
// Static CRT => the only dynamic imports left are the OS/DX DLLs above, which
// is exactly the import set Q1 is probing.

#include <windows.h>
#include <d3d12.h>
#include <dxgi1_6.h>
#include <stdio.h>
#include <stdarg.h>
#include <string.h>
#include <stdlib.h>
#include <math.h>

static FILE* g_log = nullptr;
static const char* g_logName = "pres_test.log";

static void Log(const char* fmt, ...) {
    if (!g_log) return;
    va_list ap; va_start(ap, fmt);
    vfprintf(g_log, fmt, ap);
    va_end(ap);
    fputc('\n', g_log);
    fflush(g_log);
}

static void LogErr(const char* what, HRESULT hr) {
    Log("%s -> HRESULT 0x%08X", what, (unsigned)hr);
}

// Top-down 32-bit BGRA (row-compacted to w*4) -> BMP (B,G,R,X).
static void WriteBMP(const unsigned char* bgra, int w, int h, const char* path) {
    int rowBytes = w * 4;
    int imgSize = rowBytes * h;
    BITMAPFILEHEADER fh = {};
    fh.bfType = (unsigned short)('M' | ('B' << 8));
    fh.bfSize = sizeof(fh) + sizeof(BITMAPINFOHEADER) + imgSize;
    fh.bfOffBits = sizeof(fh) + sizeof(BITMAPINFOHEADER);
    BITMAPINFOHEADER ih = {};
    ih.biSize = sizeof(ih);
    ih.biWidth = w;
    ih.biHeight = -h;          // negative => top-down
    ih.biPlanes = 1;
    ih.biBitCount = 32;
    FILE* f = fopen(path, "wb");
    if (!f) { Log("WriteBMP: cannot open %s", path); return; }
    fwrite(&fh, 1, sizeof(fh), f);
    fwrite(&ih, 1, sizeof(ih), f);
    fwrite(bgra, 1, imgSize, f);
    fclose(f);
    Log("Wrote %dx%d BMP -> %s", w, h, path);
}

static LRESULT CALLBACK WndProc(HWND h, UINT m, WPARAM w, LPARAM l) {
    if (m == WM_DESTROY) { PostQuitMessage(0); return 0; }
    return DefWindowProcW(h, m, w, l);
}

// Signal the fence and wait for it to complete on the CPU.
static void WaitFence(ID3D12Fence* fence, HANDLE fenceEvent, UINT64* fenceVal) {
    (*fenceVal)++;
    fence->SetEventOnCompletion(*fenceVal, fenceEvent);
    WaitForSingleObject(fenceEvent, 3000);
    ResetEvent(fenceEvent);
}

int main(int argc, char** argv) {
    DWORD runSeconds = 30;
    if (argc > 1) runSeconds = (DWORD)atoi(argv[1]);

    char cwd[4096];
    GetCurrentDirectoryA((DWORD)sizeof(cwd), cwd);
    char logPath[4600], bmpPath[4600];
    snprintf(logPath, sizeof(logPath), "%s\\%s", cwd, g_logName);
    snprintf(bmpPath, sizeof(bmpPath), "%s\\pres_frame.bmp", cwd);
    g_log = fopen(logPath, "w");
    if (!g_log) return 2;
    Log("==== pres_test start ====");
    Log("CWD: %s", cwd);
    Log("run_seconds: %lu", runSeconds);
    Log("PE: x86-64, statically linked CRT (imports: kernel32,user32,gdi32,d3d12,dxgi)");

    // ---- Q1a: create the D3D12 device (also forces d3d12.dll import to resolve) ----
    ID3D12Device* device = nullptr;
    HRESULT hr = D3D12CreateDevice(nullptr, D3D_FEATURE_LEVEL_11_0, IID_PPV_ARGS(&device));
    LogErr("D3D12CreateDevice", hr);
    if (FAILED(hr)) { Log("RESULT: FAIL at device creation (Q1/Q2). Console may not expose D3D12."); return 1; }
    Log("Q1/Q2: device created OK");

    // ---- Q1b: DXGI factory (forces dxgi.dll import) ----
    IDXGIFactory2* factory = nullptr;
    hr = CreateDXGIFactory2(0, IID_PPV_ARGS(&factory));
    LogErr("CreateDXGIFactory2", hr);
    if (FAILED(hr)) { Log("RESULT: FAIL at DXGI factory."); return 1; }
    Log("Q1: DXGI factory OK");

    // Log adapter descriptions (which GPU did we get?).
    for (UINT i = 0; ; ++i) {
        IDXGIAdapter1* a = nullptr;
        if (factory->EnumAdapters1(i, &a) != S_OK) break;
        DXGI_ADAPTER_DESC1 d; a->GetDesc1(&d);
        char desc[512]; WideCharToMultiByte(CP_UTF8, 0, d.Description, -1, desc, sizeof(desc), nullptr, nullptr);
        Log("Adapter[%u]: %s  vendor=%04X dev=%04X VRAM=%lluMB", i, desc, d.VendorId, d.DeviceId, (unsigned long long)(d.DedicatedVideoMemory / (1024*1024)));
        a->Release();
    }

    // ---- Q3 setup: window ----
    WNDCLASSEXW wc = { sizeof(wc) };
    wc.lpfnWndProc = WndProc;
    wc.hInstance = GetModuleHandleW(nullptr);
    wc.lpszClassName = L"PresTest";
    wc.hCursor = LoadCursorW(nullptr, IDC_ARROW);
    RegisterClassExW(&wc);
    const int W = 1920, H = 1080;
    HWND hwnd = CreateWindowExW(0, L"PresTest", L"pres_test", WS_POPUP, 0, 0, W, H, nullptr, nullptr, wc.hInstance, nullptr);
    Log("CreateWindowExW hwnd=%p", hwnd);
    if (!hwnd) { Log("RESULT: FAIL at window creation (user32)."); return 1; }
    ShowWindow(hwnd, SW_SHOW);
    UpdateWindow(hwnd);
    Log("Q3: window shown (look for a 1920x1080 fullscreen window)");

    // ---- Q3 setup: swapchain for the hwnd (the REAL app's present path) ----
    IDXGISwapChain1* sc = nullptr;
    DXGI_SWAP_CHAIN_DESC1 sd = {};
    sd.Width = W; sd.Height = H;
    sd.Format = DXGI_FORMAT_B8G8R8A8_UNORM;
    sd.SampleDesc.Count = 1;
    sd.BufferUsage = DXGI_USAGE_RENDER_TARGET_OUTPUT;
    sd.BufferCount = 3;
    sd.SwapEffect = DXGI_SWAP_EFFECT_FLIP_DISCARD;
    sd.AlphaMode = DXGI_ALPHA_MODE_IGNORE;
    hr = factory->CreateSwapChainForHwnd(device, hwnd, &sd, nullptr, nullptr, &sc);
    LogErr("CreateSwapChainForHwnd", hr);
    if (FAILED(hr)) {
        Log("RESULT: device OK but swapchain failed. Next probe variant: CreateSwapChainForComposition / direct CreateSwapChain.");
        return 1;
    }
    Log("Q3: swapchain (hwnd) created");

    UINT bufCount = 3;
    sc->GetBufferCount(&bufCount);
    ID3D12Resource* backBuf[3] = { nullptr, nullptr, nullptr };
    for (UINT i = 0; i < bufCount && i < 3; ++i) {
        sc->GetBuffer(i, IID_PPV_ARGS(&backBuf[i]));
    }

    // ---- RTV heap ----
    ID3D12DescriptorHeap* rtvHeap = nullptr;
    D3D12_DESCRIPTOR_HEAP_DESC rtd = {};
    rtd.Type = D3D12_DESCRIPTOR_HEAP_TYPE_RTV;
    rtd.NumDescriptors = bufCount;
    rtd.Flags = D3D12_DESCRIPTOR_HEAP_FLAG_NONE;
    device->CreateDescriptorHeap(&rtd, IID_PPV_ARGS(&rtvHeap));
    UINT rtvSize = device->GetDescriptorHandleIncrementSize(D3D12_DESCRIPTOR_HEAP_TYPE_RTV);
    for (UINT i = 0; i < bufCount; ++i) {
        D3D12_RENDER_TARGET_VIEW_DESC v = {};
        v.Format = DXGI_FORMAT_B8G8R8A8_UNORM;
        v.ViewDimension = D3D12_RTV_DIMENSION_TEXTURE2D;
        v.FirstSlice = 0;
        device->CreateRenderTargetView(backBuf[i], &v,
            CPU_DESCRIPTOR_HANDLE{ rtvHeap->GetCPUDescriptorHandleForHeapStart().ptr + i * rtvSize });
    }

    // ---- command allocator / list / fence ----
    // No root signature is needed: ClearRenderTargetView and CopyResource
    // execute fine on a list created with a null root signature.
    ID3D12CommandAllocator* alloc = nullptr;
    device->CreateCommandAllocator(D3D12_COMMAND_LIST_TYPE_DIRECT, IID_PPV_ARGS(&alloc));
    ID3D12GraphicsCommandList* list = nullptr;
    device->CreateCommandList(0, D3D12_COMMAND_LIST_TYPE_DIRECT, alloc, nullptr, IID_PPV_ARGS(&list));
    list->Close();
    ID3D12Fence* fence = nullptr;
    device->CreateFence(0, D3D12_FENCE_FLAG_NONE, IID_PPV_ARGS(&fence));
    HANDLE fenceEvent = CreateEventW(nullptr, FALSE, FALSE, nullptr);
    UINT64 fenceVal = 1;

    // ---- staging buffer for readback (Q2 proof) ----
    ID3D12Resource* staging = nullptr;
    D3D12_RESOURCE_DESC tex = {};
    tex.Dimension = D3D12_RESOURCE_DIMENSION_TEXTURE2D;
    tex.Width = W; tex.Height = H; tex.MipLevels = 1; tex.ArraySize = 1;
    tex.Format = DXGI_FORMAT_B8G8R8A8_UNORM;
    tex.SampleDesc.Count = 1;
    {
        D3D12_RESOURCE_FOOTPRINT fp; UINT numRows; UINT64 bufSize;
        device->GetCopyableFootprints(&tex, 0, 1, 0, &fp, &numRows, &bufSize);
        D3D12_HEAP_DESC hdesc = {};
        hdesc.SizeInBytes = bufSize;
        hdesc.Alignment = 0;
        hdesc.Properties.Type = D3D12_HEAP_TYPE_READWRITE;
        hdesc.Flags = D3D12_HEAP_FLAG_NONE;
        device->CreateCommittedResource(&hdesc, D3D12_HEAP_FLAG_NONE, D3D12_RESOURCE_STATE_COPY_DEST, nullptr, IID_PPV_ARGS(&staging));
    }

    Log("D3D12 init complete. Starting %lu-second frame loop (cycling color).", runSeconds);
    Log("ON THE TV: expect a fullscreen window whose color cycles red->green->blue->...");

    ID3D12CommandList* cl[1] = { (ID3D12CommandList*)list };

    // ---- frame loop ----
    LARGE_INTEGER freq, t0;
    QueryPerformanceFrequency(&freq);
    QueryPerformanceCounter(&t0);
    UINT64 frame = 0, lastReadback = 0;
    MSG msg = {};
    int exitReason = 0;
    while (true) {
        while (PeekMessageW(&msg, nullptr, 0, 0, PM_REMOVE)) {
            if (msg.message == WM_QUIT) { exitReason = 1; break; }
            TranslateMessage(&msg); DispatchMessageW(&msg);
        }
        if (exitReason) break;
        LARGE_INTEGER now; QueryPerformanceCounter(&now);
        double secs = (now.QuadPart - t0.QuadPart) / (double)freq.QuadPart;
        if (secs >= runSeconds) break;

        // cycling color: r/g/b sweep with different periods
        float r = 0.5f + 0.5f * (float)sinf((double)secs * 1.3);
        float g = 0.5f + 0.5f * (float)sinf((double)secs * 2.1 + 1.0);
        float b = 0.5f + 0.5f * (float)sinf((double)secs * 2.9 + 2.0);

        alloc->Reset();
        list->Reset(alloc, nullptr);

        UINT cur = sc->GetCurrentBackBufferIndex();
        D3D12_RESOURCE_BARRIER rb = {};
        rb.Type = D3D12_RESOURCE_BARRIER_TYPE_TRANSITION;
        rb.Transition.pResource = backBuf[cur];
        rb.Transition.Subresource = D3D12_RESOURCE_BARRIER_ALL_SUBRESOURCES;
        rb.Transition.StateBefore = D3D12_RESOURCE_STATE_PRESENT;
        rb.Transition.StateAfter = D3D12_RESOURCE_STATE_RENDER_TARGET;
        list->ResourceBarrier(1, &rb);

        FLOAT clr[4] = { r, g, b, 1.0f };
        CPU_DESCRIPTOR_HANDLE rtv{ rtvHeap->GetCPUDescriptorHandleForHeapStart().ptr + (UINT64)cur * rtvSize };
        list->ClearRenderTargetView(rtv, clr, 0, nullptr);

        rb.Transition.StateBefore = D3D12_RESOURCE_STATE_RENDER_TARGET;
        rb.Transition.StateAfter = D3D12_RESOURCE_STATE_PRESENT;
        list->ResourceBarrier(1, &rb);

        list->Signal(fence);
        list->Close();
        device->ExecuteCommandLists(1, cl);
        sc->Present(1, 0);          // vsync
        WaitFence(fence, fenceEvent, &fenceVal);

        // Read back every ~60 frames to produce a BMP proof of GPU rendering (Q2).
        if (frame >= lastReadback + 60 && staging) {
            alloc->Reset();
            list->Reset(alloc, nullptr);
            D3D12_RESOURCE_BARRIER cb = {};
            cb.Type = D3D12_RESOURCE_BARRIER_TYPE_TRANSITION;
            cb.Transition.pResource = backBuf[cur];
            cb.Transition.Subresource = D3D12_RESOURCE_BARRIER_ALL_SUBRESOURCES;
            cb.Transition.StateBefore = D3D12_RESOURCE_STATE_PRESENT;
            cb.Transition.StateAfter = D3D12_RESOURCE_STATE_COPY_SOURCE;
            list->ResourceBarrier(1, &cb);
            list->CopyResource(staging, backBuf[cur]);
            cb.Transition.StateBefore = D3D12_RESOURCE_STATE_COPY_SOURCE;
            cb.Transition.StateAfter = D3D12_RESOURCE_STATE_PRESENT;
            list->ResourceBarrier(1, &cb);

            list->Signal(fence);
            list->Close();
            device->ExecuteCommandLists(1, cl);
            WaitFence(fence, fenceEvent, &fenceVal);

            void* map = nullptr;
            if (SUCCEEDED(staging->Map(0, nullptr, &map))) {
                D3D12_RESOURCE_FOOTPRINT fp; UINT numRows; UINT64 bufSize;
                device->GetCopyableFootprints(&tex, 0, 1, 0, &fp, &numRows, &bufSize);
                unsigned char* out = (unsigned char*)malloc((size_t)W * H * 4);
                const unsigned char* src = (const unsigned char*)map;
                for (int y = 0; y < H; ++y)
                    memcpy(out + (size_t)y * W * 4, src + (size_t)y * fp.RowPitch, (size_t)W * 4);
                int cx = W/2, cy = H/2;
                Log("frame %llu: readback center pixel BGR=(%d,%d,%d)  expect ~(%d,%d,%d)",
                    frame,
                    (int)out[(size_t)(cy*W+cx)*4+0],
                    (int)out[(size_t)(cy*W+cx)*4+1],
                    (int)out[(size_t)(cy*W+cx)*4+2],
                    (int)(b*255), (int)(g*255), (int)(r*255));
                WriteBMP(out, W, H, bmpPath);
                free(out);
                staging->Unmap(0, nullptr);
            } else {
                Log("frame %llu: staging Map FAILED (fence not complete?)", frame);
            }
            lastReadback = frame;
        }
        frame++;
    }

    Log("==== pres_test complete (%llu frames) ====", frame);
    Log("Interpretation:");
    Log(" - log shows device+swapchain OK and you SAW the cycling color on TV  => Q1=PASS Q2=PASS Q3=PASS  (Option C viable)");
    Log(" - log shows OK but TV stayed BLACK                                  => device renders (check BMP) but present not composited; try CreateSwapChainForComposition variant");
    Log(" - BMP center pixel matches expected color                            => Q2=PASS (GPU rasterized) independent of TV");
    Log(" - device creation FAILED                                             => Q1=FAIL (console needs GDK/MSVC path)");

    // cleanup
    if (staging) staging->Release();
    if (fence) fence->Release();
    if (list) list->Release();
    if (alloc) alloc->Release();
    if (rtvHeap) rtvHeap->Release();
    for (UINT i = 0; i < bufCount; ++i) if (backBuf[i]) backBuf[i]->Release();
    if (sc) sc->Release();
    if (factory) factory->Release();
    if (device) device->Release();
    if (g_log) fclose(g_log);
    return 0;
}
