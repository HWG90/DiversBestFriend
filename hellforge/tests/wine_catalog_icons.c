/* Standalone Wine/Windows check against a player's real HFIC v2. Run the exe
 * from mods/<fixture>/ with mods/hellforge-editor/game-icons.bin beside it.
 * Pass that catalog path as argv[1]. WIC imports are test-only. */
#define COBJMACROS
#include <windows.h>
#include <wincodec.h>
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "editor_catalog_icons.h"
#include "kind_names_25480438.h"

static BYTE* rgba;
static int width, height, loads, draws;
static const BYTE* mask[2];
static unsigned mw[2], mh[2], channels[2];

static int load(const char* path, int* w, int* h)
{
    wchar_t wide[1024];
    assert(MultiByteToWideChar(CP_UTF8,0,path,-1,wide,1024));
    IWICImagingFactory* factory;
    IWICBitmapDecoder* decoder;
    IWICBitmapFrameDecode* frame;
    IWICFormatConverter* converter;
    assert(SUCCEEDED(CoCreateInstance(&CLSID_WICImagingFactory,NULL,CLSCTX_INPROC_SERVER,
                                      &IID_IWICImagingFactory,(void**)&factory)));
    assert(SUCCEEDED(IWICImagingFactory_CreateDecoderFromFilename(factory,wide,NULL,GENERIC_READ,
                                      WICDecodeMetadataCacheOnDemand,&decoder)));
    assert(SUCCEEDED(IWICBitmapDecoder_GetFrame(decoder,0,&frame)));
    assert(SUCCEEDED(IWICImagingFactory_CreateFormatConverter(factory,&converter)));
    assert(SUCCEEDED(IWICFormatConverter_Initialize(converter,(IWICBitmapSource*)frame,&GUID_WICPixelFormat32bppRGBA,
                                      WICBitmapDitherTypeNone,NULL,0,WICBitmapPaletteTypeCustom)));
    UINT ww,hh;
    assert(SUCCEEDED(IWICFormatConverter_GetSize(converter,&ww,&hh)));
    assert(ww && hh && ww<=4096 && hh<=4096);
    rgba=malloc(ww*hh*4);
    assert(rgba && SUCCEEDED(IWICFormatConverter_CopyPixels(converter,NULL,ww*4,ww*hh*4,rgba)));
    IWICFormatConverter_Release(converter);
    IWICBitmapFrameDecode_Release(frame);
    IWICBitmapDecoder_Release(decoder);
    IWICImagingFactory_Release(factory);
    *w=width=(int)ww; *h=height=(int)hh;
    ++loads;
    return 17;
}

static uint32_t theme(int token) { return (uint32_t)token; }

static void draw(int id,float x,float y,float right,float bottom,float u,float v,float u1,float v1,uint32_t tint)
{
    unsigned k=draws++;
    assert(id==17 && k<2 && mask[k]);
    assert(x>=10 && y>=20 && right<=34 && bottom<=44 && right>x && bottom>y);
    assert(tint==theme(k ? OV_THEME_TEXT : OV_THEME_GOLD));
    unsigned ax=(unsigned)(u*width+0.5f), ay=(unsigned)(v*height+0.5f);
    assert((unsigned)(u1*width+0.5f)==ax+mw[k] && (unsigned)(v1*height+0.5f)==ay+mh[k]);
    for (unsigned j=0;j<mh[k];++j) for (unsigned i=0;i<mw[k];++i) {
        const BYTE* pixel=rgba+4*((ay+j)*width+ax+i);
        const BYTE* source=mask[k]+channels[k]*(mw[k]*j+i);
        if (channels[k]==1) {
            assert(pixel[3]==source[0]);
            if (pixel[3]) assert(pixel[0]==255 && pixel[1]==255 && pixel[2]==255);
        } else assert(!memcmp(pixel,source,4));
    }
}

int main(int argc,char** argv)
{
    assert(argc==2 && SUCCEEDED(CoInitializeEx(NULL,COINIT_MULTITHREADED)));
    if (!strcmp(argv[1],"--unavailable")) {
        OvApi api={0};
        api.version=3; api.size=sizeof api; api.theme=theme; api.load_image=load; api.draw_image_uv=draw;
        assert(!editor_stratagem_icon(&api,"Resupply",10,20,24));
        assert(!loads && !draws);
        CoUninitialize();
        puts("PASS: unavailable or malformed HFIC produced no texture");
        return 0;
    }
    FILE* f=fopen(argv[1],"rb"); assert(f);
    assert(!fseek(f,0,SEEK_END)); long n=ftell(f); assert(n>=12 && n<=64*1024*1024);
    rewind(f); BYTE* src=malloc(n); assert(src && fread(src,1,n,f)==(size_t)n); fclose(f);
    OvApi api={0}; api.version=2; api.size=sizeof api; api.theme=theme; api.load_image=load; api.draw_image_uv=draw;
    assert(!editor_stratagem_icon(&api,"Resupply",10,20,24) && !loads);
    api.version=3; api.size=offsetof(OvApi,draw_image_uv);
    assert(!editor_stratagem_icon(&api,"Resupply",10,20,24) && !loads);
    api.size=sizeof api;
    assert(!editor_stratagem_icon(&api,"Resupply",10,20,24) && loads==1);
    unsigned hits=0;
    for (unsigned kind=1;kind<sizeof dbf_kind_names/sizeof *dbf_kind_names;++kind) {
        const char* name=dbf_kind_names[kind];
        if (!name) continue;
        memset(mask,0,sizeof mask);
        for (long pos=12;pos<n;) {
            assert(n-pos>=7);
            BYTE type=src[pos++], len=src[pos++];
            assert(n-pos>=len+5);
            BYTE* key=src+pos; pos+=len;
            unsigned w=src[pos]|(src[pos+1]<<8), h=src[pos+2]|(src[pos+3]<<8), c=src[pos+4];
            pos+=5;
            assert(w<=1024 && h<=1024 && (c==1 || c==4) && n-pos>=(long)(w*h*c));
            if ((type==2 || type==3) && strlen(name)==len && !memcmp(key,name,len)) {
                unsigned k=type-2; mask[k]=src+pos; mw[k]=w; mh[k]=h; channels[k]=c;
            }
            pos+=w*h*c;
        }
        draws=0;
        bool expected=mask[0] && mask[1];
        assert(editor_stratagem_icon(&api,name,10,20,24)==expected);
        assert(draws==(expected ? 2 : 0)); hits+=expected;
    }
    assert(hits && loads==1);
    printf("PASS: %u target names, both masks pixel-checked after WIC decoding; one texture\n",hits);
    free(rgba);free(src);CoUninitialize();
    return 0;
}
