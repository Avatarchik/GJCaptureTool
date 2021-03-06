//
//  GJAudioManager.m
//  GJCaptureTool
//
//  Created by 未成年大叔 on 2017/7/1.
//  Copyright © 2017年 MinorUncle. All rights reserved.
//

#import "GJAudioManager.h"
#import <AVFoundation/AVFoundation.h>
#import "GJLog.h"

#define PCM_FRAME_COUNT 1024

//static GJAudioManager* _staticManager;
@interface GJAudioManager () {
    R_GJPCMFrame *_alignCacheFrame;
    GInt32        _sizePerPacket;
    float         _durPerSize;
    NSMutableDictionary<id,id<AEAudioPlayable>>* _mixPlayers;
    BOOL          _needResumeEarMonitoring;
}
@end

@implementation GJAudioManager
//+(GJAudioManager*)shareAudioManager{
//    return nil;
//};
- (instancetype)init
{
    self = [super init];
    if (self) {
        _mixToSream = YES;
        _mixPlayers = [NSMutableDictionary dictionaryWithCapacity:2];
        [[NSNotificationCenter defaultCenter]addObserver:self selector:@selector(receiveNotific:) name:AVAudioSessionRouteChangeNotification object:nil];
    }
    return self;
}

-(void)receiveNotific:(NSNotification*)notific{
    if ([notific.name isEqualToString:AVAudioSessionRouteChangeNotification]) {
        AVAudioSessionRouteChangeReason reson = [notific.userInfo[AVAudioSessionRouteChangeReasonKey] unsignedIntegerValue];
        switch (reson) {
            case AVAudioSessionRouteChangeReasonNewDeviceAvailable:
                //插入耳机
                if (self.audioInEarMonitoring) {
                    [self setAudioInEarMonitoring:NO];
                    _needResumeEarMonitoring = YES;
                }
                break;
            case AVAudioSessionRouteChangeReasonOldDeviceUnavailable:{
                if (_needResumeEarMonitoring) {
                    [self setAudioInEarMonitoring:YES];
                }
                break;
            }
            default:
            {
                
                if ([AVAudioSession sharedInstance].currentRoute.outputs.count > 0 &&
                    [[AVAudioSession sharedInstance].currentRoute.outputs[0].portType isEqualToString:AVAudioSessionPortBuiltInReceiver]) {
                    GJLOG(DEFAULT_LOG, GJ_LOGWARNING, "Fource AVAudioSessionPortBuiltInReceiver to AVAudioSessionPortOverrideSpeaker");
                    [[AVAudioSession sharedInstance] overrideOutputAudioPort:AVAudioSessionPortOverrideSpeaker error:nil];
                }
            }
                break;
        }
    }
    
}

- (instancetype)initWithFormat:(AudioStreamBasicDescription)audioFormat {
    self = [super init];
    if (self) {

    

        //        _blockPlay = [AEBlockChannel channelWithBlock:^(const AudioTimeStamp *time, UInt32 frames, AudioBufferList *audio) {
        //            for (int i = 0 ; i<audio->mNumberBuffers; i++) {
        //                memset(audio->mBuffers[i].mData, 20, audio->mBuffers[i].mDataByteSize);
        //            }
        //            NSLog(@"block play time:%f",time->mSampleTime);
        //        }];
        //        [_audioController addChannels:@[_blockPlay]];
    }
    return self;
}

-(void)setAudioFormat:(AudioStreamBasicDescription)audioFormat{
    if (_audioController && _audioController.running) {
        GJLOG(DEFAULT_LOG, GJ_LOGFORBID, "运行状态无法修改格式");
        return;
    }
    if ((int64_t)audioFormat.mSampleRate == (int64_t)_audioFormat.mSampleRate &&
        audioFormat.mChannelsPerFrame == _audioFormat.mChannelsPerFrame &&
        audioFormat.mFormatID == _audioFormat.mFormatID &&
        audioFormat.mBytesPerFrame == _audioFormat.mBytesPerFrame &&
        audioFormat.mFormatFlags == _audioFormat.mFormatFlags &&
        audioFormat.mBitsPerChannel == _audioFormat.mBitsPerChannel &&
        audioFormat.mBytesPerPacket == _audioFormat.mBytesPerPacket &&
        audioFormat.mFramesPerPacket == _audioFormat.mFramesPerPacket
        ) {
        //无需修改
        return;
    }
    _audioFormat = audioFormat;
    NSError* error;
    if (_audioController) {
        [_audioController setAudioDescription:_audioFormat error:&error];
        if (error) {
            GJLOG(DEFAULT_LOG, GJ_LOGFORBID, "setAudioDescription error");
        }else{
            _audioFormat = audioFormat;
        }
    }
    _sizePerPacket = PCM_FRAME_COUNT * audioFormat.mBytesPerFrame;
}

