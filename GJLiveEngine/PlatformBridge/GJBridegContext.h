//
//  GJPictureDisplayContext.h
//  GJCaptureTool
//
//  Created by melot on 2017/5/16.
//  Copyright © 2017年 MinorUncle. All rights reserved.
//

#ifndef GJBridegContext_h
#define GJBridegContext_h
#include "GJLiveDefine+internal.h"
#include "GJFormats.h"

typedef GVoid (*AudioFrameOutCallback) (GHandle userData, R_GJPCMFrame* frame);
typedef GVoid (*AACPacketOutCallback)  (GHandle userData, R_GJPacket* packet);
typedef GVoid (*VideoFrameOutCallback) (GHandle userData, R_GJPixelFrame* frame);
typedef GVoid (*H264PacketOutCallback) (GHandle userData, R_GJPacket* packet);
typedef GBool (*FillDataCallback)(GHandle userData, GVoid* data, GInt32* size);
typedef GVoid (*RecodeCompleteCallback) (GHandle userData,const GChar* filePath, GHandle error);
typedef GVoid (*GJStickerUpdateCallback)(GHandle userDate,GLong index,const GHandle ioParm,GBool* ioFinish);
typedef GVoid (*AudioMixFinishCallback) (GHandle userData,const GChar* filePath, GHandle error);

typedef struct _GJPictureDisplayContext{
    GHandle obaque;
    GBool   (*displaySetup)           (struct _GJPictureDisplayContext* context);
    GBool   (*displaySetFormat)       (struct _GJPictureDisplayContext* context, GJPixelType format);
    GVoid   (*displayUnSetup)         (struct _GJPictureDisplayContext* context);
    GVoid   (*displayView)            (struct _GJPictureDisplayContext* context, GJRetainBuffer* image);
    GHandle (*getDispayView)          (struct _GJPictureDisplayContext* context);
}GJPictureDisplayContext;

typedef struct _GJVideoProduceContext{
    GHandle obaque;
    GBool   (*videoProduceSetup)      (struct _GJVideoProduceContext* context, VideoFrameOutCallback callback, GHandle userData);
    GVoid   (*videoProduceUnSetup)    (struct _GJVideoProduceContext* context);
    GBool   (*startProduce)           (struct _GJVideoProduceContext* context);
    GVoid   (*stopProduce)            (struct _GJVideoProduceContext* context);
    GBool   (*startPreview)           (struct _GJVideoProduceContext* context);
    GBool   (*setARScene)             (struct _GJVideoProduceContext* context,GHandle scene);
    GBool   (*setCaptureView)             (struct _GJVideoProduceContext* context,GView view);

    GVoid   (*stopPreview)            (struct _GJVideoProduceContext* context);
    GHandle (*getRenderView)          (struct _GJVideoProduceContext* context);
    GSize   (*getCaptureSize)         (struct _GJVideoProduceContext* context);
    GBool   (*setCameraPosition)      (struct _GJVideoProduceContext* context, GJCameraPosition cameraPosition);
    GBool   (*setOrientation)         (struct _GJVideoProduceContext* context, GJInterfaceOrientation outOrientation);
    GBool   (*setHorizontallyMirror)  (struct _GJVideoProduceContext* context, GBool mirror);
    GBool   (*setPreviewMirror)       (struct _GJVideoProduceContext* context, GBool mirror);
    GBool   (*setStreamMirror)        (struct _GJVideoProduceContext* context, GBool mirror);

    GBool   (*setFrameRate)           (struct _GJVideoProduceContext* context, GInt32 fps);
    GBool   (*setVideoFormat)         (struct _GJVideoProduceContext* context, GJPixelFormat format);
    GHandle (*getFreshDisplayImage)   (struct _GJVideoProduceContext* context);
    
    GBool   (*addSticker)             (struct _GJVideoProduceContext *context, const GVoid *overlays,  GInt32 fps, GJStickerUpdateCallback callback, const GVoid *userData);
    GVoid   (*chanceSticker)          (struct _GJVideoProduceContext* context);

    GBool   (*startTrackImage)        (struct _GJVideoProduceContext* context, const GVoid* images,GCRect initFrame);
    GVoid   (*stopTrackImage)         (struct _GJVideoProduceContext* context);

}GJVideoProduceContext;

