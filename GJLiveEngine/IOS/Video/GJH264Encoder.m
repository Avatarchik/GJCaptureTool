//
//  GJH264Encoder.m
//  视频录制
//
//  Created by tongguan on 15/12/28.
//  Copyright © 2015年 未成年大叔. All rights reserved.
//

#import "GJH264Encoder.h"
#import "GJLiveDefine+internal.h"
#import "GJLog.h"
#import "GJRetainBufferPool.h"
#import "GJUtil.h"
//#define DEFAULT_DELAY  10
//默认i帧是p帧的I_P_RATE+1倍。越小丢帧时码率降低越大

#define DEFAULT_CHECK_DELAY 1000
#define DROP_BITRATE_RATE 0.1

@interface GJH264Encoder () {
    GInt64 _fristPts;
    GBool  _shouldRestart;
    BOOL   requestFlush;
    GTime _fristTime;
    GTime _preDTS;
#ifdef NETWORK_DELAY
    GTime _dtsDelta;
#endif
}
@property (nonatomic, assign) VTCompressionSessionRef enCodeSession;
@property (nonatomic, assign) GJRetainBufferPool *    bufferPool;
//@property(nonatomic,assign)GInt32 currentBitRate;//当前码率

@end

@implementation GJH264Encoder

- (instancetype)initWithSourceSize:(CGSize)size {
    self = [super init];
    if (self) {
        _sourceSize = size;
        _bitrate    = 600;
        ;
        //        _allowMinBitRate = _currentBitRate;
        _allowBFrame = YES;

        _profileLevel = profileLevelMain;
        _entropyMode  = EntropyMode_CABAC;
        _fristPts     = GINT64_MAX;
#ifdef NETWORK_DELAY
        _dtsDelta     = 0;
#endif
        _fristTime    = -1;
        _preDTS     = -1;
        [self creatEnCodeSession];
    }
    return self;
}

//编码
- (BOOL)encodeImageBuffer:(CVImageBufferRef)imageBuffer pts:(int64_t)pts {

    if (_fristTime < 0) {
        _fristTime = GJ_Gettime()/1000;
    }
    //RETRY:
    {
        //    CMTime presentationTimeStamp = CMTimeMake(encoderFrameCount*1000.0/_destFormat.baseFormat.fps, 1000);

        NSMutableDictionary *properties = NULL;
        if (_enCodeSession == nil) {
            [self creatEnCodeSession];
            [self setAllParm];
        }
        if (requestFlush) {
            properties = [[NSMutableDictionary alloc] init];
            [properties setObject:@YES forKey:(__bridge NSString *) kVTEncodeFrameOptionKey_ForceKeyFrame];
            requestFlush = NO;
        }
        //        printf("encode pts:%lld\n",pts);
        OSStatus status = VTCompressionSessionEncodeFrame(
            _enCodeSession,
            imageBuffer,
            CMTimeMake(pts, 1000), //pts能得到dts和pts
            kCMTimeInvalid,        // may be kCMTimeInvalid ,dts只能得到dts
            (__bridge CFDictionaryRef) properties,
            NULL,
            NULL);

        if (status == 0) {
            _encodeframeCount++;
            return YES;
        } else {
            if (status == kVTInvalidSessionErr) {
                GJLOG(DEFAULT_LOG, GJ_LOGWARNING, "编码失败 kVTInvalidSessionErr:%d,重新编码", status);
                VTCompressionSessionInvalidate(_enCodeSession);
                _enCodeSession = nil;
                [self creatEnCodeSession];
                [self setAllParm];
                //                goto RETRY;//不重试，防止占用太多时间
            } else {
                GJLOG(DEFAULT_LOG, GJ_LOGFORBID, "编码失败：%d", status);
            }
            _shouldRestart = YES;
            return NO;
        }
    }
}

