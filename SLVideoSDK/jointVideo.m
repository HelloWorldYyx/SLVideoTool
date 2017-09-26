//
//  jointVideo.m
//  SLVideoSDK
//
//  Created by admin on 22/9/17.
//  Copyright © 2017年 YYX. All rights reserved.
//

#import "jointVideo.h"

@interface jointVideo()

@property (nonatomic, strong) AVAsset *AVAsset;
@end
@implementation jointVideo

@synthesize mainComposition = mainComposition_;
@synthesize videoComposition = videoComposition_;
@synthesize audioMix = audioMix_;

-(instancetype)init{
    if (self = [super init]) {
        
    }
    return self;
}



- (BOOL)jointVideoWithAsset:(AVAsset *)asset spliceAsset:(AVAsset *)spliceAsset{
    
    AVAsset *selectAsset = asset;
    CMTimeRange timeRange = CMTimeRangeMake(kCMTimeZero, asset.duration);
    //两个时间比较 可以这样来判断这个时间是否是无效时间
    if (CMTIME_COMPARE_INLINE(kCMTimeZero, !=, kCMTimeInvalid)) {
        
    }
    
    AVMutableComposition *mainComposition = [[AVMutableComposition alloc] init];
    AVMutableCompositionTrack *compositionVideoTrack = [mainComposition addMutableTrackWithMediaType:AVMediaTypeVideo preferredTrackID:kCMPersistentTrackID_Invalid];
    AVMutableCompositionTrack *soundtrackTrack = [mainComposition addMutableTrackWithMediaType:AVMediaTypeAudio preferredTrackID:kCMPersistentTrackID_Invalid];
    
    CMTime VideostartTime = kCMTimeZero;
    NSArray<AVAssetTrack *> *videoTrackers = [selectAsset tracksWithMediaType:AVMediaTypeVideo];
    if(0 >= videoTrackers.count){
        return nil;
    }
    
    [compositionVideoTrack insertTimeRange:timeRange
                                   ofTrack:[videoTrackers objectAtIndex:0]
                                    atTime:VideostartTime error:nil];
    
    NSArray<AVAssetTrack *> *soundTrackers = [selectAsset tracksWithMediaType:AVMediaTypeAudio];
    if(0 >= soundTrackers.count){
        NSLog(@"无声资源");
    } else {
        
        [soundtrackTrack insertTimeRange:timeRange
                                 ofTrack:[soundTrackers objectAtIndex:0]
                                  atTime:VideostartTime
                                   error:nil];
    }
    
    
    
    //开始拼接
    AVURLAsset *mixAsset = (AVURLAsset *)spliceAsset;
    
    float cb_seconds = (float)timeRange.duration.value / (float)timeRange.duration.timescale;
    CMTime connect_start_time = CMTimeMake(cb_seconds * mixAsset.duration.timescale, mixAsset.duration.timescale);
    NSArray<AVAssetTrack *> *videoTrackers_2 = [mixAsset tracksWithMediaType:AVMediaTypeVideo];
    NSError *t_error = nil;
    [compositionVideoTrack insertTimeRange:CMTimeRangeMake(kCMTimeZero, mixAsset.duration) //just for video connect test
                                   ofTrack:[videoTrackers_2 objectAtIndex:0]
                                    atTime:connect_start_time
                                     error:&t_error];
    if(0 >= videoTrackers_2.count){
        
    }
    
    NSArray<AVAssetTrack *> *soundTrackers_2 = [mixAsset tracksWithMediaType:AVMediaTypeAudio];
    if(0 >= soundTrackers_2.count){
        
    } else {
        [soundtrackTrack insertTimeRange:CMTimeRangeMake(kCMTimeZero, mixAsset.duration)
                                 ofTrack:[soundTrackers_2 objectAtIndex:0]
                                  atTime:connect_start_time
                                   error:&t_error];
        if(t_error)
        {
            return nil;
        }
    }
    
    
    
    AVMutableVideoComposition *select_videoComposition = [AVMutableVideoComposition videoCompositionWithPropertiesOfAsset:mainComposition];
    
    NSArray<AVMutableVideoCompositionInstruction *> *videocomIns = select_videoComposition.instructions;
    //调整LayerStack的ConstantAffineMatrix
    AVMutableVideoComposition *first_vcn = [AVMutableVideoComposition videoCompositionWithPropertiesOfAsset:selectAsset];
    AVMutableVideoComposition *second_vcn = [AVMutableVideoComposition videoCompositionWithPropertiesOfAsset:mixAsset];
    
    CGAffineTransform fir_video_adjust_t = [[selectAsset tracksWithMediaType:AVMediaTypeVideo] objectAtIndex:0].preferredTransform;
    CGAffineTransform sec_video_adjust_t = [[mixAsset tracksWithMediaType:AVMediaTypeVideo] objectAtIndex:0].preferredTransform;
    CGSize adjust_t_size = CGSizeZero;
    
    CGSize fir_ren_size = first_vcn.renderSize;
    CGSize sec_ren_size = second_vcn.renderSize;
    
    adjust_t_size = CGSizeMake(MAX(fir_ren_size.width, sec_ren_size.width), MAX(fir_ren_size.height, sec_ren_size.height));
    CGFloat fir_aspect_scale = MIN(adjust_t_size.width / fir_ren_size.width, adjust_t_size.height / fir_ren_size.height);
    CGFloat sec_aspect_scale = MIN(adjust_t_size.width / sec_ren_size.width, adjust_t_size.height / sec_ren_size.height);
    //first video frame adjust
    fir_video_adjust_t = CGAffineTransformScale(fir_video_adjust_t, fir_aspect_scale, fir_aspect_scale);
    fir_ren_size.width *= fir_aspect_scale;
    fir_ren_size.height *= fir_aspect_scale;
    CGFloat fir_adjust_t_t_x = (adjust_t_size.width - fir_ren_size.width) / 2.0;
    CGFloat fir_adjust_t_t_y = (adjust_t_size.height - fir_ren_size.height) / 2.0;
    fir_video_adjust_t = CGAffineTransformTranslate(fir_video_adjust_t, fir_adjust_t_t_x / fir_aspect_scale, fir_adjust_t_t_y / fir_aspect_scale);
    //second video frame adjust
    sec_video_adjust_t = CGAffineTransformScale(sec_video_adjust_t, sec_aspect_scale, sec_aspect_scale);
    sec_ren_size.width *= sec_aspect_scale;
    sec_ren_size.height *= sec_aspect_scale;
    CGFloat sec_adjust_t_t_x = (adjust_t_size.width - sec_ren_size.width) / 2.0;
    CGFloat sec_adjust_t_t_y = (adjust_t_size.height - sec_ren_size.height) / 2.0;
    sec_video_adjust_t = CGAffineTransformTranslate(sec_video_adjust_t, sec_adjust_t_t_x / sec_aspect_scale, sec_adjust_t_t_y / sec_aspect_scale);
    
    AVMutableVideoCompositionInstruction *t_video_com_ins = [videocomIns objectAtIndex:0];
    CMTimeRange t_ran = t_video_com_ins.timeRange;
    
    AVMutableVideoCompositionLayerInstruction *t_layer_ins = [self copyAndResetVideoLayerInstruction:[t_video_com_ins.layerInstructions objectAtIndex:0] withStartTransform:fir_video_adjust_t endTransform:fir_video_adjust_t timeRange:t_video_com_ins.timeRange desiredEasy:YES];
    t_video_com_ins.layerInstructions = @[t_layer_ins];
    
    t_video_com_ins = [videocomIns objectAtIndex:1];
    t_ran = t_video_com_ins.timeRange;
    
    t_layer_ins = [self copyAndResetVideoLayerInstruction:[t_video_com_ins.layerInstructions objectAtIndex:0] withStartTransform:sec_video_adjust_t endTransform:sec_video_adjust_t timeRange:t_video_com_ins.timeRange desiredEasy:YES];
    t_video_com_ins.layerInstructions = @[t_layer_ins];
    
    
    select_videoComposition.renderSize = adjust_t_size;
    select_videoComposition.instructions = videocomIns;
    
    AVMutableAudioMix *videoAudioMixTools = [AVMutableAudioMix audioMix];

    
    
    
    return YES;
}
- (AVMutableVideoCompositionLayerInstruction *)copyAndResetVideoLayerInstruction:(AVVideoCompositionLayerInstruction *)ins
                                                              withStartTransform:(CGAffineTransform)strans
                                                                    endTransform:(CGAffineTransform)etrans
                                                                       timeRange:(CMTimeRange)trange
                                                                     desiredEasy:(BOOL)easy{
    AVMutableVideoCompositionLayerInstruction *videoLayerIns = [AVMutableVideoCompositionLayerInstruction videoCompositionLayerInstruction];
    videoLayerIns.trackID = ins.trackID;
    
    [videoLayerIns setTransformRampFromStartTransform:strans toEndTransform:etrans timeRange:trange];
    
    if(easy){
        float totoal_duration_seconds = (float)trange.duration.value / (float)trange.duration.timescale;    //附加 for  test
        if(totoal_duration_seconds > 1.0){
            CMTime easyInDuration = CMTimeMake(1.0 * trange.duration.timescale, trange.duration.timescale);
            
            [videoLayerIns setOpacityRampFromStartOpacity:0.0 toEndOpacity:1.0 timeRange:CMTimeRangeMake(trange.start, easyInDuration)];
        }
        if(totoal_duration_seconds > 2.0){
            CMTime easyOutDuration = CMTimeMake(1.0 * trange.duration.timescale, trange.duration.timescale);
            
            CMTime easyOutStartTime = CMTimeSubtract(CMTimeAdd(trange.start, trange.duration), easyOutDuration);
            
            [videoLayerIns setOpacityRampFromStartOpacity:1.0 toEndOpacity:0.0 timeRange:CMTimeRangeMake(easyOutStartTime, easyOutDuration)];
        }
    }
    
    return videoLayerIns;
}