typedef struct _GJAudioProduceContext{
    GHandle obaque;
    GBool   (*audioProduceSetup)      (struct _GJAudioProduceContext* context, AudioFrameOutCallback callback, GHandle userData);
    GVoid   (*audioProduceUnSetup)    (struct _GJAudioProduceContext* context);
    GBool   (*setAudioFormat)         (struct _GJAudioProduceContext* context, GJAudioFormat format);
    GBool   (*audioProduceStart)      (struct _GJAudioProduceContext* context);
    GVoid   (*audioProduceStop)       (struct _GJAudioProduceContext* context);
    GBool   (*enableAudioInEarMonitoring)(struct _GJAudioProduceContext* context, GBool enable);
    GBool   (*enableAudioEchoCancellation)(struct _GJAudioProduceContext* context, GBool enable);
    GBool   (*setupMixAudioFile)      (struct _GJAudioProduceContext* context, const GChar* file, GBool loop,AudioMixFinishCallback callback, GHandle userData);
    GBool   (*startMixAudioFileAtTime)(struct _GJAudioProduceContext* context, GUInt64 time);
    GBool   (*setInputGain)           (struct _GJAudioProduceContext* context, GFloat32 inputGain);
    GBool   (*setMixVolume)           (struct _GJAudioProduceContext* context, GFloat32 volume);
    GBool   (*setOutVolume)           (struct _GJAudioProduceContext* context, GFloat32 volume);
    GVoid   (*stopMixAudioFile)       (struct _GJAudioProduceContext* context);
    GBool   (*setMixToStream)         (struct _GJAudioProduceContext* context, GBool should);
    GBool   (*enableReverb)           (struct _GJAudioProduceContext* context, GBool enable);
    GBool   (*enableMeasurementMode)     (struct _GJAudioProduceContext* context, GBool enable);

}GJAudioProduceContext;

typedef struct _GJAudioPlayContext{
    GHandle obaque;
    GBool   (*audioPlaySetup)         (struct _GJAudioPlayContext* context, GJAudioFormat format, FillDataCallback dataCallback, GHandle userData);
    GVoid   (*audioPlayUnSetup)       (struct _GJAudioPlayContext* context);
    GVoid   (*audioPlayCallback)      (struct _GJAudioPlayContext* context, GHandle audioData, GInt32 size);
    GVoid   (*audioStop)              (struct _GJAudioPlayContext* context);
    GBool   (*audioStart)             (struct _GJAudioPlayContext* context);
    GVoid   (*audioPause)             (struct _GJAudioPlayContext* context);
    GBool   (*audioResume)            (struct _GJAudioPlayContext* context);
    GBool   (*audioSetSpeed)          (struct _GJAudioPlayContext* context, GFloat32 speed);
    GFloat32 (*audioGetSpeed)         (struct _GJAudioPlayContext* context);
}GJAudioPlayContext;

typedef struct _GJEncodeToAACContext{
    GHandle obaque;
    GBool   (*encodeSetup)            (struct _GJEncodeToAACContext* context, GJAudioFormat sourceFormat, GJAudioStreamFormat destForamt, AACPacketOutCallback callback,                GHandle userData);
    GVoid   (*encodeUnSetup)          (struct _GJEncodeToAACContext* context);
    GVoid   (*encodeFlush)            (struct _GJEncodeToAACContext* context);
    GVoid   (*encodeFrame)            (struct _GJEncodeToAACContext* context, R_GJPCMFrame* frame);
    AACPacketOutCallback       encodeCompleteCallback;
}GJEncodeToAACContext;