- (void)creatEnCodeSession {
    if (_enCodeSession != nil) {
        VTCompressionSessionInvalidate(_enCodeSession);
    }
    _shouldRestart  = NO;
    OSStatus result = VTCompressionSessionCreate(
        NULL,
        (int32_t) _sourceSize.width,
        (int32_t) _sourceSize.height,
        kCMVideoCodecType_H264,
        NULL,
        NULL,
        NULL,
        encodeOutputCallback,
        (__bridge void *_Nullable)(self),
        &_enCodeSession);
    if (!_enCodeSession) {
        NSLog(@"VTCompressionSessionCreate 失败------------------status:%d", (int) result);
        return;
    }
    _sps = _pps = nil;
    if (_bufferPool != NULL) {
        GJRetainBufferPool *pool = _bufferPool;
        dispatch_async(dispatch_get_global_queue(0, 0), ^{

            GJRetainBufferPoolClean(pool, true);
            GJRetainBufferPoolFree(pool);
        });
        _bufferPool = NULL;
    }
    GJRetainBufferPoolCreate(&_bufferPool, 1, GTrue, R_GJPacketMalloc, GNULL, GNULL);
    VTCompressionSessionPrepareToEncodeFrames(_enCodeSession);
}
- (void)setGop:(int)gop {
    _gop                         = gop;
    CFNumberRef frameIntervalRef = CFNumberCreate(kCFAllocatorDefault, kCFNumberIntType, &(_gop));
    OSStatus    result           = VTSessionSetProperty(_enCodeSession, kVTCompressionPropertyKey_MaxKeyFrameInterval, frameIntervalRef);
    CFRelease(frameIntervalRef);
    if (result != 0) {
        GJLOG(DEFAULT_LOG, GJ_LOGFORBID, "kVTCompressionPropertyKey_MaxKeyFrameInterval set error");
    }
}
- (void)setProfileLevel:(ProfileLevel)profileLevel {
    _profileLevel   = profileLevel;
    OSStatus result = VTSessionSetProperty(_enCodeSession, kVTCompressionPropertyKey_ProfileLevel, getCFStrByLevel(_profileLevel));
    if (result != 0) {
        GJLOG(DEFAULT_LOG, GJ_LOGFORBID, "kVTCompressionPropertyKey_ProfileLevel set error");
    }
}
- (void)setEntropyMode:(EntropyMode)entropyMode {
    _entropyMode    = entropyMode;
    OSStatus result = VTSessionSetProperty(_enCodeSession, kVTCompressionPropertyKey_H264EntropyMode, getCFStrByEntropyMode(_entropyMode));
    if (result != 0) {
        GJLOG(DEFAULT_LOG, GJ_LOGFORBID, "kVTCompressionPropertyKey_H264EntropyMode set error");
    }
}
- (void)setAllowBFrame:(BOOL)allowBFrame {
    _allowBFrame    = allowBFrame;
    OSStatus result = VTSessionSetProperty(_enCodeSession, kVTCompressionPropertyKey_AllowFrameReordering, _allowBFrame ? kCFBooleanTrue : kCFBooleanFalse);
    if (result != 0) {
        GJLOG(DEFAULT_LOG, GJ_LOGFORBID, "kVTCompressionPropertyKey_AllowFrameReordering set error");
    }
}
- (void)setAllParm {
    //    kVTCompressionPropertyKey_MaxFrameDelayCount
    //    kVTCompressionPropertyKey_MaxH264SliceBytes
    //    kVTVideoEncoderSpecification_EnableHardwareAcceleratedVideoEncoder
    //    kVTCompressionPropertyKey_RealTime

    self.allowBFrame  = _allowBFrame;
    self.profileLevel = _profileLevel;
    self.entropyMode  = _entropyMode;
    self.gop          = _gop;
    self.bitrate      = _bitrate;
}
- (void)setBitrate:(int)bitrate {
    if (bitrate >= 0 && _enCodeSession) {
        _bitrate            = bitrate;
        CFNumberRef bitRate = CFNumberCreate(kCFAllocatorDefault, kCFNumberSInt32Type, &(_bitrate));
        OSStatus    result  = VTSessionSetProperty(_enCodeSession, kVTCompressionPropertyKey_AverageBitRate, bitRate);
        CFRelease(bitRate);
        if (result != noErr) {
            GJLOG(DEFAULT_LOG, GJ_LOGFORBID, "kVTCompressionPropertyKey_AverageBitRate set error:%d", result);
        } else {
            GJLOG(DEFAULT_LOG, GJ_LOGINFO, "set video bitrate:%0.2f kB/s", bitrate / 1024.0 / 8.0);
        }
    }
}

//static GBool R_BufferRelease(GJRetainBuffer* buffer){
//    GJBufferPool* pool = buffer->parm;
//    GJBufferPoolSetData(pool, buffer->data-buffer->frontSize);
//    GJBufferPoolSetData(defauleBufferPool(), (void*)buffer);
//    return GTrue;
//}

