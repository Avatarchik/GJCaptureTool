//
//  GJLivePull.m
//  GJLivePull
//
//  Created by mac on 17/3/6.
//  Copyright © 2017年 MinorUncle. All rights reserved.
//

#import "GJLivePull.h"
#import "GJRtmpPull.h"
#import "GJH264Decoder.h"
#import "GJPlayer.h"
#import "GJLog.h"
#import "GJPCMDecodeFromAAC.h"
#import <CoreImage/CoreImage.h>


@interface GJLivePull()<GJH264DecoderDelegate,GJPCMDecodeFromAACDelegate>
{
    GJRtmpPull* _videoPull;
    NSThread*  _playThread;
    
    BOOL    _pulling;
    
    NSTimer * _timer;
    
    NSRecursiveLock* _lock;
}
@property(strong,nonatomic)GJH264Decoder* videoDecoder;
@property(strong,nonatomic)GJPCMDecodeFromAAC* audioDecoder;

@property(strong,nonatomic)GJPlayer* player;
@property(assign,nonatomic)long sendByte;
@property(assign,nonatomic)int unitByte;

@property(assign,nonatomic)int gaterFrequency;


@property(strong,nonatomic)NSDate* startPullDate;
@property(strong,nonatomic)NSDate* connentDate;
@property(strong,nonatomic)NSDate* fristVideoDate;
@property(strong,nonatomic)NSDate* fristAudioDate;

@end
@implementation GJLivePull
- (instancetype)init
{
    self = [super init];
    if (self) {
        
        _player = [[GJPlayer alloc]init];
        _videoDecoder = [[GJH264Decoder alloc]init];
        _videoDecoder.delegate = self;
        _enablePreview = YES;
        _gaterFrequency = 2.0;
        _lock = [[NSRecursiveLock alloc]init];
    }
    return self;
}

static void pullMessageCallback(GJRtmpPull* pull, GJRTMPPullMessageType messageType,void* rtmpPullParm,void* messageParm){
    GJLivePull* livePull = (__bridge GJLivePull *)(rtmpPullParm);
    switch (messageType) {
        case GJRTMPPullMessageType_connectError:
        case GJRTMPPullMessageType_urlPraseError:
            [livePull.delegate livePull:livePull errorType:kLivePushConnectError infoDesc:@"连接错误"];
            [livePull stopStreamPull];
            break;
        case GJRTMPPullMessageType_sendPacketError:
            [livePull.delegate livePull:livePull errorType:kLivePullReadPacketError infoDesc:@"读取失败"];
            [livePull stopStreamPull];
            break;
        case GJRTMPPullMessageType_connectSuccess:
            livePull.connentDate = [NSDate date];
            [livePull.delegate livePull:livePull connentSuccessWithElapsed:[livePull.connentDate timeIntervalSinceDate:livePull.startPullDate]*1000];
            break;
        case GJRTMPPullMessageType_closeComplete:{
            NSDate* stopDate = [NSDate date];
            GJPullSessionInfo info = {0};
            info.sessionDuring = [stopDate timeIntervalSinceDate:livePull.startPullDate]*1000;
            [livePull.delegate livePull:livePull closeConnent:&info resion:kConnentCloce_Active];
        }
            break;
        default:
            GJLOG(GJ_LOGERROR,"not catch info：%d",messageType);
            break;
    }
}



- (BOOL)startStreamPullWithUrl:(char*)url{
    [_lock lock];
    GJAssert(_videoPull == NULL, "请先关闭上一个流\n");
    _pulling = true;
    GJRtmpPull_Create(&_videoPull, pullMessageCallback, (__bridge void *)(self));
    GJRtmpPull_StartConnect(_videoPull, pullDataCallback, (__bridge void *)(self),(const char*) url);
    [_audioDecoder start];
    _timer = [NSTimer scheduledTimerWithTimeInterval:_gaterFrequency repeats:YES block:^(NSTimer * _Nonnull timer) {
        GJCacheInfo videoCache = [_player getVideoCache];
        GJCacheInfo audioCache = [_player getAudioCache];
        GJPullStatus status = {0};
        status.bitrate = _unitByte/_gaterFrequency;
        _unitByte = 0;
        status.audioCacheCount = audioCache.cacheCount;
        status.audioCacheTime = audioCache.cacheTime;
        status.videoCacheTime = videoCache.cacheTime;
        status.videoCacheCount = videoCache.cacheCount;
        
        [self.delegate livePull:self updatePullStatus:&status];
    }];
    _startPullDate = [NSDate date];
    [_lock unlock];
    return YES;
}

