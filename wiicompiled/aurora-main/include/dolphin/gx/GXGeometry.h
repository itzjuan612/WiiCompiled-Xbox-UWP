#ifndef DOLPHIN_GXGEOMETRY_H
#define DOLPHIN_GXGEOMETRY_H

#include <dolphin/gx/GXEnum.h>

#ifdef __cplusplus
extern "C" {
#endif

void GXSetVtxDesc(GXAttr attr, GXAttrType type);
void GXSetSourceVtxDesc(GXAttr attr, GXAttrType type);
void GXSetVtxDescv(GXVtxDescList* list);
void GXClearVtxDesc(void);
void GXSetVtxAttrFmtv(GXVtxFmt vtxfmt, const GXVtxAttrFmtList* list);
void GXSetVtxAttrFmt(GXVtxFmt vtxfmt, GXAttr attr, GXCompCnt cnt, GXCompType type, u8 frac);
void GXSetNumTexGens(u8 nTexGens);
void GXBegin(GXPrimitive type, GXVtxFmt vtxfmt, u16 nverts);
void GXSetTexCoordGen2(GXTexCoordID dst_coord, GXTexGenType func, GXTexGenSrc src_param, u32 mtx, GXBool normalize,
                       u32 postmtx);
void GXSetLineWidth(u8 width, GXTexOffset texOffsets);
void GXSetPointSize(u8 pointSize, GXTexOffset texOffsets);
void GXEnableTexOffsets(GXTexCoordID coord, GXBool line_enable, GXBool point_enable);
#ifdef TARGET_PC
void GXSetArray(GXAttr attr, const void* data, u32 size, u8 stride, bool le);
#define GXSETARRAY(attr, data, size, stride, le) GXSetArray((attr), (data), (size), (stride), (le))
#else
void GXSetArray(GXAttr attr, const void* data, u8 stride);
#define GXSETARRAY(attr, data, size, stride, le) GXSetArray((attr), (data), (stride))
#endif
void GXInvalidateVtxCache(void);

static inline void GXSetTexCoordGen(GXTexCoordID dst_coord, GXTexGenType func, GXTexGenSrc src_param, u32 mtx) {
  GXSetTexCoordGen2(dst_coord, func, src_param, mtx, GX_FALSE, GX_PTIDENTITY);
}

#ifdef __cplusplus
}
#endif

// The 4-arg PC convenience overload has C++ linkage (it forwards to the
// 5-arg C function above, adding a C++ `bool`). It used to be declared inside
// the extern "C" block, which Clang tolerated but MSVC rejects as C2733
// ("cannot overload a function with extern C linkage"). Declaring it here, in
// plain C++ scope, is identical for Clang (overload resolution is unchanged)
// and valid for MSVC.
#ifdef __cplusplus
#ifdef TARGET_PC
static inline void GXSetArray(GXAttr attr, const void* data, u32 size, u8 stride) {
  GXSetArray(attr, data, size, stride, false);
}
#endif
#endif

#endif