void encodeOutputCallback(void *outputCallbackRefCon, void *sourceFrameRefCon, OSStatus statu, VTEncodeInfoFlags infoFlags,
                          CMSampleBufferRef sample) {
    if (statu != 0) return;
    if (!CMSampleBufferDataIsReady(sample)) {

        GJLOG(DEFAULT_LOG, GJ_LOGWARNING, "didCompressH264 data is not ready ");
        return;
    }
    GJH264Encoder * encoder    = (__bridge GJH264Encoder *) (outputCallbackRefCon);
    GJRetainBuffer *buffer     = NULL;
    R_GJPacket *    pushPacket = NULL;
#define PUSH_H264_PACKET_PRE_SIZE 45

    CMBlockBufferRef dataBuffer = CMSampleBufferGetDataBuffer(sample);
    size_t           length, totalLength;
    //    size_t bufferOffset = 0;
    uint8_t *inDataPointer;
    CMBlockBufferGetDataPointer(dataBuffer, 0, &length, &totalLength, (char **) &inDataPointer);

    bool keyframe = !CFDictionaryContainsKey((CFArrayGetValueAtIndex(CMSampleBufferGetSampleAttachmentsArray(sample, true), 0)), kCMSampleAttachmentKey_NotSync);

    if (encoder.sps == nil) {
        if (!keyframe) {
            return;
        }
        CMFormatDescriptionRef format = CMSampleBufferGetFormatDescription(sample);
        size_t                 spsSize, sparameterSetCount;
        int                    spHeadSize;
        const uint8_t *        sps;
        OSStatus               statusCode = CMVideoFormatDescriptionGetH264ParameterSetAtIndex(format, 0, &sps, &spsSize, &sparameterSetCount, &spHeadSize);
        if (statusCode != noErr) {
            GJLOG(DEFAULT_LOG, GJ_LOGFORBID, "CMVideoFormatDescriptionGetH264ParameterSetAt sps error:%d", statusCode);
            return;
        }

        size_t         ppsSize, pparameterSetCount;
        int            ppHeadSize;
        const uint8_t *pps;
        statusCode = CMVideoFormatDescriptionGetH264ParameterSetAtIndex(format, 1, &pps, &ppsSize, &pparameterSetCount, &ppHeadSize);
        if ((statusCode != noErr)) {
            GJLOG(DEFAULT_LOG, GJ_LOGFORBID, "CMVideoFormatDescriptionGetH264ParameterSetAt pps error:%d", statusCode);
            return;
        }

        size_t spsppsSize = spsSize + ppsSize;
        int    needSize   = (int) (8 + spsppsSize + totalLength + PUSH_H264_PACKET_PRE_SIZE);
        pushPacket        = (R_GJPacket *) GJRetainBufferPoolGetSizeData(encoder->_bufferPool, needSize);
        buffer            = &pushPacket->retain;
        if (R_BufferFrontSize(buffer) < PUSH_H264_PACKET_PRE_SIZE) {
            R_BufferMoveDataToPoint(buffer, PUSH_H264_PACKET_PRE_SIZE, GFalse);
        }
        pushPacket->flag       = GJPacketFlag_KEY;
        pushPacket->extendDataOffset = 0;
        pushPacket->extendDataSize   = (GInt32)(spsppsSize + 8);

        pushPacket->dataOffset = pushPacket->extendDataSize;
        pushPacket->dataSize = (GInt32)totalLength;
        uint8_t *data = R_BufferStart(buffer);
        uint32_t sSize = htonl(spsSize);
//        memcpy(data, "\x00\x00\x00\x01", 4);
        memcpy(data, &sSize, 4);
        memcpy(data + 4, sps, spsSize);
        encoder.sps = [NSData dataWithBytes:sps length:spsSize];

        sSize = htonl(ppsSize);
//        memcpy(data + 4 + sparameterSetSize, "\x00\x00\x00\x01", 4);
        memcpy(data + 4 + spsSize,&sSize, 4);

        memcpy(data + 8 + spsSize, pps, ppsSize);
        encoder.pps = [NSData dataWithBytes:pps length:ppsSize];

        memcpy(data + spsppsSize + 8, inDataPointer, totalLength);
        inDataPointer = data + spsppsSize + 8;
        
        GJLOG(DEFAULT_LOG, GJ_LOGINFO,"encode sps size:%zu:", spsSize);
        GJ_LogHexString(GJ_LOGINFO, sps, (GUInt32) spsSize);
        GJLOG(DEFAULT_LOG, GJ_LOGINFO,"encode pps size:%zu:", ppsSize);
        GJ_LogHexString(GJ_LOGINFO, pps, (GUInt32) ppsSize);

    } else {
        int needSize = (int) (totalLength + PUSH_H264_PACKET_PRE_SIZE);
        //       R_BufferPack(&buffer, GJBufferPoolGetSizeData(encoder.bufferPool,needSize), needSize, R_BufferRelease, encoder.bufferPool);
        pushPacket = (R_GJPacket *) GJRetainBufferPoolGetSizeData(encoder->_bufferPool, needSize);
        buffer     = &pushPacket->retain;
        if (R_BufferFrontSize(buffer) < PUSH_H264_PACKET_PRE_SIZE) {
            R_BufferMoveDataToPoint(buffer, PUSH_H264_PACKET_PRE_SIZE, GFalse);
        }
        pushPacket->flag       = 0;
        pushPacket->dataOffset = 0;
        pushPacket->dataSize   = (GInt32)(totalLength);
        pushPacket->extendDataSize = pushPacket->extendDataOffset = 0;

        //拷贝
        uint8_t *rDate = R_BufferStart(buffer);
        memcpy(rDate, inDataPointer, totalLength);
        inDataPointer = rDate;
    }

    pushPacket->type = GJMediaType_Video;
    CMTime pts       = CMSampleBufferGetPresentationTimeStamp(sample);

#ifdef NETWORK_DELAY
    pushPacket->dts = GJ_Gettime()/1000;
    if (encoder->_dtsDelta == 0) {
        encoder->_dtsDelta = (int)GMAX(1000,(pushPacket->dts - pts.value)*4);
    }
    pushPacket->dts -= encoder->_dtsDelta;
//    pushPacket->dts = GJ_Gettime()/1000 - encoder->_fristTime;
//    NSLog(@"decode Dur:%lld size:%d",pushPacket->dts - pts.value,pushPacket->dataSize);

#else
    pushPacket->dts = GJ_Gettime()/1000 - encoder->_fristTime;
#endif
//    assert(pushPacket->dts != encoder->_preDTS);

    if (pushPacket->dts == encoder->_preDTS) {
        pushPacket->dts = encoder->_preDTS + 1;
    }
    if (pushPacket->dts > pts.value) {
        if (encoder->_preDTS <= 0) {
            encoder->_preDTS = pts.value-2;
        }else if (encoder->_preDTS + 1 >= pts.value) {
            //如果比上一次解dts还要早，则直接推迟pts到dts
            GJLOG(DEFAULT_LOG, GJ_LOGDEBUG, "pts:%d小于preDts:%d，修改pts为：%d",pts.value,encoder->_preDTS,encoder->_preDTS + 2);
            pts.value = encoder->_preDTS+2;

        }
        //dt则直接采用上次dts
        pushPacket->dts = encoder->_preDTS+1;
    }
    
    pushPacket->pts = pts.value;
    encoder->_preDTS = pushPacket->dts;


//    printf("encode over pts:%lld dts:%lld data size:%zu\n",pts.value,pushPacket->dts,totalLength);

//    NSData* seid = [NSData dataWithBytes:pushPacket->ppOffset+pushPacket->retain.data length:30];
//    NSData* spsd = [NSData dataWithBytes:pushPacket->spsOffset+pushPacket->retain.data  length:pushPacket->spsSize];
//    NSData* ppsd = [NSData dataWithBytes:pushPacket->ppsOffset+pushPacket->retain.data  length:pushPacket->ppsSize];
//
//    static int t = 0;
//    NSLog(@"push times:%d :%@,sps:%@，pps:%@",t++,seid,spsd,ppsd);
#if 0
    CMTime ptd = CMSampleBufferGetDuration(sample);
    CMTime opts = CMSampleBufferGetOutputPresentationTimeStamp(sample);
    CMTime odts = CMSampleBufferGetOutputDecodeTimeStamp(sample);
    CMTime optd = CMSampleBufferGetOutputDuration(sample);
    CMTime dts = CMSampleBufferGetDecodeTimeStamp(sample);
    GJLOG(DEFAULT_LOG, GJ_LOGINFO,"encode dts:%f pts:%f\n",dts.value*1.0 / dts.timescale,pts.value*1.0/pts.timescale);
#endif

//    int bufferOffset = 0;
//    static const uint32_t AVCCHeaderLength = 4;
//    while (bufferOffset < totalLength) {
//        // Read the NAL unit length
//        uint32_t NALUnitLength = 0;
//        memcpy(&NALUnitLength, inDataPointer + bufferOffset, AVCCHeaderLength);
//        NALUnitLength = CFSwapInt32BigToHost(NALUnitLength);
//
//        uint8_t *data = inDataPointer + bufferOffset;
//        memcpy(&data[0], "\x00\x00\x00\x01", AVCCHeaderLength);
//        bufferOffset += AVCCHeaderLength + NALUnitLength;
//    }

    encoder.completeCallback(pushPacket);
    R_BufferUnRetain(buffer);
}

- (void)flush {
    requestFlush = YES;
    _sps         = nil;
    _pps         = nil;
    _fristPts    = GINT64_MAX;
    _fristTime   = -1;
    _preDTS    = -1;
}

- (void)dealloc {
    GJLOG(DEFAULT_LOG, GJ_LOGDEBUG, "GJH264Encoder：%p", self);
    if (_enCodeSession) VTCompressionSessionInvalidate(_enCodeSession);
    if (_bufferPool) {
        GJRetainBufferPool *pool = _bufferPool;
        dispatch_async(dispatch_get_global_queue(0, 0), ^{
            GJRetainBufferPoolClean(pool, true);
            GJRetainBufferPoolFree(pool);
        });
    }
}
//-(void)restart{
//
//    [self creatEnCodeSession];
//}

@end