- (void)stopStreamPull{
    [_lock lock];
    if (_videoPull) {
        [_audioDecoder stop];
        [_player stop];
        GJRtmpPull_CloseAndRelease(_videoPull);
        _videoPull = NULL;
        _pulling = NO;
    }
    _fristAudioDate = _fristVideoDate = _connentDate = nil;
    [_lock unlock];
}

-(UIView *)getPreviewView{
    return _player.displayView;
}

-(void)setEnablePreview:(BOOL)enablePreview{
    _enablePreview = enablePreview;
    
}
static const int mpeg4audio_sample_rates[16] = {
    96000, 88200, 64000, 48000, 44100, 32000,
    24000, 22050, 16000, 12000, 11025, 8000, 7350
};
static void pullDataCallback(GJRtmpPull* pull,GJRTMPDataType dataType,GJRetainBuffer* buffer,void* parm,int64_t pts){
    GJLivePull* livePull = (__bridge GJLivePull *)(parm);
    
    livePull.sendByte = livePull.sendByte + buffer->size;
    livePull.unitByte = livePull.unitByte + buffer->size;
    if (dataType == GJRTMPAudioData) {
        if (livePull.fristAudioDate == nil) {
            livePull.fristAudioDate = [NSDate date];
            uint8_t* adts = buffer->data;
            uint8_t sampleIndex = adts[2] << 2;
            sampleIndex = sampleIndex>>4;
            int sampleRate = mpeg4audio_sample_rates[sampleIndex];
            uint8_t channel = adts[2] & 0x1 <<2;
            channel += (adts[3] & 0xc0)>>6;
            AudioStreamBasicDescription sourceformat = {0};
            sourceformat.mFormatID = kAudioFormatMPEG4AAC;
            sourceformat.mChannelsPerFrame = channel;
            sourceformat.mSampleRate = sampleRate;
            sourceformat.mFramesPerPacket = 1024;

            AudioStreamBasicDescription destformat = {0};
            destformat.mFormatID = kAudioFormatLinearPCM;
            destformat.mSampleRate       = sourceformat.mSampleRate;               // 3
            destformat.mChannelsPerFrame = sourceformat.mChannelsPerFrame;                     // 4
            destformat.mFramesPerPacket  = 1;                     // 7
            destformat.mBitsPerChannel   = 16;                    // 5
            destformat.mBytesPerFrame   = destformat.mChannelsPerFrame * destformat.mBitsPerChannel/8;
            destformat.mFramesPerPacket = destformat.mBytesPerFrame * destformat.mFramesPerPacket ;
            destformat.mFormatFlags = kLinearPCMFormatFlagIsSignedInteger|kLinearPCMFormatFlagIsPacked;
            livePull.audioDecoder = [[GJPCMDecodeFromAAC alloc]initWithDestDescription:&destformat SourceDescription:&sourceformat];
            livePull.audioDecoder.delegate = livePull;
            [livePull.audioDecoder start];
            
            livePull.player.audioFormat = destformat;
            [livePull.player start];
        }
        AudioStreamPacketDescription format;
        format.mDataByteSize = buffer->size;
        format.mStartOffset = 7;
        format.mVariableFramesInPacket = 0;
        [livePull.audioDecoder decodeBuffer:buffer packetDescriptions:&format pts:pts];
//        static int times =0;
//        NSData* audio = [NSData dataWithBytes:buffer->data length:buffer->size];
//        NSLog(@" pullaudio times:%d ,%@",times++,audio);
        
    }else if (dataType == GJRTMPVideoData) {
        [livePull.videoDecoder decodeBuffer:buffer pts:pts];
    }
}
-(void)GJH264Decoder:(GJH264Decoder *)devocer decodeCompleteImageData:(CVImageBufferRef)imageBuffer pts:(int64_t)pts{
    [_player addVideoDataWith:imageBuffer pts:pts];
    return;    
}

-(void)pcmDecode:(GJPCMDecodeFromAAC *)decoder completeBuffer:(GJRetainBuffer *)buffer pts:(int64_t)pts{

    
    [_player addAudioDataWith:buffer pts:pts];
}

@end
