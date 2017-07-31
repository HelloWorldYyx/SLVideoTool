//
//  PCMPlayer.h
//  AudioFileServices
//
//  Created by admin on 26/7/17.
//  Copyright © 2017年 baxiang. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>

@interface PCMPlayer : NSObject


//播放并顺带附上数据
- (void)playAudioWithSampleBufferRef:(CMSampleBufferRef)sampleBufferRef;

//reset
- (void)resetPlay;

//编码PCM成AAC
- (BOOL)encoderAAC:(CMSampleBufferRef)samplebuffer aacData:(char*)aacData aacLen:(int*)aacLen;

- (void)playAudioWithData:(NSData *)data;
@end
