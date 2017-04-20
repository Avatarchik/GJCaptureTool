//
//  GJLivePush.h
//  GJCaptureTool
//
//  Created by mac on 17/2/23.
//  Copyright © 2017年 MinorUncle. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "GJLiveDefine.h"
#import <CoreVideo/CVImageBuffer.h>
#import <CoreMedia/CMTime.h>
#import "GJLiveDefine+internal.h"

enum AVCaptureDevicePosition;
@class UIView;
@class GJLivePush;

@protocol GJLivePushDelegate <NSObject>
@required


-(void)livePush:(GJLivePush*)livePush updatePushStatus:(GJPushStatus*)status;
-(void)livePush:(GJLivePush*)livePush closeConnent:(GJPushSessionInfo*)info resion:(GJConnentCloceReason)reason;
-(void)livePush:(GJLivePush*)livePush connentSuccessWithElapsed:(int)elapsed;

-(void)livePush:(GJLivePush*)livePush errorType:(GJLiveErrorType)type infoDesc:(NSString*)info;
-(void)livePush:(GJLivePush*)livePush pushPacket:(R_GJH264Packet*)packet;
-(void)livePush:(GJLivePush*)livePush pushImagebuffer:(CVImageBufferRef)packet pts:(CMTime)pts;


@optional

@end

#import "GJLivePlayer.h"

@interface GJLivePush : NSObject
@property(nonatomic,assign)enum AVCaptureDevicePosition cameraPosition;

@property(nonatomic,strong,readonly,getter=getPreviewView)UIView* previewView;

@property(nonatomic,assign,readonly)CaptureSizeType caputreSizeType;

@property(nonatomic,assign,readonly)NSInteger captureFps;

@property(nonatomic,weak)id<GJLivePushDelegate> delegate;

@property(strong,nonatomic)GJLivePlayer* player;

//push status,
#define kLIVEPUSH_CONNECT 1<<0
#define kLIVEPUSH_PREVIEW 1<<1
#define kLIVEPUSH_CAPTURE 1<<2

@property(nonatomic,assign,readonly)int status;


- (bool)startCaptureWithSizeType:(CaptureSizeType)sizeType fps:(NSInteger)fps position:(enum AVCaptureDevicePosition)cameraPosition;

- (void)stopCapture;

- (void)startPreview;

- (void)stopPreview;

- (bool)startStreamPushWithConfig:(GJPushConfig)config;

- (void)stopStreamPush;

- (void)videoRecodeWithPath:(NSString*)path;



@end