- (void)audioMixerProduceFrameWith:(AudioBufferList *)frame time:(int64_t)time {
    //    R_GJPCMFrame* pcmFrame = NULL;
    //    printf("audio size:%d chchesize:%d pts:%lld\n",frame->mBuffers[0].mDataByteSize,_alignCacheFrame->retain.size,time);
    int needSize = _sizePerPacket - R_BufferSize(&_alignCacheFrame->retain);
    int leftSize = frame->mBuffers[0].mDataByteSize;
    while (leftSize >= needSize) {
        R_BufferWrite(&_alignCacheFrame->retain, frame->mBuffers[0].mData + frame->mBuffers[0].mDataByteSize - leftSize, needSize);
        _alignCacheFrame->channel = frame->mBuffers[0].mNumberChannels;
        _alignCacheFrame->pts     = time - (GInt64)(R_BufferSize(&_alignCacheFrame->retain) * _durPerSize);

        static int64_t pre;
        if (pre == 0) {
            pre = _alignCacheFrame->pts;
        }
        //        printf("audio pts:%lld,size:%d dt:%lld\n",_alignCacheFrame->pts,_alignCacheFrame->retain.size,_alignCacheFrame->pts-pre);
        pre = _alignCacheFrame->pts;
        self.audioCallback(_alignCacheFrame);
        R_BufferUnRetain(&_alignCacheFrame->retain);
        time             = time + needSize / _durPerSize;
        _alignCacheFrame = (R_GJPCMFrame *) GJRetainBufferPoolGetSizeData(_bufferPool, _sizePerPacket);
        leftSize         = leftSize - needSize;
        needSize         = _sizePerPacket;
    }
    if (leftSize > 0) {
        _alignCacheFrame->pts = (GInt64) time;
        R_BufferWrite(&_alignCacheFrame->retain, frame->mBuffers[0].mData + frame->mBuffers[0].mDataByteSize - leftSize, leftSize);
    }
}

-(void)addMixPlayer:(id<AEAudioPlayable>)player key:(id <NSCopying>)key{
    if (![_mixPlayers.allKeys containsObject:key]) {
        [_mixPlayers setObject:player forKey:key];
        [_audioController addChannels:@[player]];
        if (_mixPlayers.count == 1) {
            [_audioController addOutputReceiver:_audioMixer];
        }
    }
}

-(void)removeMixPlayerWithkey:(id <NSCopying>)key{
    if ([_mixPlayers.allKeys containsObject:key]) {
        id<AEAudioPlayable> player = _mixPlayers[key];
        [_mixPlayers removeObjectForKey:key];
        if (_mixPlayers.count == 0) {
            [_audioController removeOutputReceiver:_audioMixer];
        }
        [_audioController removeChannels:@[player]];
    }
}

