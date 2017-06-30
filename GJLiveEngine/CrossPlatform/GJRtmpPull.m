//
//  GJRtmpPull.c
//  GJCaptureTool
//
//  Created by 未成年大叔 on 17/3/4.
//  Copyright © 2017年 MinorUncle. All rights reserved.
//

#include "GJRtmpPull.h"
#include "GJLog.h"
#include "sps_decode.h"
#import "GJLiveDefine+internal.h"
#include <string.h>
#import <Foundation/Foundation.h>
#import "GJBufferPool.h"
#include "GJFLVPack.h"

#define BUFFER_CACHE_SIZE 40
#define RTMP_RECEIVE_TIMEOUT    10




GVoid GJRtmpPull_Delloc(GJRtmpPull* pull);

GBool packetBufferRelease(GJRetainBuffer* buffer){
    if (buffer->data) {
        free(buffer->data);
    }
    GJBufferPoolSetData(defauleBufferPool(), (GUInt8*)buffer);
    return GTrue;
}

static GHandle pullRunloop(GHandle parm){
    pthread_setname_np("rtmpPullLoop");
    GJRtmpPull* pull = (GJRtmpPull*)parm;
    GJRTMPPullMessageType errType = GJRTMPPullMessageType_connectError;
    GHandle errParm = NULL;
    GInt32 ret = RTMP_SetupURL(pull->rtmp, pull->pullUrl);
    if (!ret) {
        errType = GJRTMPPullMessageType_urlPraseError;
        GJLOG(GJ_LOGERROR, "RTMP_SetupURL error");
        goto ERROR;
    }
    pull->rtmp->Link.timeout = RTMP_RECEIVE_TIMEOUT;
    
    ret = RTMP_Connect(pull->rtmp, NULL);
    if (!ret) {
        errType = GJRTMPPullMessageType_connectError;
        GJLOG(GJ_LOGERROR, "RTMP_Connect error");
        goto ERROR;
    }
    ret = RTMP_ConnectStream(pull->rtmp, 0);
    if (!ret) {
        errType = GJRTMPPullMessageType_connectError;
        GJLOG(GJ_LOGERROR, "RTMP_ConnectStream error");
        goto ERROR;
    }else{
        GJLOG(GJ_LOGDEBUG, "RTMP_Connect success");
        if(pull->messageCallback){
            pull->messageCallback(pull, GJRTMPPullMessageType_connectSuccess,pull->messageCallbackParm,NULL);
        }
    }

    
    while(!pull->stopRequest){
        RTMPPacket packet = {0};
        GBool rResult = GFalse;
        while ((rResult = RTMP_ReadPacket(pull->rtmp, &packet))) {
            GUInt8 *sps = NULL,*pps = NULL,*pp = NULL,*sei = NULL;
            GInt32 spsSize = 0,ppsSize = 0,ppSize = 0,seiSize=0;
            if (!RTMPPacket_IsReady(&packet) || !packet.m_nBodySize)
            {
                continue;
            }
            
            RTMP_ClientPacket(pull->rtmp, &packet);
            
            if (packet.m_packetType == RTMP_PACKET_TYPE_AUDIO) {
                GJLOGFREQ("receive audio pts:%d",packet.m_nTimeStamp);
                pull->audioPullInfo.pts = packet.m_nTimeStamp;
                pull->audioPullInfo.count++;
                pull->audioPullInfo.byte += packet.m_nBodySize;
                GUInt8* body = (GUInt8*)packet.m_body;
                
                R_GJAACPacket* aacPacket = (R_GJAACPacket*)GJBufferPoolGetSizeData(defauleBufferPool(), sizeof(R_GJAACPacket));
                memset(aacPacket, 0, sizeof(R_GJAACPacket));

                GJRetainBuffer* retainBuffer = &aacPacket->retain;
                retainBufferPack(&retainBuffer, body - RTMP_MAX_HEADER_SIZE, RTMP_MAX_HEADER_SIZE+packet.m_nBodySize, packetBufferRelease, NULL);
//                retainBufferMoveDataToPoint(retainBuffer, RTMP_MAX_HEADER_SIZE, GFalse);
                aacPacket->pts = packet.m_nTimeStamp;
                
                if (body[1] == GJ_flv_a_aac_package_type_aac_raw) {
                    aacPacket->adtsOffset = 0;
                    aacPacket->adtsSize = 0;
                    aacPacket->aacOffset = RTMP_MAX_HEADER_SIZE+2;
                    aacPacket->aacSize = (GInt32)(packet.m_nBodySize - 2);
                }else if (body[1] == GJ_flv_a_aac_package_type_aac_sequence_header){
                    GUInt8 profile = body[2]>>3;
                    GUInt8 freqIdx = ((body[2] & 0x07) << 1) |(body[3]&0x01);
                    GUInt8 chanCfg = (body[3] & 0x78) >> 3;
                    int adtsLength = 7;
                    GUInt8* adts = body - RTMP_MAX_HEADER_SIZE;
                    NSUInteger fullLength = adtsLength + 0;
                    adts[0] = (char)0xFF;	// 11111111  	= syncword
                    adts[1] = (char)0xF1;	   // 1111 0 00 1 = syncword+id(MPEG-4) + Layer + absent
                    adts[2] = (char)(((profile)<<6) + (freqIdx<<2) +(chanCfg>>2));// profile(2)+sampling(4)+privatebit(1)+channel_config(1)
                    adts[3] = (char)(((chanCfg&3)<<6) + (fullLength>>11));
                    adts[4] = (char)((fullLength&0x7FF) >> 3);
                    adts[5] = (char)(((fullLength&7)<<5) + 0x1F);
                    adts[6] = (char)0xFC;
                    
                    aacPacket->adtsOffset = 0;
                    aacPacket->adtsSize = adtsLength;
                    aacPacket->aacOffset = RTMP_MAX_HEADER_SIZE+2;
                    aacPacket->aacSize = (GInt32)(packet.m_nBodySize - 2);
                }else{
                    GJLOG(GJ_LOGFORBID,"音频流格式错误");
                    packet.m_body=NULL;
                    retainBufferUnRetain(retainBuffer);
                    break;
                }
               
                packet.m_body=NULL;
                pthread_mutex_lock(&pull->mutex);
                if (!pull->releaseRequest) {
                    pull->audioCallback(pull,aacPacket,pull->dataCallbackParm);
                }
                pthread_mutex_unlock(&pull->mutex);
                retainBufferUnRetain(retainBuffer);
                
            }else if (packet.m_packetType == RTMP_PACKET_TYPE_VIDEO){
                GJLOGFREQ("receive video pts:%d",packet.m_nTimeStamp);
//                GJLOG(GJ_LOGDEBUG,"receive video pts:%d",packet.m_nTimeStamp);

                GUInt8 *body = (GUInt8*)packet.m_body;
                GUInt8 *pbody = body;
                GInt32 isKey = 0;
                GInt32 index = 0;
                
                            
                while (index < packet.m_nBodySize) {
                    if ((pbody[index] & 0x0F) == 0x07) {
                        index ++;
                        if (pbody[index] == 0) {//sps pps
                            index += 10;
                            spsSize = pbody[index++]<<8;
                            spsSize += pbody[index++];
                            sps = pbody+index;
                            index += spsSize+1;
                            ppsSize += pbody[index++]<<8;
                            ppsSize += pbody[index++];
                            pps = pbody+index;
                            index += ppsSize;
                            if (pbody+4>body+packet.m_nBodySize) {
                                GJLOG(GJ_LOGINFO,"only spspps\n");
                            }
                        }else if (pbody[index] == 1) {
                            index += 4;
                            if ((pbody[index+4] & 0x0F) == 0x6) {
                                isKey = GTrue;
                                seiSize += pbody[index]<<24;
                                seiSize += pbody[index+1]<<16;
                                seiSize += pbody[index+2]<<8;
                                seiSize += pbody[index+3];
                                sei = pbody + index;
                                seiSize += 4;
                                index += seiSize;
                                if(index < packet.m_nBodySize && (pbody[index+4] & 0x0F) == 0x5){
                                    ppSize += pbody[index]<<24;
                                    ppSize += pbody[index+1]<<16;
                                    ppSize += pbody[index+2]<<8;
                                    ppSize += pbody[index+3];
                                    pp = pbody + index;
                                    ppSize += 4;
                                    index += ppSize;
                                }
                            }else if((pbody[index+4] & 0x0F) == 0x5){
                                isKey = GTrue;
                                ppSize += pbody[index]<<24;
                                ppSize += pbody[index+1]<<16;
                                ppSize += pbody[index+2]<<8;
                                ppSize += pbody[index+3];
                                pp = pbody + index;
                                ppSize += 4;
                                index += ppSize;
                            }else if((pbody[index+4] & 0x0F) == 0x1){
                                isKey = GFalse;
                                ppSize += pbody[index]<<24;
                                ppSize += pbody[index+1]<<16;
                                ppSize += pbody[index+2]<<8;
                                ppSize += pbody[index+3];
                                pp = pbody + index;
                                ppSize += 4;
                                index += ppSize;
                            }
                            
                        }else  if (pbody[index] == 2){
                            GJLOG(GJ_LOGDEBUG,"直播结束\n");
                            RTMPPacket_Free(&packet);
                            errType = GJRTMPPullMessageType_closeComplete;
                            goto ERROR;
                            break;
                        }else{
                            GJLOG(GJ_LOGFORBID,"h264格式有误\n");
                            RTMPPacket_Free(&packet);
                            goto ERROR;
                        }
                        
                    }else{
                        GJLOG(GJ_LOGFORBID,"h264格式有误，type:%d\n",body[0]);
                        RTMPPacket_Free(&packet);
                        break;
                    }
                }
               
                
                R_GJH264Packet* h264Packet = (R_GJH264Packet*)                GJBufferPoolGetSizeData(defauleBufferPool(), sizeof(R_GJH264Packet));
                memset(h264Packet, 0, sizeof(R_GJH264Packet));
                GJRetainBuffer* retainBuffer = &h264Packet->retain;
                retainBufferPack(&retainBuffer, packet.m_body-RTMP_MAX_HEADER_SIZE,RTMP_MAX_HEADER_SIZE+packet.m_nBodySize,packetBufferRelease, NULL);
               
                
                h264Packet->spsOffset = sps - retainBuffer->data;
                h264Packet->spsSize = spsSize;
                h264Packet->ppsOffset = pps - retainBuffer->data;
                h264Packet->ppsSize = ppsSize;
                h264Packet->ppOffset = pp - retainBuffer->data;
                h264Packet->ppSize = ppSize;
                h264Packet->seiOffset = sei - retainBuffer->data;
                h264Packet->seiSize = seiSize;
                h264Packet->pts = packet.m_nTimeStamp;
                
                
                pull->videoPullInfo.pts = packet.m_nTimeStamp;
                pull->videoPullInfo.count++;
                pull->videoPullInfo.byte += packet.m_nBodySize;
                
                
                pthread_mutex_lock(&pull->mutex);
                if (!pull->releaseRequest) {
                    pull->videoCallback(pull,h264Packet,pull->dataCallbackParm);
                }
                pthread_mutex_unlock(&pull->mutex);
                retainBufferUnRetain(retainBuffer);
                packet.m_body=NULL;
            }else{
                GJLOG(GJ_LOGWARNING,"not media Packet:%p type:%d",packet,packet.m_packetType);
                RTMPPacket_Free(&packet);
                break;
            }
            break;
        }
//        if (packet.m_body) {
//            RTMPPacket_Free(&packet);
////            GJAssert(0, "读取数据错误\n");
//        }
        if (rResult == GFalse) {
            errType = GJRTMPPullMessageType_receivePacketError;
            GJLOG(GJ_LOGWARNING,"pull Read Packet Error");
            goto ERROR;
        }
    }
    errType = GJRTMPPullMessageType_closeComplete;
ERROR:
    RTMP_Close(pull->rtmp);
    if (pull->messageCallback) {
        pull->messageCallback(pull, errType,pull->messageCallbackParm,errParm);
    }
    GBool shouldDelloc = GFalse;
    pthread_mutex_lock(&pull->mutex);
    pull->pullThread = NULL;
    if (pull->releaseRequest == GTrue) {
        shouldDelloc = GTrue;
    }
    pthread_mutex_unlock(&pull->mutex);
    if (shouldDelloc) {
        GJRtmpPull_Delloc(pull);
    }
    GJLOG(GJ_LOGDEBUG, "pullRunloop end");
    return NULL;
}
GBool GJRtmpPull_Create(GJRtmpPull** pullP,PullMessageCallback callback,GHandle rtmpPullParm){
    GJRtmpPull* pull = NULL;
    if (*pullP == NULL) {
        pull = (GJRtmpPull*)malloc(sizeof(GJRtmpPull));
    }else{
        pull = *pullP;
    }
    memset(pull, 0, sizeof(GJRtmpPull));
    pull->rtmp = RTMP_Alloc();
    RTMP_Init(pull->rtmp);
    
    pull->messageCallback = callback;
    pull->messageCallbackParm = rtmpPullParm;
    pull->stopRequest = GFalse;
    pthread_mutex_init(&pull->mutex, NULL);
    *pullP = pull;
    return GTrue;
}

