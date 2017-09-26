//
//  jointVideo.h
//  SLVideoSDK
//
//  Created by admin on 22/9/17.
//  Copyright © 2017年 YYX. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
@interface jointVideo : NSObject
{
    
    
    
}
@property (nonatomic, strong) AVComposition *mainComposition;
@property (nonatomic, strong) AVAudioMix *audioMix;
@property (nonatomic, strong) AVVideoComposition *videoComposition;

- (void)spliceVideoWithArray:(NSArray *)arrayAssetFile outputFile:(NSString *)outputFile;
@end