- (BOOL)startRecode:(NSError **)error {
    GJRetainBufferPoolCreate(&_bufferPool, 1, GTrue, R_GJPCMFrameMalloc, GNULL, GNULL);
    _alignCacheFrame = (R_GJPCMFrame *) GJRetainBufferPoolGetSizeData(_bufferPool, _sizePerPacket);

    NSError *configError;
    [[GJAudioSessionCenter shareSession] lockBeginConfig];
    [[GJAudioSessionCenter shareSession] requestPlay:YES key:self.description error:&configError];
    [[GJAudioSessionCenter shareSession] requestRecode:YES key:self.description error:&configError];
    [[GJAudioSessionCenter shareSession] requestDefaultToSpeaker:YES key:self.description error:&configError];
    [[GJAudioSessionCenter shareSession] requestAllowAirPlay:YES key:self.description error:&configError];
    [[GJAudioSessionCenter shareSession] unLockApplyConfig:&configError];
    if (configError) {
        GJLOG(DEFAULT_LOG, GJ_LOGERROR, "Apply audio session Config error:%@", configError.description.UTF8String);
    }
    
#ifdef AUDIO_SEND_TEST
    _audioMixer = [[AEAudioSender alloc] init];
    
#else
    if (_audioMixer == nil) {
        _audioMixer = [[GJAudioMixer alloc] init];
        _audioMixer.delegate = self;
    }
#endif
    if(_audioController == nil){
        //第一次需要的时候才申请，并初始化所有参数
        _audioController                    = [[AEAudioController alloc] initWithAudioDescription:_audioFormat inputEnabled:YES];
        [_audioController addInputReceiver:_audioMixer];
        [self setAudioInEarMonitoring:_audioInEarMonitoring];
        [self setMixToSream:_mixToSream];
        [self setEnableReverb:_enableReverb];
        [self setAce:_ace];
        [self setUseMeasurementMode:_useMeasurementMode];
    }else{
        //其他的每次配置参数的时候已经应用了,无需再配置
    }
    NSTimeInterval preferredBufferDuration = _sizePerPacket/_audioFormat.mBytesPerFrame/_audioFormat.mSampleRate;
    if (preferredBufferDuration - _audioController.preferredBufferDuration > 0.01 || preferredBufferDuration - _audioController.preferredBufferDuration < -0.01) {
        [_audioController setPreferredBufferDuration:preferredBufferDuration];
    }
    _durPerSize = 1000.0 / _audioController.audioDescription.mSampleRate / _audioController.audioDescription.mBytesPerFrame;

    
    if (![_audioController start:error]) {
        GJLOG(DEFAULT_LOG, GJ_LOGERROR, "AEAudioController start error:%@", (*error).description.UTF8String);
    }

    return *error == nil;
}

- (void)stopRecode {

    if (_mixfilePlay) {
        [self stopMix];
    }
    [_audioController stop];

    NSError *configError;
    [[GJAudioSessionCenter shareSession] lockBeginConfig];
    [[GJAudioSessionCenter shareSession] requestPlay:NO key:self.description error:nil];
    [[GJAudioSessionCenter shareSession] requestRecode:NO key:self.description error:nil];
    [[GJAudioSessionCenter shareSession] requestDefaultToSpeaker:NO key:self.description error:nil];
    [[GJAudioSessionCenter shareSession] requestAllowAirPlay:NO key:self.description error:nil];
    [[GJAudioSessionCenter shareSession] unLockApplyConfig:&configError];
    if (configError) {
        GJLOG(DEFAULT_LOG, GJ_LOGERROR, "Apply audio session Config error:%@", configError.description.UTF8String);
    }

    if (_alignCacheFrame) {
        R_BufferUnRetain(&_alignCacheFrame->retain);
        _alignCacheFrame = GNULL;
    }
    if (_bufferPool) {
        GJRetainBufferPool *pool = _bufferPool;
        _bufferPool              = GNULL;
        dispatch_async(dispatch_get_global_queue(0, 0), ^{
            GJRetainBufferPoolClean(pool, GTrue);
            GJRetainBufferPoolFree(pool);
        });
    }
}

- (AEPlaythroughChannel *)playthrough {
    if (_playthrough == nil) {
        _playthrough = [[AEPlaythroughChannel alloc] init];
    }
    return _playthrough;
}

-(BOOL)isHeadphones{
    AVAudioSessionRouteDescription* route = [[AVAudioSession sharedInstance] currentRoute];
    for (AVAudioSessionPortDescription* desc in [route outputs]) {
        if ([[desc portType] isEqualToString:AVAudioSessionPortHeadphones])
            return YES;
    }
    return NO;
}

-(void)setUseMeasurementMode:(BOOL)useMeasurementMode{
    _useMeasurementMode = useMeasurementMode;
    if (_audioController) {
        if (_audioController.useMeasurementMode != useMeasurementMode) {
            _audioController.useMeasurementMode = useMeasurementMode;
        }
    }
}

-(void)setAce:(BOOL)ace{
    _ace = ace;
    if (_audioController) {
        if (_audioController.voiceProcessingEnabled != ace) {
            [_audioController setVoiceProcessingEnabled:ace];
        }
    }
}