typedef struct _GJAACDecodeContext{
    GHandle obaque;
    pthread_mutex_t lock;

    GBool   (*decodeSetup)            (struct _GJAACDecodeContext* context, GJAudioFormat sourceFormat, GJAudioFormat destForamt, AudioFrameOutCallback callback, GHandle userData);
    GVoid   (*decodeUnSetup)          (struct _GJAACDecodeContext* context);
    GBool   (*decodePacket)           (struct _GJAACDecodeContext* context, R_GJPacket* packet);
    AudioFrameOutCallback           decodeeCompleteCallback;
}GJAACDecodeContext;

typedef struct _GJH264DecodeContext{
    GHandle obaque;
    GBool   (*decodeSetup)            (struct _GJH264DecodeContext* context, GJPixelType format, VideoFrameOutCallback callback, GHandle userData);
    GVoid   (*decodeUnSetup)          (struct _GJH264DecodeContext* context);
    GBool   (*decodePacket)           (struct _GJH264DecodeContext* context, R_GJPacket* packet);
    
    VideoFrameOutCallback      decodeeCompleteCallback;
}GJH264DecodeContext;

typedef struct _GJEncodeToH264eContext{
    GHandle obaque;
    GBool   (*encodeSetup)            (struct _GJEncodeToH264eContext* context, GJPixelFormat format, H264PacketOutCallback callback, GHandle userData);
    GVoid   (*encodeUnSetup)          (struct _GJEncodeToH264eContext* context);
    GBool   (*encodeFrame)            (struct _GJEncodeToH264eContext* context, R_GJPixelFrame* frame);
    GBool   (*encodeSetBitrate)       (struct _GJEncodeToH264eContext* context, GInt32 bitrate);
    GBool   (*encodeSetProfile)       (struct _GJEncodeToH264eContext* context, ProfileLevel profile);
    GBool   (*encodeSetEntropy)       (struct _GJEncodeToH264eContext* context, EntropyMode model);
    GBool   (*encodeSetGop)           (struct _GJEncodeToH264eContext* context, GInt32 gop);
    GBool   (*encodeAllowBFrame)      (struct _GJEncodeToH264eContext* context, GBool allowBframe);
    GBool   (*encodeGetSPS_PPS)       (struct _GJEncodeToH264eContext* context, GUInt8* sps, GInt32* spsSize, GUInt8* pps, GInt32* ppsSize);
    GVoid   (*encodeFlush)            (struct _GJEncodeToH264eContext* context);

    H264PacketOutCallback            encodeCompleteCallback;
}GJEncodeToH264eContext;


extern GVoid GJ_AudioProduceContextCreate(GJAudioProduceContext** context);
extern GVoid GJ_VideoProduceContextCreate(GJVideoProduceContext** context);
extern GVoid GJ_AACDecodeContextCreate(GJAACDecodeContext** context);
extern GVoid GJ_H264DecodeContextCreate(GJH264DecodeContext** context);
extern GVoid GJ_AACEncodeContextCreate(GJEncodeToAACContext** context);
extern GVoid GJ_H264EncodeContextCreate(GJEncodeToH264eContext** context);
extern GVoid GJ_AudioPlayContextCreate(GJAudioPlayContext** context);
extern GVoid GJ_PictureDisplayContextCreate(GJPictureDisplayContext** context);

extern GVoid GJ_AudioProduceContextDealloc(GJAudioProduceContext** context);
extern GVoid GJ_VideoProduceContextDealloc(GJVideoProduceContext** context);
extern GVoid GJ_AACDecodeContextDealloc(GJAACDecodeContext** context);
extern GVoid GJ_H264DecodeContextDealloc(GJH264DecodeContext** context);
extern GVoid GJ_AACEncodeContextDealloc(GJEncodeToAACContext** context);
extern GVoid GJ_H264EncodeContextDealloc(GJEncodeToH264eContext** context);
extern GVoid GJ_AudioPlayContextDealloc(GJAudioPlayContext** context);
extern GVoid GJ_PictureDisplayContextDealloc(GJPictureDisplayContext** context);

#endif /* GJPictureDisplayContext_h */
