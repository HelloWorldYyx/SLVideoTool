//
//  OISamplebufferRef.m
//  SLVideoSDK
//
//  Created by admin on 1/9/17.
//  Copyright © 2017年 YYX. All rights reserved.
//

#import "OISamplebufferRef.h"

@implementation OISamplebufferRef
- (void)setSampleBuffer:(CMSampleBufferRef)sampleBuffer{
    if (sampleBuffer) {
        _sampleBuffer = sampleBuffer;
    }
}
@end