-(void)setAudioInEarMonitoring:(BOOL)audioInEarMonitoring{
    if (![self isHeadphones]) {
        _needResumeEarMonitoring = audioInEarMonitoring;
        
    }else{
        _needResumeEarMonitoring = NO;
        [self _setAudioInEarMonitoring:audioInEarMonitoring];
    }
}

-(void)_setAudioInEarMonitoring:(BOOL)audioInEarMonitoring{
    _audioInEarMonitoring = audioInEarMonitoring;
    if (_audioController == nil) {
        return;
    }
    if (audioInEarMonitoring) {
        //关闭麦克风接受，打开播放接受
        [_audioController removeInputReceiver:_audioMixer];
        if (![_audioController.inputReceivers containsObject:self.playthrough]) {
            [_audioController addInputReceiver:self.playthrough];
        }
        [self addMixPlayer:self.playthrough key:self.playthrough.description];
    } else {
        [self removeMixPlayerWithkey:self.playthrough.description];
        if (![_audioController.inputReceivers containsObject:_audioMixer]) {
            [_audioController addInputReceiver:_audioMixer];
        }
        [_audioController removeInputReceiver:self.playthrough];
    }
}

-(void)setEnableReverb:(BOOL)enable{
    _enableReverb = enable;
    if (_reverb == nil) {
        _reverb           = [[AEReverbFilter alloc] init];
        _reverb.dryWetMix = 80;
    }
    if(_audioController){
        if (enable) {
            if (![_audioController.filters containsObject:_reverb] && _reverb) {
                [_audioController addFilter:_reverb];
            }
        }else{
            [_audioController removeFilter:_reverb];
        }
    }
}

- (void)setMixToSream:(BOOL)mixToSream {
    _mixToSream = mixToSream;
    
    if(_audioMixer){
#ifndef AUDIO_SEND_TEST
        if (_mixToSream) {
            [_audioMixer removeIgnoreSource:_audioController.topGroup];
        } else {
            [_audioMixer addIgnoreSource:_audioController.topGroup];
        }
#endif
    }

}

- (BOOL)setMixFile:(NSURL*)file finish:(MixFinishBlock)finishBlock {
    if (_mixfilePlay != nil) {
        GJLOG(DEFAULT_LOG, GJ_LOGWARNING, "上一个文件没有关闭，自动关闭");
        [self removeMixPlayerWithkey:_mixfilePlay.description];
        _mixfilePlay = nil;
    }
    
    if (_audioController == nil) {
        return NO;
    }
    
    NSError *error;
    _mixfilePlay = [[AEAudioFilePlayer alloc] initWithURL:file error:&error];
    if (_mixfilePlay == nil) {
        GJLOG(DEFAULT_LOG, GJ_LOGERROR, "AEAudioFilePlayer alloc error:%s", error.localizedDescription.UTF8String);
        return GFalse;
    } else {
        __weak GJAudioManager* wkSelf = self;
        _mixfilePlay.completionBlock   = ^{
            if (finishBlock) {
                finishBlock(GTrue);
            }
            [wkSelf removeMixPlayerWithkey:wkSelf.mixfilePlay.description];
            wkSelf.mixfilePlay.completionBlock = nil;
            wkSelf.mixfilePlay = nil;
        };
        [self addMixPlayer:_mixfilePlay key:_mixfilePlay.description];
        return GTrue;
    }
}

- (BOOL)mixFilePlayAtTime:(uint64_t)time {
    if (_mixfilePlay) {
        [_mixfilePlay playAtTime:time];
        return YES;
    } else {
        GJLOG(DEFAULT_LOG, GJ_LOGERROR, "请先设置minx file");
        return NO;
    }
}

- (void)stopMix {
    if (_mixfilePlay == nil) {
        GJLOG(DEFAULT_LOG, GJ_LOGWARNING, "重复stop mix");
    } else {
        [self removeMixPlayerWithkey:_mixfilePlay.description];
        _mixfilePlay.completionBlock();
        _mixfilePlay.completionBlock = nil;
        _mixfilePlay = nil;
    }
}

- (void)dealloc {
    GJLOG(DEFAULT_LOG, GJ_LOGDEBUG, "GJAudioManager dealloc");
    if (_bufferPool) {
        [self stopRecode];
    }
    [_audioController removeInputReceiver:_audioMixer];
    [_audioController removeChannels:_mixPlayers.allValues];
}
@end