GVoid GJRtmpPull_Delloc(GJRtmpPull* pull){
    if (pull) {
        RTMP_Free(pull->rtmp);
        free(pull);
        GJLOG(GJ_LOGDEBUG, "GJRtmpPull_Delloc:%p",pull);
    }else{
        GJLOG(GJ_LOGWARNING, "GJRtmpPull_Delloc NULL PULL");
    }
}
GVoid GJRtmpPull_Close(GJRtmpPull* pull){
    GJLOG(GJ_LOGDEBUG, "GJRtmpPull_Close:%p",pull);
    pull->stopRequest = GTrue;

}
GVoid GJRtmpPull_Release(GJRtmpPull* pull){
    GJLOG(GJ_LOGDEBUG, "GJRtmpPull_Release:%p",pull);
    GBool shouldDelloc = GFalse;
    pthread_mutex_lock(&pull->mutex);
    pull->messageCallback = NULL;
    pull->releaseRequest = GTrue;
    if (pull->pullThread == NULL) {
        shouldDelloc = GTrue;
    }
    pthread_mutex_unlock(&pull->mutex);
    if (shouldDelloc) {
        GJRtmpPull_Delloc(pull);
    }
}
GVoid GJRtmpPull_CloseAndRelease(GJRtmpPull* pull){
    GJRtmpPull_Close(pull);
    GJRtmpPull_Release(pull);
}

GBool GJRtmpPull_StartConnect(GJRtmpPull* pull,PullVideoDataCallback videoCallback,PullAudioDataCallback audioCallback,GHandle callbackParm,const GChar* pullUrl){
    GJLOG(GJ_LOGDEBUG, "GJRtmpPull_StartConnect:%p",pull);

    if (pull->pullThread != NULL) {
        GJRtmpPull_Close(pull);
        pthread_join(pull->pullThread, NULL);
    }
    size_t length = strlen(pullUrl);
    GJAssert(length <= MAX_URL_LENGTH-1, "sendURL 长度不能大于：%d",MAX_URL_LENGTH-1);
    memcpy(pull->pullUrl, pullUrl, length+1);
    pull->stopRequest = GFalse;
    pull->videoCallback = videoCallback;
    pull->audioCallback = audioCallback;
    pull->dataCallbackParm = callbackParm;
    pthread_create(&pull->pullThread, NULL, pullRunloop, pull);
    return GTrue;
}
GJTrafficUnit GJRtmpPull_GetVideoPullInfo(GJRtmpPull* pull){
    return pull->videoPullInfo;
}
GJTrafficUnit GJRtmpPull_GetAudioPullInfo(GJRtmpPull* pull){
    return pull->audioPullInfo;
}
