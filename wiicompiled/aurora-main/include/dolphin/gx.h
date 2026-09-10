#ifndef DOLPHIN_GX_H
#define DOLPHIN_GX_H

#ifdef __cplusplus
extern "C" {
#endif

#include <dolphin/gx/GXAurora.h>
#include <dolphin/gx/GXBump.h>
#include <dolphin/gx/GXCommandList.h>
#include <dolphin/gx/GXCpu2Efb.h>
#include <dolphin/gx/GXCull.h>
#include <dolphin/gx/GXDispList.h>
#include <dolphin/gx/GXDraw.h>
#include <dolphin/gx/GXExtra.h>
#include <dolphin/gx/GXFifo.h>
#include <dolphin/gx/GXFrameBuffer.h>
// NB: GXGeometry.h is deliberately NOT included inside the extern "C" block below. It declares
// its C functions inside its OWN extern "C" scope, but it also provides a C++-linkage
// convenience overload (the 4-arg GXSetArray, plain C++ scope after that block). Including it
// while this file's extern "C" is still open would give that overload C linkage, which MSVC
// rejects as C2733 ("cannot overload a function with extern C linkage") - Clang tolerates it,
// which is why the bug only surfaced on the MSVC/UWP target. Include it after the block closes.
#include <dolphin/gx/GXGet.h>
#include <dolphin/gx/GXLighting.h>
#include <dolphin/gx/GXManage.h>
#include <dolphin/gx/GXPerf.h>
#include <dolphin/gx/GXPixel.h>
#include <dolphin/gx/GXStruct.h>
#include <dolphin/gx/GXTev.h>
#include <dolphin/gx/GXTexture.h>
#include <dolphin/gx/GXTransform.h>
#include <dolphin/gx/GXVert.h>

#ifdef __cplusplus
}
#endif

// C++-linkage convenience (4-arg GXSetArray) lives in GXGeometry.h's plain C++ scope, so this
// include must come after the extern "C" block above closes (see the note where it was moved).
#include <dolphin/gx/GXGeometry.h>

#endif
