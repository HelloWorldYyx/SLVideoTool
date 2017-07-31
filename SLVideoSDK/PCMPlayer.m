//
//  PCMPlayer.m
//  AudioFileServices
//
//  Created by admin on 26/7/17.
//  Copyright © 2017年 baxiang. All rights reserved.
//

#import "PCMPlayer.h"
//#import <AVFoundation/AVFoundation.h>
#define MIN_SIZE_PER_FRAME 2000
#define QUEUE_BUFFER_SIZE 3 //队列缓冲个数

@interface PCMPlayer ()
{
    AudioQueueRef audioQueue;                                   //音频播放队列
    AudioStreamBasicDescription _audioDescription;
    AudioQueueBufferRef audioQueueBuffers[QUEUE_BUFFER_SIZE];   //音频缓冲
    BOOL audioQueueBufferUsed[QUEUE_BUFFER_SIZE];               //判断音频缓冲是否在使用
    NSLock *sysnLock;
    NSMutableData *tempData;
    OSStatus osState;
    BOOL isFirst;
    AudioConverterRef m_converter;
}
@end


@implementation PCMPlayer
- (instancetype)init
{
    self = [super init];
    if (self) {
        sysnLock = [[NSLock alloc]init];
        isFirst = YES;
        // 播放PCM使用
        if (_audioDescription.mSampleRate <= 0) {
            //设置音频参数
            _audioDescription.mSampleRate = 44100.0;//采样率
            _audioDescription.mFormatID = kAudioFormatLinearPCM;
            // 下面这个是保存音频数据的方式的说明，如可以根据大端字节序或小端字节序，浮点数或整数以及不同体位去保存数据
            _audioDescription.mFormatFlags = kLinearPCMFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked;
            //1单声道 2双声道
            _audioDescription.mChannelsPerFrame = 1;
            //每一个packet一侦数据,每个数据包下的桢数，即每个数据包里面有多少桢
            _audioDescription.mFramesPerPacket = 1;
            //每个采样点16bit量化 语音每采样点占用位数
            _audioDescription.mBitsPerChannel = 16;
            _audioDescription.mBytesPerFrame = (_audioDescription.mBitsPerChannel / 8) * _audioDescription.mChannelsPerFrame;
            //每个数据包的bytes总数，每桢的bytes数*每个数据包的桢数
            _audioDescription.mBytesPerPacket = _audioDescription.mBytesPerFrame * _audioDescription.mFramesPerPacket;
        }
        
        // 使用player的内部线程播放 新建输出
        AudioQueueNewOutput(&_audioDescription, AudioPlayerAQInputCallback, (__bridge void * _Nullable)(self), nil, 0, 0, &audioQueue);
        
        // 设置音量
        AudioQueueSetParameter(audioQueue, kAudioQueueParam_Volume, 1.0);
        
        // 初始化需要的缓冲区
        for (int i = 0; i < QUEUE_BUFFER_SIZE; i++) {
            audioQueueBufferUsed[i] = false;
            
            osState = AudioQueueAllocateBuffer(audioQueue, MIN_SIZE_PER_FRAME, &audioQueueBuffers[i]);
            
            printf("第 %d 个AudioQueueAllocateBuffer 初始化结果 %d (0表示成功)", i + 1, osState);
        }
        
        osState = AudioQueueStart(audioQueue, NULL);
        if (osState != noErr) {
            printf("AudioQueueStart Error");
        }
    }
    return self;
}


- (void)resetPlay{
    if (audioQueue != nil) {
        AudioQueueReset(audioQueue);
    }
}


//播放相关
- (void)playAudioWithSampleBufferRef:(CMSampleBufferRef)sampleBufferRef{
//    if (!isFirst) {
//        return;
//    }
    isFirst = !isFirst;
    [sysnLock lock];
    
    CMBlockBufferRef blockBufferRef = CMSampleBufferGetDataBuffer(sampleBufferRef);
    size_t length = CMBlockBufferGetDataLength(blockBufferRef);
    Byte buffer[length];
    CMBlockBufferCopyDataBytes(blockBufferRef, 0, length, buffer);
    NSData *data1 = [NSData dataWithBytes:buffer length:length];
    
    
    tempData = [NSMutableData new];
    [tempData appendData:data1];
    //得到数据
    NSUInteger len = tempData.length;
    Byte *bytes = (Byte *)malloc(len);
    int i = 0;
    while (true) {
        if ((!audioQueueBufferUsed[i])) {
            audioQueueBufferUsed[i] = true;
            break;
        } else {
            i++;
            if (i >= QUEUE_BUFFER_SIZE) {
                i = 0;
            }
        }
    }
    audioQueueBuffers[i] -> mAudioDataByteSize = (unsigned int)len;
    
    //把byte的头地址开始的len字节给mAudioData
    memcpy(audioQueueBuffers[i] -> mAudioData, bytes, len);
    
    free(bytes);
    AudioQueueEnqueueBuffer(audioQueue, audioQueueBuffers[i], 0, NULL);
    AudioQueueSetParameter(audioQueue, kAudioQueueParam_Volume, 1.0);
    NSLog(@"本次播放数据大小:%ld",len);
    AudioQueueStart(audioQueue, NULL);
    [sysnLock unlock];
}


// 回调回来把buffer状态设为未使用
static void AudioPlayerAQInputCallback(void* inUserData,AudioQueueRef audioQueueRef, AudioQueueBufferRef audioQueueBufferRef) {
    
    PCMPlayer* player = (__bridge PCMPlayer*)inUserData;
    
    [player resetBufferState:audioQueueRef and:audioQueueBufferRef];
}