- (void)spliceVideoWithArray:(NSArray *)arrayAssetFile outputFile:(NSString *)outputFile{
    
    NSMutableArray *arrayAsset = [NSMutableArray array];
    for (NSString *file in arrayAssetFile) {
        AVURLAsset *asset = [AVURLAsset assetWithURL:[NSURL fileURLWithPath:file]];
        [arrayAsset addObject:asset];
    }
    AVMutableComposition *composition = [AVMutableComposition composition];
    AVMutableCompositionTrack *trackVideo = [composition addMutableTrackWithMediaType:AVMediaTypeVideo preferredTrackID:kCMPersistentTrackID_Invalid];
    AVMutableCompositionTrack *trackAudio = [composition addMutableTrackWithMediaType:AVMediaTypeVideo preferredTrackID:kCMPersistentTrackID_Invalid];
    NSArray *videoTracks = @[trackVideo, trackAudio];
    NSMutableArray *videoAssets = (NSMutableArray *)arrayAsset;
    CMTime cursorTime = kCMTimeZero;
    CMTime transitionDuration = CMTimeMake(2, 1);
    for (NSUInteger i = 0; i < videoAssets.count; i++) {
        NSUInteger  trackIndex  = i % 2;
        AVMutableCompositionTrack *currenTrack = videoTracks[trackIndex];
        AVAsset *asset  = videoAssets[i];
        NSArray <AVAssetTrack *> *arrayTrack = [asset tracksWithMediaType:AVMediaTypeVideo];
        if (arrayTrack.count <= 0) {
            return;
        }
        AVAssetTrack *assetTrack = [arrayTrack firstObject];
        CMTimeRange timeRange = CMTimeRangeMake(kCMTimeZero, asset.duration);
        [currenTrack insertTimeRange:timeRange
                             ofTrack:assetTrack
                              atTime:cursorTime
                               error:nil];
        cursorTime = CMTimeAdd(cursorTime, timeRange.duration);
        cursorTime = CMTimeSubtract(cursorTime, transitionDuration);
    }
    
    
    //获取过渡和通过时间
    CMTime cursorTime1 = kCMTimeZero;
    NSMutableArray *passThroughTimeRanges = [NSMutableArray array];
    NSMutableArray *transitionTimeRnages  = [NSMutableArray array];
    
    NSUInteger videoCount = videoAssets.count;
    for (NSUInteger i = 0; i < videoCount; i++) {
        AVAsset *asset = videoAssets[i];
        CMTimeRange timeRange = CMTimeRangeMake(cursorTime1, asset.duration);
        if (i > 0) {
            timeRange.start = CMTimeAdd(timeRange.start, transitionDuration);
            timeRange.duration = CMTimeSubtract(timeRange.duration, transitionDuration);
        }
        if (i+1 < videoCount) {
            timeRange.duration  = CMTimeSubtract(timeRange.duration, transitionDuration);
        }
        [passThroughTimeRanges addObject:[NSValue valueWithCMTimeRange:timeRange]];
        
        cursorTime1 = CMTimeAdd(cursorTime1, asset.duration);
        cursorTime1 = CMTimeSubtract(cursorTime1, transitionDuration);
        if (i+1 < videoCount) {
            timeRange = CMTimeRangeMake(cursorTime1, transitionDuration);
            NSValue *timeRangeValue = [NSValue valueWithCMTimeRange:timeRange];
            [transitionTimeRnages addObject:timeRangeValue];
        }
        
    }
    
    //创建组合 和 层指令
    NSMutableArray *compositionInstructions = [NSMutableArray array];
    NSArray *tracks = [composition tracksWithMediaType:AVMediaTypeVideo];
    for (int i = 0; i< passThroughTimeRanges.count; i++) {
        NSUInteger trackIndex = i % 2;
        AVMutableCompositionTrack *currentTrack = tracks[trackIndex];
        AVMutableVideoCompositionInstruction *instruction = [AVMutableVideoCompositionInstruction videoCompositionInstruction];
        instruction.timeRange = [passThroughTimeRanges[i] CMTimeRangeValue];
        AVMutableVideoCompositionLayerInstruction *layerInstruction = [AVMutableVideoCompositionLayerInstruction videoCompositionLayerInstructionWithAssetTrack:currentTrack];
        instruction.layerInstructions = @[layerInstruction];
        [compositionInstructions addObject:instruction];
        if (i < transitionTimeRnages.count) {
            AVCompositionTrack *foregroundTrack = tracks[trackIndex];
            AVCompositionTrack *backgroundTrack = tracks[1 - trackIndex];\
            AVMutableVideoCompositionInstruction *instruction = [AVMutableVideoCompositionInstruction videoCompositionInstruction];
            CMTimeRange timeRange = [transitionTimeRnages[i] CMTimeRangeValue];
            instruction.timeRange = timeRange;
            AVMutableVideoCompositionLayerInstruction *fromlayerinstruction = [AVMutableVideoCompositionLayerInstruction videoCompositionLayerInstructionWithAssetTrack:foregroundTrack];
            AVMutableVideoCompositionLayerInstruction *tolayerInstruction = [AVMutableVideoCompositionLayerInstruction videoCompositionLayerInstructionWithAssetTrack:backgroundTrack];
            
            instruction.layerInstructions = @[fromlayerinstruction,tolayerInstruction];
            [compositionInstructions addObject:instruction];
        }
    }
    
    //配置AVvideoComposition
    AVMutableVideoComposition *videoComposition = [AVMutableVideoComposition videoComposition];
    videoComposition.instructions = compositionInstructions;
    videoComposition.renderSize = CGSizeMake(1280.0f, 720.0f);
    videoComposition.frameDuration = CMTimeMake(1, 30);
    videoComposition.renderScale = 1.0f;
    
    videoComposition_ = videoComposition;
    audioMix_ = [AVMutableAudioMix audioMix];
    mainComposition_ = composition;
    
    

}

@end