- (void)resetBufferState:(AudioQueueRef)audioQueueRef and:(AudioQueueBufferRef)audioQueueBufferRef {
    // 防止空数据让audioqueue后续都不播放(未验证)
    if (tempData.length == 0) {
        audioQueueBufferRef->mAudioDataByteSize = 1;
        Byte* byte = audioQueueBufferRef->mAudioData;
        byte = 0;
        AudioQueueEnqueueBuffer(audioQueueRef, audioQueueBufferRef, 0, NULL);
    }
    
    for (int i = 0; i < QUEUE_BUFFER_SIZE; i++) {
        // 将这个buffer设为未使用
        if (audioQueueBufferRef == audioQueueBuffers[i]) {
            audioQueueBufferUsed[i] = false;
        }
    }
}

// ************************** 内存回收 **********************************

- (void)dealloc {
    
    if (audioQueue != nil) {
        AudioQueueStop(audioQueue,true);
    }
    
    audioQueue = nil;
    sysnLock = nil;
    printf("dealloc...");
}
//*********    samplebuffer编码成AAC  *************************

- (BOOL)createAudioConvert:(CMSampleBufferRef)sampleBuffer{
    if (sampleBuffer == nil) {
        return NO;
    }
    AudioStreamBasicDescription inputFormat = *(CMAudioFormatDescriptionGetStreamBasicDescription(CMSampleBufferGetFormatDescription(sampleBuffer)));
    AudioStreamBasicDescription outputFormat; //输出音频格式
//    menmset
    outputFormat.mSampleRate        = inputFormat.mSampleRate;//采样率
    outputFormat.mFormatID          = kAudioFormatMPEG4AAC;//AAC编码
    outputFormat.mChannelsPerFrame  = inputFormat.mChannelsPerFrame; //1 单声道 2 双声道
    outputFormat.mFramesPerPacket   = 1024;  //AAC 一帧是1024个字节
    AudioClassDescription *desc = [self getAudioClassDescriptionWithType:kAudioFormatMPEG4AAC fromManufacturer:kAppleSoftwareAudioCodecManufacturer];
    if (AudioConverterNewSpecific(&inputFormat, &outputFormat, 1, desc, &m_converter) != noErr) {
        NSLog(@"audioConverterNewSpecific failed");
        return NO;
    }
    return  YES;
}

//编码PCM成AAC
- (BOOL)encoderAAC:(CMSampleBufferRef)samplebuffer aacData:(char*)aacData aacLen:(int*)aacLen{
    if ([self createAudioConvert:samplebuffer] != YES) {
        return NO;
    }
    CMBlockBufferRef blockBuffer = nil;
    AudioBufferList inBufferList;
    if ((CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(samplebuffer, NULL, &inBufferList, sizeof(inBufferList), NULL, NULL, 0, &blockBuffer) != noErr)) {
        NSLog(@"CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer failed");
        return NO;
    }
    // 初始化一个输出缓冲列表
    AudioBufferList outBufferList;
    outBufferList.mNumberBuffers              = 1;
    outBufferList.mBuffers[0].mNumberChannels = 2;
    outBufferList.mBuffers[0].mDataByteSize   = *aacLen; //设置缓冲区大小
    outBufferList.mBuffers[0].mData           = aacData;
    UInt32 outputDataPacketSize               = 1;
    if (AudioConverterFillComplexBuffer(m_converter, inputDataProc, &inBufferList, &outputDataPacketSize, &outBufferList, NULL) != noErr)
    {
        NSLog(@"AudioConverterFillComplexBuffer failed");
        return NO;
    }
    *aacLen = outBufferList.mBuffers[0].mDataByteSize; // 设置编码后的AAC大小
    CFRelease(blockBuffer);
    return YES;
    
}

- (AudioClassDescription *)getAudioClassDescriptionWithType:(UInt32)type fromManufacturer:(UInt32)manufacturer {
    static AudioClassDescription audioDesc;
    UInt32 encoderSpecifier = type, size = 0;
    OSStatus status;
    status = AudioFormatGetPropertyInfo(kAudioFormatProperty_Encoders, sizeof(encoderSpecifier), &encoderSpecifier, &size);
    if (status) {
        return nil;
    }
    uint32_t count = size / sizeof(AudioClassDescription);
    AudioClassDescription descs[count];
    status = AudioFormatGetProperty(kAudioFormatProperty_Encoders, sizeof(encoderSpecifier), &encoderSpecifier, &size, descs);
    for (uint32_t i = 0; i < count; i++) {
        if ((type == descs[i].mSubType) && (manufacturer == descs[i].mManufacturer)) {
            memcpy(&audioDesc, &descs[i], sizeof(audioDesc));
            break;
        }
    }
    return &audioDesc;
}

OSStatus inputDataProc(AudioConverterRef inConverter, UInt32 *ioNumberDataPackets, AudioBufferList *ioData,AudioStreamPacketDescription **outDataPacketDescription, void *inUserData) {
    ///< style="font-family: Arial, Helvetica, sans-serif;">AudioConverterFillComplexBuffer 编码过程中，会要求这个函数来填充输入数据，也就是原始PCM数据</span>
    AudioBufferList bufferList = *(AudioBufferList*)inUserData;
    ioData->mBuffers[0].mNumberChannels = 1;
    ioData->mBuffers[0].mData           = bufferList.mBuffers[0].mData;
    ioData->mBuffers[0].mDataByteSize   = bufferList.mBuffers[0].mDataByteSize;
    return noErr;
}
@end
