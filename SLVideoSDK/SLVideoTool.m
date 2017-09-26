//
//  SLVideoTool.m
//  SLVideoSDK
//
//  Created by admin on 27/6/17.
//  Copyright © 2017年 YYX. All rights reserved.
//

#import "SLVideoTool.h"

#import "OISamplebufferRef.h"


NSString * const SLVideoMixingAudioParameterAudioAssetURLKey    = @"Audio asset URL";
NSString * const SLVideoMixingAudioParameterVideoVolumeKey      = @"Video volume";
NSString * const SLVideoMixingAudioParameterAudioVolumeKey      = @"Audio volume";
NSString * const SLVideoMixingAudioParameterAudioStartTimeKey   = @"Audio start time";
NSString * const SLVideoMixingAudioParameterTimeRangeOfVideoKey = @"Time range of video";
NSString * const SlVideoMixingAudioParameterTimeRangeOfAudioKey = @"Time range of audio";

@interface SLVideoTool ()
{
    AVAssetReader *assetReader_;
    AVAssetReaderTrackOutput *videoTrackOutput_;
    AVAssetReaderTrackOutput *audioTrackOutput_;
    AVAsset *AVAsset_;
    AVAsset *originalAsset_;
    NSURL *URL_;
    id <SLVideoToolDelegate> delegate__;
    SLVideoStatus status_;
    NSTimeInterval previousFrameActualTime_;
    BOOL shouldStopPlaying_;
    AVMutableComposition *mainComposition_;
    AVMutableAudioMix *videoAudioMixTools_;
    AVMutableVideoComposition *selectVideoComposition_;
    BOOL isClip_;
    BOOL isMix_;
    NSDictionary *parametersDic_;
    CMTimeRange clipTimeRange_;
    
        
    NSMutableArray *reverseCacheBlocks_;
    NSMutableArray *reverseCacheFramesCMtimes_;
    NSInteger reverseBlockSize_;
    

}
@end

@implementation SLVideoTool

@synthesize AVAsset = AVAsset_;
@synthesize URL = URL_;
@synthesize delegate = delegate_;
@synthesize status = status_;
@synthesize mainComposition = mainComposition_;
@synthesize videoAudioMixTools = videoAudioMixTools_;
@synthesize selectVideoComposition = selectVideoComposition_;
@synthesize assetReader = assetReader_;

- (instancetype)init{
    if (self = [super init]) {
        assetReader_       = nil;
        videoTrackOutput_  = nil;
        audioTrackOutput_  = nil;
        AVAsset_           = nil;
        URL_               = nil;
        delegate_          = nil;
        _orientation       = SLVideoOrientationUnKnown;
        _progress          = 0.0;
        _size              = CGSizeZero;
        isClip_            = NO;
        isMix_             = NO;
    }
    return self;
}

- (instancetype)initWithAVAsset:(AVAsset *)asset{
    if (self = [super init]) {
        self.AVAsset = asset;
        originalAsset_ = asset;

    }
    return self;
}

- (instancetype)initWithURL:(NSURL *)URL{
    if (self = [super init]) {
        self.URL = URL;
        originalAsset_ = self.AVAsset;
        reverseCacheBlocks_ = [[NSMutableArray alloc] init];
        reverseCacheFramesCMtimes_ = [[NSMutableArray alloc] init];
        reverseBlockSize_ = 1;

    }
    return self;
}

#pragma mark - Properties` Setter && Getter

- (void)setAVAsset:(AVAsset *)AVAsset{
    if (AVAsset_ != AVAsset) {
        if (AVAsset_) {
            AVAsset_ = nil;
        }
        if (AVAsset) {
            AVAsset_ = AVAsset;
            NSArray *tracks = [AVAsset_ tracksWithMediaType:AVMediaTypeVideo];
            if (0 < [tracks count]) {
                AVAssetTrack *videoTrack = [tracks objectAtIndex:0];
                CGAffineTransform transform = videoTrack.preferredTransform;
                if (transform.a == 0
                    && transform.b == 1.0
                    && transform.c == -1.0
                    && transform.d == 0) {
                    _orientation = SLVideoOrientationPortrait;
                } else if (transform.a == 0
                           && transform.b == -1.0
                           && transform.c == 1.0
                           && transform.d == 0) {
                    _orientation = SLVideoOrientationPOrtraitUpsideDown;
                } else if (transform.a == 1.0
                           && transform.b == 0
                           && transform.c == 0
                           && transform.d == 1.0) {
                    _orientation = SLVideoOrientationLandscapeLeft;
                } else if (transform.a == -1.0
                           && transform.b == 0
                           && transform.c == 0
                           && transform.d == -1.0) {
                    _orientation = SLvideoOrientationLandscapeRight;
                }
                
                if (_orientation == SLVideoOrientationPortrait || _orientation == SLVideoOrientationPOrtraitUpsideDown) {
                    _size = CGSizeMake(videoTrack.naturalSize.width, videoTrack.naturalSize.height);
                } else {
                    _size = videoTrack.naturalSize;
                }
            }
        }
    }
}

- (void)setURL:(NSURL *)URL {
    if (URL_ != URL) {
        if (URL_) {
            URL_ = nil;
        }
        if (URL) {
            URL_ = URL;
        } else {
            self.AVAsset = nil;
            return;
        }
        NSDictionary *options = [NSDictionary dictionaryWithObject:[NSNumber numberWithBool:YES] forKey:AVURLAssetPreferPreciseDurationAndTimingKey];
        AVURLAsset *urlAsset = [AVURLAsset URLAssetWithURL:URL_ options:options];
        self.AVAsset = urlAsset;
    }
}

- (double)duration{
    double duration = 0.0;
    if (self.AVAsset) {
        duration = CMTimeGetSeconds(self.AVAsset.duration);
    }
    return duration;
}

#pragma mark - 剪切
/**
 剪切视频
 
 @param timeRange 剪切视频时间 类型为CMTimeRange 取值在视频的时间方位之内.
 */
- (void)clipWithTimeRange:(CMTimeRange)timeRange{
    
    if (timeRange.duration.value < 1) {
        self.AVAsset = originalAsset_;
        return;
    }
    isClip_ = YES;
    clipTimeRange_ = timeRange;
    AVAsset *asset = originalAsset_;
    AVAssetTrack *videoAssetTrack = nil;
    AVAssetTrack *audioAssetTrack = nil;
    
    if (0 != [[asset tracksWithMediaType:AVMediaTypeVideo] count]) {
        videoAssetTrack = [[asset tracksWithMediaType:AVMediaTypeVideo] firstObject];
    } else {
        NSLog(@"数据有误,请检查资源数据");
        return;
    }
    if (0 != [[asset tracksWithMediaType:AVMediaTypeAudio] count]) {
        audioAssetTrack = [[asset tracksWithMediaType:AVMediaTypeAudio] firstObject];
    } else {
        NSLog(@"无声视频");
    }
    AVMutableComposition *mainComposition = [[AVMutableComposition alloc]init];
    float videoRangeTime = CMTimeGetSeconds(self.AVAsset.duration);
    float clipTime = CMTimeGetSeconds(timeRange.duration);
    float clipStartTime = CMTimeGetSeconds(timeRange.start);
    float timeDuration;
    if ((videoRangeTime - clipStartTime) < clipTime) {
        timeDuration = videoRangeTime - clipStartTime;
    } else {
        timeDuration = clipTime;
    }
    if (nil != videoAssetTrack) {
        AVMutableCompositionTrack *mutableVideoCompositionTrack = [mainComposition addMutableTrackWithMediaType:AVMediaTypeVideo preferredTrackID:kCMPersistentTrackID_Invalid];
        NSError *error = nil;
        [mutableVideoCompositionTrack insertTimeRange:CMTimeRangeMake(timeRange.start, CMTimeMake(timeDuration * self.AVAsset.duration.timescale, self.AVAsset.duration.timescale))
                                              ofTrack:videoAssetTrack
                                               atTime:kCMTimeZero
                                                error:&error];
        NSLog(@"视频数据插入Error:%@",error);
    }
    if (nil != audioAssetTrack) {
        AVMutableCompositionTrack *mutableAudioCompositionTrack = [mainComposition addMutableTrackWithMediaType:AVMediaTypeAudio preferredTrackID:kCMPersistentTrackID_Invalid];
        NSError *error = nil;
        [mutableAudioCompositionTrack insertTimeRange:CMTimeRangeMake(timeRange.start, CMTimeMake(timeDuration * self.AVAsset.duration.timescale, self.AVAsset.duration.timescale))
                                              ofTrack:audioAssetTrack
                                               atTime:kCMTimeZero
                                                error:&error];
        
        NSLog(@"音频数据插入Error:%@",error);
    }
    self.AVAsset = mainComposition;
    if (isMix_) {
        [self mixAudioWithParameters:parametersDic_];
    }
    return;
}

#pragma mark - 混音
/**
 混音
 
 @param parameters 混音携带参数字典 URL => 混音音频资源; VideoVolume 视频音量 取值范围 0 ~ 1; AudioVolume 混音音量 取值范围 0 ~ 1; AudioStartTime 音频开始时间,该值是相对音频时间.而且取得值在音频范围内 类型 CMTime; TimeRangeOfAudio 音频的时间范围,该值是在音频资料上掘取的.不允许超过音频资料的时间范围 类型:CMTimeRange;
 @return BOOL 类型 返回YES 表示混音成功,返回NO 表示混音失败,并会打印失败LOG
 */
- (BOOL)mixAudioWithParameters:(NSDictionary *)parameters{
    parametersDic_ = parameters;
    isMix_ = YES;
    NSURL *asssetURL = [parameters objectForKey:SLVideoMixingAudioParameterAudioAssetURLKey];
    NSString *audioVolumeString  = [parameters objectForKey:SLVideoMixingAudioParameterAudioVolumeKey];

    float audioVolume = [audioVolumeString floatValue];
    
    NSString *videoVolumeString  = [parameters objectForKey:SLVideoMixingAudioParameterVideoVolumeKey];
    float videoVolume = [videoVolumeString floatValue];
    
    NSValue *audioStartTimeValue = [parameters valueForKey:SLVideoMixingAudioParameterAudioStartTimeKey];
    CMTime audioStartTime = [audioStartTimeValue CMTimeValue];
    
    NSValue *audioTimeRangeValue = [parameters valueForKey:SlVideoMixingAudioParameterTimeRangeOfAudioKey];
    CMTimeRange audioTimeRange = [audioTimeRangeValue CMTimeRangeValue];
    
    NSValue *videoTimeRangeValue = [parameters valueForKey:SLVideoMixingAudioParameterTimeRangeOfVideoKey];
    CMTimeRange videoTimeRange = [videoTimeRangeValue CMTimeRangeValue];
    
//    BOOL mixFinsh = [self mixAudioAssetAtURL:asssetURL
//                                 videoVolume:videoVolume
//                                 audioVolume:audioVolume
//                              audioStartTime:audioStartTime
//                              audioRangeTime:audioTimeRange
//                              vidioRangeTime:videoTimeRange];

    BOOL mixFinsh = [self YXmixAudioAssetAtURL:asssetURL
                                   videoVolume:videoVolume
                                   audioVolume:audioVolume
                                audioStartTime:audioStartTime
                                audioRangeTime:audioTimeRange
                                vidioRangeTime:videoTimeRange
                                slowVolumeTime:CMTimeMake(300, 100)];

    return mixFinsh;

}

/**
 混音
 
 @param audioAssetURL        混音URL
 @param videoVolume          视频音量               取值范围在 (0 - 1)
 @param audioVolume          背景音量               取值范围在 (0 - 1)
 @param startTime            背景音频第一次开始时间    该值是相对音频时间.而且取得值在音频范围内
 @param audioRangeTime       背景音频时间            该值是在音频资料上掘取的.不允许超过音频资料的时间范围
 @param videoRangeTime       混音范围                该值是在原视频上进行取值,表示混音的时间范围.
 @return                     返回BOOL类型.数据输入有误会返回NO并不做任何处理.错误信息会被LOG
 */
- (BOOL)mixAudioAssetAtURL:(NSURL *)audioAssetURL
               videoVolume:(float)videoVolume
               audioVolume:(float)audioVolume
            audioStartTime:(CMTime)startTime
            audioRangeTime:(CMTimeRange)audioRangeTime
            vidioRangeTime:(CMTimeRange)videoRangeTime{
    
    if (!audioAssetURL) {
        mainComposition_ = nil;
        videoAudioMixTools_ = nil;
        selectVideoComposition_ = nil;
        return YES;
        
    } else {
        
        if (videoVolume < 0
            || videoVolume > 1
            || audioVolume < 0
            || videoVolume > 1
            || startTime.value < 0
            || audioRangeTime.duration.value < 1) {
            //            OIErrorLog(YES, [self.class class], @"mixAudio", @"参数传入有误", @"请检查参数范围的问题");
            return NO;
        }
        //创建一个音视频组合轨道
        mainComposition_ = [[AVMutableComposition alloc] init];
        
        //可变音视频轨道添加一个 视频通道
        AVMutableCompositionTrack *compositionVideoTrack = [mainComposition_ addMutableTrackWithMediaType:AVMediaTypeVideo preferredTrackID:kCMPersistentTrackID_Invalid];
        
        //可变音视频轨道添加一个 音频通道
        AVMutableCompositionTrack *compositionAudioTrack = [mainComposition_ addMutableTrackWithMediaType:AVMediaTypeAudio preferredTrackID:kCMPersistentTrackID_Invalid];
        
        //视频通道数组
        NSArray<AVAssetTrack *> *videoTrackers = [AVAsset_ tracksWithMediaType:AVMediaTypeVideo];
        if (0 >= videoTrackers.count) {
            NSLog(@"数据获取失败");
            return NO;
        }
        
        //获取第一个视频通道
        AVAssetTrack *videoTrack = [videoTrackers objectAtIndex:0];
        
        //视频时间
        float videoTimes = CMTimeGetSeconds(self.AVAsset.duration);
        
        compositionVideoTrack.preferredTransform = videoTrack.preferredTransform;
        NSError *error = nil;
        
        //把采集轨道数据加入到可变轨道之中
        [compositionVideoTrack insertTimeRange:CMTimeRangeMake(kCMTimeZero, AVAsset_.duration)
                                       ofTrack:videoTrack
                                        atTime:kCMTimeZero
                                         error:&error];
        if (error) {
            //            OIErrorLog(YES, nil, nil, [NSString stringWithFormat:@"视轨错误:%@",error], nil);
            NSLog(@"视轨出错%@",error);
            return NO;
        }
        NSLog(@"%@",AVAsset_);
        //获取音频轨道数组
        NSArray<AVAssetTrack *> *audioTrackers = [AVAsset_ tracksWithMediaType:AVMediaTypeAudio];
        if (0 >= audioTrackers.count) {
            NSLog(@"音频数据获取失败");
        } else {
            //获取第一个音频轨道
            AVAssetTrack *audioTrack = [audioTrackers objectAtIndex:0];
            int audioTimeScale = audioTrack.naturalTimeScale;
            
            
            //获取音频的时间
            CMTime audioDuration = CMTimeMake(videoTimes * audioTimeScale, audioTimeScale);
            
            //讲音频轨道加入到可变轨道中
            [compositionAudioTrack insertTimeRange:CMTimeRangeMake(kCMTimeZero, audioDuration)
                                           ofTrack:audioTrack
                                            atTime:kCMTimeZero
                                             error:&error];
            if (error) {
                //                OIErrorLog(YES, nil, nil, [NSString stringWithFormat:@"音轨错误:%@",error], nil);
                NSLog(@"音轨错误:%@",error);
                return NO;
            }
        }
        
        //增加音轨
        //采集资源
        AVURLAsset *mixAsset = [[AVURLAsset alloc]initWithURL:audioAssetURL options:nil];
        NSArray<AVAssetTrack *> *audioTrackersMix = [mixAsset tracksWithMediaType:AVMediaTypeAudio];
        if (0 >= audioTrackersMix.count) {
            NSLog(@"获取第二音轨数据失败");
            return NO;
        }
        
        videoAudioMixTools_ = [AVMutableAudioMix audioMix];
        NSMutableArray <AVAudioMixInputParameters *> * inputParameterArray = [NSMutableArray array];
        
        if (!isClip_) {
            clipTimeRange_ = CMTimeRangeMake(kCMTimeZero, self.AVAsset.duration);
        }
        
        //混音第一次开始时间
        float audioStartSecond = CMTimeGetSeconds(startTime);
        
        //混音音频开始时间
        float audioRangeStartSecond = CMTimeGetSeconds(audioRangeTime.start);
        
        //混音音频的总时间
        float audioRangeSecond = CMTimeGetSeconds(audioRangeTime.duration);
        
        //混音的总时间
        float audioMixRangeSecond = CMTimeGetSeconds(videoRangeTime.duration);
        
        //混音最后一轨道的时间
        float audioEndSecond;
        //混音开始时间
        float videoRangeStartTime = CMTimeGetSeconds(videoRangeTime.start);
        float clipRangeStartTime = CMTimeGetSeconds(clipTimeRange_.start);
        float audioMixRangeStartSecond = CMTimeGetSeconds(videoRangeTime.start);
        float clipTimeRangeDuration = CMTimeGetSeconds(clipTimeRange_.duration);
        
        if (videoRangeStartTime > clipRangeStartTime) {
            

            if ((clipRangeStartTime + clipTimeRangeDuration) > (audioMixRangeSecond + audioMixRangeStartSecond)) {
                audioMixRangeSecond = CMTimeGetSeconds(videoRangeTime.duration);
            } else {
                audioMixRangeSecond = (clipRangeStartTime + clipTimeRangeDuration) - audioMixRangeStartSecond;
            }
             audioMixRangeStartSecond = videoRangeStartTime - clipRangeStartTime;
        } else {
            
            if ((clipRangeStartTime + clipTimeRangeDuration) > (audioMixRangeSecond + audioMixRangeStartSecond)) {
                audioMixRangeSecond = audioMixRangeSecond + audioMixRangeStartSecond - clipRangeStartTime;
            } else {
                audioMixRangeSecond = clipRangeStartTime + clipTimeRangeDuration - clipRangeStartTime;
            }
            audioMixRangeStartSecond = 0;
        }
        
        if (audioMixRangeSecond > videoTimes) {
            audioMixRangeSecond = videoTimes;
        }
        if (audioStartSecond > (audioRangeSecond + audioRangeStartSecond)
            || audioStartSecond < 0
            || audioStartSecond < audioRangeStartSecond
            || audioMixRangeStartSecond < 0
            || audioMixRangeSecond < 0) {
            NSLog(@"开始传入的数据有误");
            return NO;
        }
        
        //获取第一个音频轨道
        AVMutableAudioMixInputParameters *firstAudioParam = [AVMutableAudioMixInputParameters audioMixInputParametersWithTrack:compositionAudioTrack];
        
        //设置第一个音轨音量
        [firstAudioParam setVolumeRampFromStartVolume:videoVolume toEndVolume:videoVolume timeRange:CMTimeRangeMake(kCMTimeZero, AVAsset_.duration)];
        [inputParameterArray addObject:firstAudioParam];
        
        
        
        if (audioRangeSecond < audioMixRangeSecond) {
            int cycleIndex = (audioMixRangeSecond - (audioRangeSecond - (audioStartSecond - audioRangeStartSecond))) / audioRangeSecond;
            
            if (cycleIndex < 1) {
                //可变音视轨道再添音轨
                AVMutableCompositionTrack *mixAudioTrack = [mainComposition_ addMutableTrackWithMediaType:AVMediaTypeAudio preferredTrackID:kCMPersistentTrackID_Invalid];//第二音轨
                
                
                
                //讲采集到数据加入到音轨
                [mixAudioTrack insertTimeRange:CMTimeRangeMake(audioRangeTime.start, CMTimeMake((audioRangeSecond + audioRangeStartSecond - audioStartSecond) * audioRangeTime.duration.timescale, audioRangeTime.duration.timescale))
                                       ofTrack:[audioTrackersMix objectAtIndex:0]
                                        atTime:videoRangeTime.start
                                         error:&error];
                //第二个音频轨道
                AVMutableAudioMixInputParameters *secondAudioParam = [AVMutableAudioMixInputParameters audioMixInputParametersWithTrack:mixAudioTrack];
                
                [secondAudioParam setVolumeRampFromStartVolume:audioVolume toEndVolume:audioVolume timeRange:CMTimeRangeMake(videoRangeTime.start, CMTimeMake((audioRangeSecond + audioRangeStartSecond - audioStartSecond) * audioRangeTime.duration.timescale, audioRangeTime.duration.timescale))];
                [inputParameterArray addObject:secondAudioParam];
                
                
                //可变音视轨道再添音轨
                AVMutableCompositionTrack *mixAudioTrack1 = [mainComposition_ addMutableTrackWithMediaType:AVMediaTypeAudio preferredTrackID:kCMPersistentTrackID_Invalid];//第二音轨
                float endSecond = audioMixRangeSecond - (audioRangeSecond + audioRangeStartSecond - audioStartSecond);
                
                
                //讲采集到数据加入到音轨
                [mixAudioTrack1 insertTimeRange:CMTimeRangeMake(audioRangeTime.start, CMTimeMake(endSecond * audioRangeTime.duration.timescale, audioRangeTime.duration.timescale))
                                        ofTrack:[audioTrackersMix objectAtIndex:0]
                                         atTime:CMTimeMake((audioMixRangeStartSecond + audioRangeSecond + audioRangeStartSecond - audioStartSecond) * startTime.timescale, startTime.timescale)
                                          error:&error];
                //第二个音频轨道
                AVMutableAudioMixInputParameters *secondAudioParam1 = [AVMutableAudioMixInputParameters audioMixInputParametersWithTrack:mixAudioTrack1];
                
                if (endSecond < 0.5) {
                    [secondAudioParam1 setVolumeRampFromStartVolume:audioVolume toEndVolume:0 timeRange:CMTimeRangeMake(CMTimeMake((audioMixRangeStartSecond + audioRangeSecond + audioRangeStartSecond - audioStartSecond) * startTime.timescale, startTime.timescale), CMTimeMake(endSecond, 1))];
                } else {
                    [secondAudioParam1 setVolumeRampFromStartVolume:audioVolume toEndVolume:audioVolume timeRange:CMTimeRangeMake(CMTimeMake((audioMixRangeStartSecond + audioRangeSecond + audioRangeStartSecond - audioStartSecond ) * startTime.timescale, startTime.timescale), CMTimeMake(endSecond - 0.5, 1))];
                    [secondAudioParam1 setVolumeRampFromStartVolume:audioVolume toEndVolume:0 timeRange:CMTimeRangeMake(CMTimeMake(audioMixRangeStartSecond + audioRangeSecond + audioRangeStartSecond - audioStartSecond + endSecond - 0.5, 1), CMTimeMake(0.5, 1))];
                }
                
                
                [inputParameterArray addObject:secondAudioParam1];
                
            } else {
                
                //可变音视轨道再添音轨
                AVMutableCompositionTrack *mixAudioTrackFirst = [mainComposition_ addMutableTrackWithMediaType:AVMediaTypeAudio preferredTrackID:kCMPersistentTrackID_Invalid];//第二音轨
                
                
                
                //讲采集到数据加入到音轨
                [mixAudioTrackFirst insertTimeRange:CMTimeRangeMake(audioRangeTime.start, CMTimeMake((audioRangeSecond + audioRangeStartSecond - audioStartSecond) * audioRangeTime.duration.timescale, audioRangeTime.duration.timescale))
                                            ofTrack:[audioTrackersMix objectAtIndex:0]
                                             atTime:videoRangeTime.start
                                              error:&error];
                //第二个音频轨道
                AVMutableAudioMixInputParameters *secondAudioParamFirst = [AVMutableAudioMixInputParameters audioMixInputParametersWithTrack:mixAudioTrackFirst];
                [secondAudioParamFirst setVolumeRampFromStartVolume:audioVolume toEndVolume:audioVolume timeRange:CMTimeRangeMake(videoRangeTime.start, CMTimeMake((audioRangeSecond + audioRangeStartSecond - audioStartSecond) * audioRangeTime.duration.timescale, audioRangeTime.duration.timescale))];
                [inputParameterArray addObject:secondAudioParamFirst];
                
                for (int i = 0; i < cycleIndex; i++) {
                    //可变音视轨道再添音轨
                    AVMutableCompositionTrack *mixAudioTrack = [mainComposition_ addMutableTrackWithMediaType:AVMediaTypeAudio preferredTrackID:kCMPersistentTrackID_Invalid];//第二音轨
                    
                    //讲采集到数据加入到音轨
                    [mixAudioTrack insertTimeRange:audioRangeTime
                                           ofTrack:[audioTrackersMix objectAtIndex:0]
                                            atTime:CMTimeMake((audioMixRangeStartSecond + audioRangeSecond + audioRangeStartSecond - audioStartSecond + audioRangeSecond * i) * startTime.timescale, startTime.timescale)
                                             error:&error];
                    //第二个音频轨道
                    AVMutableAudioMixInputParameters *secondAudioParam = [AVMutableAudioMixInputParameters audioMixInputParametersWithTrack:mixAudioTrack];
                    [secondAudioParam setVolumeRampFromStartVolume:audioVolume toEndVolume:audioVolume timeRange:CMTimeRangeMake(CMTimeMake((audioMixRangeStartSecond + audioRangeSecond + audioRangeStartSecond - audioStartSecond + audioRangeSecond * i) * startTime.timescale, startTime.timescale), audioRangeTime.duration)];
                    [inputParameterArray addObject:secondAudioParam];
                    
                }
                //可变音视轨道再添音轨
                AVMutableCompositionTrack *mixAudioTrack = [mainComposition_ addMutableTrackWithMediaType:AVMediaTypeAudio preferredTrackID:kCMPersistentTrackID_Invalid];//最后音轨
                float endSecond = audioMixRangeSecond - (audioRangeSecond + audioRangeStartSecond - audioStartSecond) - audioRangeSecond * cycleIndex;
                
                
                //讲采集到数据加入到音轨
                [mixAudioTrack insertTimeRange:CMTimeRangeMake(audioRangeTime.start, CMTimeMake(endSecond * audioRangeTime.duration.timescale, audioRangeTime.duration.timescale))
                                       ofTrack:[audioTrackersMix objectAtIndex:0]
                                        atTime:CMTimeMake((audioMixRangeStartSecond + audioRangeSecond + audioRangeStartSecond - audioStartSecond + audioRangeSecond * cycleIndex) * startTime.timescale, startTime.timescale)
                                         error:&error];
                //第二个音频轨道
                AVMutableAudioMixInputParameters *secondAudioParam = [AVMutableAudioMixInputParameters audioMixInputParametersWithTrack:mixAudioTrack];
                
                if (endSecond < 0.5) {
                    [secondAudioParam setVolumeRampFromStartVolume:audioVolume toEndVolume:0 timeRange:CMTimeRangeMake(CMTimeMake((audioMixRangeStartSecond + audioRangeSecond + audioRangeStartSecond - audioStartSecond + audioRangeSecond * cycleIndex) * startTime.timescale, startTime.timescale), CMTimeMake(endSecond, 1))];
                } else {
                    [secondAudioParam setVolumeRampFromStartVolume:audioVolume toEndVolume:audioVolume timeRange:CMTimeRangeMake(CMTimeMake((audioMixRangeStartSecond + audioRangeSecond + audioRangeStartSecond - audioStartSecond + audioRangeSecond * cycleIndex) * startTime.timescale, startTime.timescale), CMTimeMake(endSecond - 0.5, 1))];
                    [secondAudioParam setVolumeRampFromStartVolume:audioVolume toEndVolume:0 timeRange:CMTimeRangeMake(CMTimeMake((audioMixRangeStartSecond + audioRangeSecond + audioRangeStartSecond - audioStartSecond + audioRangeSecond * cycleIndex) * startTime.timescale, startTime.timescale), CMTimeMake(0.5, 1))];
                }

                [inputParameterArray addObject:secondAudioParam];
                
                
            }
            
        } else {
            
            if (audioRangeSecond - (audioStartSecond - audioRangeStartSecond) > audioMixRangeSecond) {
                
                //可变音视轨道再添音轨
                AVMutableCompositionTrack *mixAudioTrack = [mainComposition_ addMutableTrackWithMediaType:AVMediaTypeAudio preferredTrackID:kCMPersistentTrackID_Invalid];//音轨
                //讲采集到数据加入到音轨
                [mixAudioTrack insertTimeRange:CMTimeRangeMake(startTime,CMTimeMake(audioMixRangeSecond * self.AVAsset.duration.timescale, self.AVAsset.duration.timescale))
                                       ofTrack:[audioTrackersMix objectAtIndex:0]
                                        atTime:CMTimeMake(audioMixRangeStartSecond * self.AVAsset.duration.timescale, self.AVAsset.duration.timescale)
                                         error:&error];
                
                
                audioEndSecond = audioMixRangeSecond;
                //第二个音频轨道
                AVMutableAudioMixInputParameters *secondAudioParam = [AVMutableAudioMixInputParameters audioMixInputParametersWithTrack:mixAudioTrack];
                float endSecond = audioMixRangeSecond;
                if (endSecond < 0.5) {
                    [secondAudioParam setVolumeRampFromStartVolume:audioVolume toEndVolume:0 timeRange:CMTimeRangeMake(CMTimeMake(audioMixRangeStartSecond * self.AVAsset.duration.timescale, self.AVAsset.duration.timescale), CMTimeMake(endSecond, 1))];
                } else {
                    [secondAudioParam setVolumeRampFromStartVolume:audioVolume toEndVolume:audioVolume timeRange:CMTimeRangeMake(CMTimeMake(audioMixRangeStartSecond * self.AVAsset.duration.timescale, self.AVAsset.duration.timescale), CMTimeMake(endSecond - 0.5, 1))];
                    [secondAudioParam setVolumeRampFromStartVolume:audioVolume toEndVolume:0 timeRange:CMTimeRangeMake(CMTimeMake((audioMixRangeStartSecond  + endSecond - 0.5) * self.AVAsset.duration.timescale, self.AVAsset.duration.timescale), CMTimeMake(0.5, 1))];
                }
                
                [inputParameterArray addObject:secondAudioParam];
                
            } else {
                //可变音视轨道再添音轨
                AVMutableCompositionTrack *mixAudioTrack = [mainComposition_ addMutableTrackWithMediaType:AVMediaTypeAudio preferredTrackID:kCMPersistentTrackID_Invalid];//音轨
                //讲采集到数据加入到音轨
                [mixAudioTrack insertTimeRange:CMTimeRangeMake(CMTimeMake(audioStartSecond * startTime.timescale, startTime.timescale),CMTimeMake((audioRangeSecond - (audioStartSecond - audioRangeStartSecond)) * startTime.timescale, startTime.timescale))
                                       ofTrack:[audioTrackersMix objectAtIndex:0]
                                        atTime:CMTimeMake(audioMixRangeStartSecond * self.AVAsset.duration.timescale, self.AVAsset.duration.timescale)
                                         error:&error];
                //音频轨道
                AVMutableAudioMixInputParameters *secondAudioParam = [AVMutableAudioMixInputParameters audioMixInputParametersWithTrack:mixAudioTrack];
                [secondAudioParam setVolumeRampFromStartVolume:audioVolume toEndVolume:audioVolume timeRange:CMTimeRangeMake(kCMTimeZero, CMTimeMake((audioRangeSecond - (audioStartSecond - audioRangeStartSecond)) * startTime.timescale, startTime.timescale))];
                [inputParameterArray addObject:secondAudioParam];
                
                //可变音视轨道再添音轨
                AVMutableCompositionTrack *mixAudioTrackEnd = [mainComposition_ addMutableTrackWithMediaType:AVMediaTypeAudio preferredTrackID:kCMPersistentTrackID_Invalid];//音轨
                float endSecond = audioMixRangeSecond - (audioRangeSecond + audioRangeStartSecond - audioStartSecond);
                audioEndSecond = endSecond;
                //讲采集到数据加入到音轨
                [mixAudioTrackEnd insertTimeRange:CMTimeRangeMake(audioRangeTime.start,CMTimeMake(endSecond * startTime.timescale, startTime.timescale))
                                          ofTrack:[audioTrackersMix objectAtIndex:0]
                                           atTime:CMTimeMake((audioMixRangeStartSecond + audioRangeSecond + audioRangeStartSecond - audioStartSecond) * startTime.timescale, startTime.timescale)
                                            error:&error];
                //音频轨道
                AVMutableAudioMixInputParameters *secondAudioParamEnd = [AVMutableAudioMixInputParameters audioMixInputParametersWithTrack:mixAudioTrackEnd];
                
                if (endSecond < 0.5) {
                    [secondAudioParam setVolumeRampFromStartVolume:audioVolume toEndVolume:0 timeRange:CMTimeRangeMake(CMTimeMake((audioMixRangeStartSecond + audioRangeSecond + audioRangeStartSecond - audioStartSecond) * startTime.timescale, startTime.timescale), CMTimeMake(endSecond, 1))];
                } else {
                    [secondAudioParam setVolumeRampFromStartVolume:audioVolume toEndVolume:audioVolume timeRange:CMTimeRangeMake(CMTimeMake((audioMixRangeStartSecond + audioRangeSecond + audioRangeStartSecond - audioStartSecond) * startTime.timescale, startTime.timescale), CMTimeMake(endSecond - 0.5, 1))];
                    [secondAudioParam setVolumeRampFromStartVolume:audioVolume toEndVolume:0 timeRange:CMTimeRangeMake(CMTimeMake((audioMixRangeStartSecond + audioRangeSecond + audioRangeStartSecond - audioStartSecond) * startTime.timescale, startTime.timescale), CMTimeMake(0.5, 1))];
                }
                [inputParameterArray addObject:secondAudioParamEnd];
            }
            
        }

        videoAudioMixTools_.inputParameters = inputParameterArray;

        
        //视频操作指令集合
        selectVideoComposition_ = [AVMutableVideoComposition videoCompositionWithPropertiesOfAsset:mainComposition_];
        AVMutableVideoComposition *firstVcn = [AVMutableVideoComposition videoCompositionWithPropertiesOfAsset:AVAsset_];
        selectVideoComposition_.renderSize = firstVcn.renderSize;
        self.AVAsset = mainComposition_;
        return YES;
        
    }
    
    
}
- (BOOL)YXmixAudioAssetAtURL:(NSURL *)audioAssetURL
               videoVolume:(float)videoVolume
               audioVolume:(float)audioVolume
            audioStartTime:(CMTime)startTime
            audioRangeTime:(CMTimeRange)audioRangeTime
            vidioRangeTime:(CMTimeRange)videoRangeTime
              slowVolumeTime:(CMTime)slowVolumeTime{
    if (!audioAssetURL) {
        mainComposition_ = nil;
        videoAudioMixTools_ = nil;
        selectVideoComposition_ = nil;
        return YES;
        
    } else {
        
        if (videoVolume < 0
            || videoVolume > 1
            || audioVolume < 0
            || videoVolume > 1
            || startTime.value < 0
            || audioRangeTime.duration.value < 1) {
            //            OIErrorLog(YES, [self.class class], @"mixAudio", @"参数传入有误", @"请检查参数范围的问题");
            return NO;
        }
        //创建一个音视频组合轨道
        mainComposition_ = [[AVMutableComposition alloc] init];
        
        //可变音视频轨道添加一个 视频通道
        AVMutableCompositionTrack *compositionVideoTrack = [mainComposition_ addMutableTrackWithMediaType:AVMediaTypeVideo preferredTrackID:kCMPersistentTrackID_Invalid];
        
        //可变音视频轨道添加一个 音频通道
        AVMutableCompositionTrack *compositionAudioTrack = [mainComposition_ addMutableTrackWithMediaType:AVMediaTypeAudio preferredTrackID:kCMPersistentTrackID_Invalid];
        
        //视频通道数组
        NSArray<AVAssetTrack *> *videoTrackers = [AVAsset_ tracksWithMediaType:AVMediaTypeVideo];
        if (0 >= videoTrackers.count) {
            NSLog(@"数据获取失败");
            return NO;
        }
        
        //获取第一个视频通道
        AVAssetTrack *videoTrack = [videoTrackers objectAtIndex:0];
        
        //视频时间
        float videoTimes = CMTimeGetSeconds(self.AVAsset.duration);
        
        compositionVideoTrack.preferredTransform = videoTrack.preferredTransform;
        NSError *error = nil;
        
        //把采集轨道数据加入到可变轨道之中
        [compositionVideoTrack insertTimeRange:CMTimeRangeMake(kCMTimeZero, AVAsset_.duration)
                                       ofTrack:videoTrack
                                        atTime:kCMTimeZero
                                         error:&error];
        if (error) {
            //            OIErrorLog(YES, nil, nil, [NSString stringWithFormat:@"视轨错误:%@",error], nil);
            NSLog(@"视轨出错%@",error);
            return NO;
        }
        NSLog(@"%@",AVAsset_);
        //获取音频轨道数组
        NSArray<AVAssetTrack *> *audioTrackers = [AVAsset_ tracksWithMediaType:AVMediaTypeAudio];
        if (0 >= audioTrackers.count) {
            NSLog(@"音频数据获取失败");
        } else {
            //获取第一个音频轨道
            AVAssetTrack *audioTrack = [audioTrackers objectAtIndex:0];
            int audioTimeScale = audioTrack.naturalTimeScale;
            
            
            //获取音频的时间
            CMTime audioDuration = CMTimeMake(videoTimes * audioTimeScale, audioTimeScale);
            
            //讲音频轨道加入到可变轨道中
            [compositionAudioTrack insertTimeRange:CMTimeRangeMake(kCMTimeZero, audioDuration)
                                           ofTrack:audioTrack
                                            atTime:kCMTimeZero
                                             error:&error];
            if (error) {
                //                OIErrorLog(YES, nil, nil, [NSString stringWithFormat:@"音轨错误:%@",error], nil);
                NSLog(@"音轨错误:%@",error);
                return NO;
            }
        }
        
        //增加音轨
        //采集资源
        AVURLAsset *mixAsset = [[AVURLAsset alloc]initWithURL:audioAssetURL options:nil];
        NSArray<AVAssetTrack *> *audioTrackersMix = [mixAsset tracksWithMediaType:AVMediaTypeAudio];
        if (0 >= audioTrackersMix.count) {
            NSLog(@"获取第二音轨数据失败");
            return NO;
        }
        
        videoAudioMixTools_ = [AVMutableAudioMix audioMix];
        NSMutableArray <AVAudioMixInputParameters *> * inputParameterArray = [NSMutableArray array];
        
        if (!isClip_) {
            clipTimeRange_ = CMTimeRangeMake(kCMTimeZero, self.AVAsset.duration);
        }
        
        //混音第一次开始时间
        float audioStartSecond = CMTimeGetSeconds(startTime);
        
        //混音音频开始时间
        float audioRangeStartSecond = CMTimeGetSeconds(audioRangeTime.start);
        
        //混音音频的总时间
        float audioRangeSecond = CMTimeGetSeconds(audioRangeTime.duration);
        
        //混音的总时间
        float audioMixRangeSecond = CMTimeGetSeconds(videoRangeTime.duration);
        
        //混音最后一轨道的时间
        float audioEndSecond;
        //混音开始时间
        float videoRangeStartTime = CMTimeGetSeconds(videoRangeTime.start);
        float clipRangeStartTime = CMTimeGetSeconds(clipTimeRange_.start);
        float audioMixRangeStartSecond = CMTimeGetSeconds(videoRangeTime.start);
        float clipTimeRangeDuration = CMTimeGetSeconds(clipTimeRange_.duration);
        
        //减音时间
        float slowVolumeSecond = CMTimeGetSeconds(slowVolumeTime);
        
        if (videoRangeStartTime > clipRangeStartTime) {
            
            
            if ((clipRangeStartTime + clipTimeRangeDuration) > (audioMixRangeSecond + audioMixRangeStartSecond)) {
                audioMixRangeSecond = CMTimeGetSeconds(videoRangeTime.duration);
            } else {
                audioMixRangeSecond = (clipRangeStartTime + clipTimeRangeDuration) - audioMixRangeStartSecond;
            }
            audioMixRangeStartSecond = videoRangeStartTime - clipRangeStartTime;
        } else {
            
            if ((clipRangeStartTime + clipTimeRangeDuration) > (audioMixRangeSecond + audioMixRangeStartSecond)) {
                audioMixRangeSecond = audioMixRangeSecond + audioMixRangeStartSecond - clipRangeStartTime;
            } else {
                audioMixRangeSecond = clipRangeStartTime + clipTimeRangeDuration - clipRangeStartTime;
            }
            audioMixRangeStartSecond = 0;
        }
        
        if (audioMixRangeSecond > videoTimes) {
            audioMixRangeSecond = videoTimes;
        }
        if (audioStartSecond > (audioRangeSecond + audioRangeStartSecond)
            || audioStartSecond < 0
            || audioStartSecond < audioRangeStartSecond
            || audioMixRangeStartSecond < 0
            || audioMixRangeSecond < 0) {
            NSLog(@"开始传入的数据有误");
            return NO;
        }
        
        //获取第一个音频轨道
        AVMutableAudioMixInputParameters *firstAudioParam = [AVMutableAudioMixInputParameters audioMixInputParametersWithTrack:compositionAudioTrack];
        
        //设置第一个音轨音量
        [firstAudioParam setVolumeRampFromStartVolume:videoVolume toEndVolume:videoVolume timeRange:CMTimeRangeMake(kCMTimeZero, AVAsset_.duration)];
        [inputParameterArray addObject:firstAudioParam];
        
        //可变音视轨道再添音轨
        AVMutableCompositionTrack *mixAudioTrack = [mainComposition_ addMutableTrackWithMediaType:AVMediaTypeAudio preferredTrackID:kCMPersistentTrackID_Invalid];//第二音轨
        
        if (audioRangeSecond < audioMixRangeSecond) {
            int cycleIndex = (audioMixRangeSecond - (audioRangeSecond - (audioStartSecond - audioRangeStartSecond))) / audioRangeSecond;
            
            if (cycleIndex < 1) {
                
                //讲采集到数据加入到音轨
                [mixAudioTrack insertTimeRange:CMTimeRangeMake(audioRangeTime.start, CMTimeMake((audioRangeSecond + audioRangeStartSecond - audioStartSecond) * audioRangeTime.duration.timescale, audioRangeTime.duration.timescale))
                                       ofTrack:[audioTrackersMix objectAtIndex:0]
                                        atTime:videoRangeTime.start
                                         error:&error];
                float endSecond = audioMixRangeSecond - (audioRangeSecond + audioRangeStartSecond - audioStartSecond);
                
                
                //讲采集到数据加入到音轨
                [mixAudioTrack insertTimeRange:CMTimeRangeMake(audioRangeTime.start, CMTimeMake(endSecond * audioRangeTime.duration.timescale, audioRangeTime.duration.timescale))
                                        ofTrack:[audioTrackersMix objectAtIndex:0]
                                         atTime:CMTimeMake((audioMixRangeStartSecond + audioRangeSecond + audioRangeStartSecond - audioStartSecond) * startTime.timescale, startTime.timescale)
                                          error:&error];
                
                
                
            } else {
                //讲采集到数据加入到音轨
                [mixAudioTrack insertTimeRange:CMTimeRangeMake(audioRangeTime.start, CMTimeMake((audioRangeSecond + audioRangeStartSecond - audioStartSecond) * audioRangeTime.duration.timescale, audioRangeTime.duration.timescale))
                                            ofTrack:[audioTrackersMix objectAtIndex:0]
                                             atTime:videoRangeTime.start
                                              error:&error];
                
                for (int i = 0; i < cycleIndex; i++) {
                    
                    //讲采集到数据加入到音轨
                    [mixAudioTrack insertTimeRange:audioRangeTime
                                           ofTrack:[audioTrackersMix objectAtIndex:0]
                                            atTime:CMTimeMake((audioMixRangeStartSecond + audioRangeSecond + audioRangeStartSecond - audioStartSecond + audioRangeSecond * i) * startTime.timescale, startTime.timescale)
                                             error:&error];
                    
                }

                float endSecond = audioMixRangeSecond - (audioRangeSecond + audioRangeStartSecond - audioStartSecond) - audioRangeSecond * cycleIndex;
                
                
                //讲采集到数据加入到音轨
                [mixAudioTrack insertTimeRange:CMTimeRangeMake(audioRangeTime.start, CMTimeMake(endSecond * audioRangeTime.duration.timescale, audioRangeTime.duration.timescale))
                                       ofTrack:[audioTrackersMix objectAtIndex:0]
                                        atTime:CMTimeMake((audioMixRangeStartSecond + audioRangeSecond + audioRangeStartSecond - audioStartSecond + audioRangeSecond * cycleIndex) * startTime.timescale, startTime.timescale)
                                         error:&error];
                
            }
            
        } else {
            
            if (audioRangeSecond - (audioStartSecond - audioRangeStartSecond) > audioMixRangeSecond) {
                //讲采集到数据加入到音轨
                [mixAudioTrack insertTimeRange:CMTimeRangeMake(startTime,CMTimeMake(audioMixRangeSecond * self.AVAsset.duration.timescale, self.AVAsset.duration.timescale))
                                       ofTrack:[audioTrackersMix objectAtIndex:0]
                                        atTime:CMTimeMake(audioMixRangeStartSecond * self.AVAsset.duration.timescale, self.AVAsset.duration.timescale)
                                         error:&error];
                
                
                audioEndSecond = audioMixRangeSecond;
                float endSecond = audioMixRangeSecond;


                
            } else {
                //讲采集到数据加入到音轨
                [mixAudioTrack insertTimeRange:CMTimeRangeMake(CMTimeMake(audioStartSecond * startTime.timescale, startTime.timescale),CMTimeMake((audioRangeSecond - (audioStartSecond - audioRangeStartSecond)) * startTime.timescale, startTime.timescale))
                                       ofTrack:[audioTrackersMix objectAtIndex:0]
                                        atTime:CMTimeMake(audioMixRangeStartSecond * self.AVAsset.duration.timescale, self.AVAsset.duration.timescale)
                                         error:&error];
                float endSecond = audioMixRangeSecond - (audioRangeSecond + audioRangeStartSecond - audioStartSecond);
                audioEndSecond = endSecond;
                //讲采集到数据加入到音轨
                [mixAudioTrack insertTimeRange:CMTimeRangeMake(audioRangeTime.start,CMTimeMake(endSecond * startTime.timescale, startTime.timescale))
                                          ofTrack:[audioTrackersMix objectAtIndex:0]
                                           atTime:CMTimeMake((audioMixRangeStartSecond + audioRangeSecond + audioRangeStartSecond - audioStartSecond) * startTime.timescale, startTime.timescale)
                                            error:&error];
            }
            
        }
        
        AVMutableAudioMixInputParameters *audioMixInputParameters = [AVMutableAudioMixInputParameters audioMixInputParametersWithTrack:mixAudioTrack];
        [audioMixInputParameters setVolumeRampFromStartVolume:audioVolume toEndVolume:audioVolume timeRange:CMTimeRangeMake(videoRangeTime.start, CMTimeMake((CMTimeGetSeconds(videoRangeTime.duration) - slowVolumeSecond) * videoRangeTime.duration.timescale , videoRangeTime.duration.timescale))];
        [audioMixInputParameters setVolumeRampFromStartVolume:audioVolume toEndVolume:0 timeRange:CMTimeRangeMake(CMTimeMake((CMTimeGetSeconds(videoRangeTime.duration) - slowVolumeSecond) * videoRangeTime.duration.timescale , videoRangeTime.duration.timescale), slowVolumeTime)];
        
        [inputParameterArray addObject:audioMixInputParameters];
        
        videoAudioMixTools_.inputParameters = inputParameterArray;
        
        
        //视频操作指令集合
        selectVideoComposition_ = [AVMutableVideoComposition videoCompositionWithPropertiesOfAsset:mainComposition_];
//        selectVideoComposition_ = [AVMutableVideoComposition videoComposition];
//        AVMutableVideoCompositionInstruction *videoInstruction = [AVMutableVideoCompositionInstruction videoCompositionInstruction];
//        AVMutableVideoCompositionLayerInstruction *videoLayerIntruction = [AVMutableVideoCompositionLayerInstruction videoCompositionLayerInstructionWithAssetTrack:videoTrack];
//        videoInstruction.layerInstructions = @[videoLayerIntruction];
//        [videoLayerIntruction setOpacityRampFromStartOpacity:1.0 toEndOpacity:0 timeRange:CMTimeRangeMake(CMTimeMake(1200, 600), CMTimeMakeWithSeconds(2, 600))];
//        selectVideoComposition_.instructions = @[videoInstruction];
//
//
        AVMutableVideoComposition *firstVcn = [AVMutableVideoComposition videoCompositionWithPropertiesOfAsset:AVAsset_];
        selectVideoComposition_.frameDuration = firstVcn.frameDuration;
        selectVideoComposition_.renderSize = firstVcn.renderSize;
        
        self.AVAsset = mainComposition_;
        
        
        
        
        return YES;
        
    }
}

#pragma  mark -倒放

- (void)upendVideo{
    
    reverseBlockSize_ = 1;
    dispatch_semaphore_t synSemaphoreLoadValues = dispatch_semaphore_create(0);
    [AVAsset_ loadValuesAsynchronouslyForKeys:[NSArray arrayWithObject:@"tracks"] completionHandler:^{
       dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
           NSError *error = nil;
           AVKeyValueStatus tracksStatus = [AVAsset_ statusOfValueForKey:@"tracks" error:&error];
           if (tracksStatus != AVKeyValueStatusLoaded) {
               //
           }
           dispatch_semaphore_signal(synSemaphoreLoadValues);
           
       });
    }];
    
    double loadTrackBegin = [[NSDate date] timeIntervalSince1970];
    dispatch_semaphore_wait(synSemaphoreLoadValues, DISPATCH_TIME_FOREVER);
    double loadTrackEnd = [[NSDate date] timeIntervalSince1970];
    NSLog(@"load track time consume ................ %.3f",(loadTrackEnd - loadTrackBegin) * 1000);
    
    mainComposition_ = [[AVMutableComposition alloc]init];
    AVMutableCompositionTrack *compositionvVideoTrack = [mainComposition_ addMutableTrackWithMediaType:AVMediaTypeVideo preferredTrackID:kCMPersistentTrackID_Invalid];
    AVMutableCompositionTrack *compositionAudioTrack = [mainComposition_ addMutableTrackWithMediaType:AVMediaTypeAudio preferredTrackID:kCMPersistentTrackID_Invalid];
    
    CMTime videoStartTime = kCMTimeZero;
    
    NSArray <AVAssetTrack *> *videoTrackers = [AVAsset_ tracksWithMediaType:AVMediaTypeVideo];
    if (0 >= videoTrackers.count) {
        NSLog(@"视频资源有错");
        return ;
    }
    AVAssetTrack *videoTrack = [videoTrackers firstObject];
    compositionvVideoTrack.preferredTransform = videoTrack.preferredTransform;
    
    float videoTimes = CMTimeGetSeconds(AVAsset_.duration);
    
    AVMutableVideoComposition *firstVcn = [AVMutableVideoComposition videoCompositionWithPropertiesOfAsset:AVAsset_];
    CMTime forceFrameDuration = firstVcn.frameDuration;
    videoStartTime.timescale = forceFrameDuration.timescale;
    
    NSMutableArray <NSValue *> *framesRangeArray = [NSMutableArray array];
    NSMutableArray <AVAssetTrack *> *frameTrackersArray = [NSMutableArray array];
    
    
    CMTime videoReverseSingleStep = forceFrameDuration;
    videoReverseSingleStep.value *= reverseBlockSize_; // 视频长了之后 AVMutableVideoComposition会造成内存爆炸, 把处理数加大,就不会了
    
    CMTime readTrackFrameStartTime = CMTimeSubtract(AVAsset_.duration, videoReverseSingleStep);
    CMTime readTrackFrameLastTime = AVAsset_.duration;
    NSError *error = nil;
    for (;;) {
        if (readTrackFrameStartTime.value <= 0.0) {
            [framesRangeArray addObject:[NSValue valueWithCMTimeRange:CMTimeRangeMake(kCMTimeZero,readTrackFrameLastTime)]];
            [frameTrackersArray addObject:videoTrack];
            break;
        }
        [framesRangeArray addObject:[NSValue valueWithCMTimeRange:CMTimeRangeMake(readTrackFrameStartTime, videoReverseSingleStep)]];
        [frameTrackersArray addObject:videoTrack];
        
        readTrackFrameLastTime = readTrackFrameStartTime;
        readTrackFrameStartTime = CMTimeSubtract(readTrackFrameStartTime, videoReverseSingleStep);
    }
    [compositionvVideoTrack insertTimeRanges:framesRangeArray ofTracks:frameTrackersArray atTime:videoStartTime error:&error];
    if (error) {
        NSLog(@"error: %@ ",error);
        return ;
    }
    NSArray <AVAssetTrack *> *audioTrackers = [AVAsset_ tracksWithMediaType:AVMediaTypeAudio];
    if ( 0 >= audioTrackers.count) {
        NSLog(@"这是一个无声视频");
    } else {
        [frameTrackersArray removeAllObjects];
        [framesRangeArray removeAllObjects];
        AVAssetTrack *audioTrack = [audioTrackers firstObject];
        int audioTimeScale = audioTrack.naturalTimeScale;
        CMTime audioDuration = CMTimeMake(videoTimes * audioTimeScale , audioTimeScale);
        int singleAudioStep = audioTimeScale / (int)(1024.0f / audioTimeScale * 1000) * 2.0;
        CMTime forceAudioDuration = CMTimeMake(singleAudioStep, audioTimeScale);
        CMTime audioReverseSingleStep = forceAudioDuration;
        CMTime readTrackAudioStartTime = CMTimeSubtract(audioDuration, audioReverseSingleStep);
        CMTime readTrackAudioLastTiem = audioDuration;
        for (; ; ) {
            if (readTrackAudioStartTime.value <= 0.0) {
                [framesRangeArray addObject: [NSValue valueWithCMTimeRange:CMTimeRangeMake(kCMTimeZero, readTrackAudioLastTiem)]];
                [frameTrackersArray addObject:audioTrack];
                break;
            }
            [framesRangeArray addObject:[NSValue valueWithCMTimeRange:CMTimeRangeMake(readTrackAudioStartTime, audioReverseSingleStep)]];
            [frameTrackersArray addObject:audioTrack];
            
            readTrackAudioLastTiem = readTrackAudioStartTime;
            readTrackAudioStartTime = CMTimeSubtract(readTrackAudioStartTime, audioReverseSingleStep);
        }
        [compositionAudioTrack insertTimeRanges:framesRangeArray ofTracks:frameTrackersArray atTime:kCMTimeZero error:&error];
        if (error) {
            NSLog(@"erro:%@",error);
            return;
        }
    }
    [framesRangeArray removeAllObjects];
    [frameTrackersArray removeAllObjects];
    
    selectVideoComposition_ = [AVMutableVideoComposition videoCompositionWithPropertiesOfAsset:mainComposition_];
    selectVideoComposition_.renderSize = firstVcn.renderSize;
    videoAudioMixTools_ = [AVMutableAudioMix audioMix];
    
}





#pragma mark - 初始化AVassetReader
//初始化AVAssetReader
- (void)initializeAssetReader
{
    if (mainComposition_ && selectVideoComposition_ && videoAudioMixTools_) {
        NSError *error = nil;
        assetReader_ = [[AVAssetReader alloc] initWithAsset:mainComposition_ error:&error];
        
        assetReader_.timeRange = CMTimeRangeMake(kCMTimeZero, CMTimeMake(mainComposition_.duration.value, mainComposition_.duration.timescale));
        
        NSDictionary *outputSettings = @{(id)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_32BGRA)};
        AVAssetReaderVideoCompositionOutput *readerVideoOutput = [AVAssetReaderVideoCompositionOutput assetReaderVideoCompositionOutputWithVideoTracks:[mainComposition_ tracksWithMediaType:AVMediaTypeVideo]
                                                                                                                                         videoSettings:outputSettings];
#if ! TARGET_IPHONE_SIMULATOR
        //在模拟机调试的时候
        if( [AVVideoComposition isKindOfClass:[AVMutableVideoComposition class]] )
            [(AVMutableVideoComposition*)selectVideoComposition_ setRenderScale:1.0];
#endif
        readerVideoOutput.videoComposition = selectVideoComposition_;
        readerVideoOutput.alwaysCopiesSampleData = NO;
        if ([assetReader_ canAddOutput:readerVideoOutput]) {
            [assetReader_ addOutput:readerVideoOutput];
        } else{
            NSLog(@"加入视频输入失败");
        }
        
        NSArray *audioTracks = [mainComposition_ tracksWithMediaType:AVMediaTypeAudio];
        
        BOOL shouldRecordAudioTrack = ([audioTracks count] > 0);
        AVAssetReaderAudioMixOutput *readerAudioOutput = nil;
        
        if (shouldRecordAudioTrack)
        {
            readerAudioOutput = [AVAssetReaderAudioMixOutput assetReaderAudioMixOutputWithAudioTracks:audioTracks audioSettings:nil];
            readerAudioOutput.audioMix = videoAudioMixTools_;
            readerAudioOutput.alwaysCopiesSampleData = NO;
            if ([assetReader_ canAddOutput:readerAudioOutput]) {
                [assetReader_ addOutput:readerAudioOutput];
            } else{
                NSLog(@"加入音频失败");
            }
        }
        
        videoTrackOutput_ = (AVAssetReaderTrackOutput *)readerVideoOutput;
        audioTrackOutput_ = (AVAssetReaderTrackOutput *)readerAudioOutput;

    }
    else {

        NSError *error;
        AVAssetReader *assetReader = [[AVAssetReader alloc] initWithAsset:self.AVAsset error:&error];
        if (error) {
            return;
        }
        NSMutableDictionary *outputSettings = [NSMutableDictionary dictionary];
        [outputSettings setObject: [NSNumber numberWithInt:kCVPixelFormatType_32BGRA]  forKey: (NSString*)kCVPixelBufferPixelFormatTypeKey];
        // Maybe set alwaysCopiesSampleData to NO on iOS 5.0 for faster video decoding
        videoTrackOutput_ = [[AVAssetReaderTrackOutput alloc] initWithTrack:[[self.AVAsset tracksWithMediaType:AVMediaTypeVideo] objectAtIndex:0] outputSettings:outputSettings];
        videoTrackOutput_.alwaysCopiesSampleData = NO;
        if (![assetReader canAddOutput:videoTrackOutput_]) {
            assetReader = nil;
            videoTrackOutput_ = nil;
            
            NSLog(@"SLVideoTool messege: videoTrackOutput can not be added.");
            
            return;
        } else {
            [assetReader addOutput:videoTrackOutput_];
        }
        
        NSArray *audioTracks = [self.AVAsset tracksWithMediaType:AVMediaTypeAudio];
        
        if (audioTracks.count > 0)
        {
            // This might need to be extended to handle movies with more than one audio track
            AVAssetTrack* audioTrack = [audioTracks objectAtIndex:0];
            NSMutableDictionary *audioSettings = [NSMutableDictionary dictionary];
            [audioSettings setObject: [NSNumber numberWithInt:kAudioFormatLinearPCM]  forKey: (NSString*)AVFormatIDKey];
            audioTrackOutput_ = [[AVAssetReaderTrackOutput alloc] initWithTrack:audioTrack outputSettings:audioSettings];
            audioTrackOutput_.alwaysCopiesSampleData = NO;
            if ([assetReader canAddOutput:audioTrackOutput_]) {
                [assetReader addOutput:audioTrackOutput_];
            }
            else {
                audioTrackOutput_ = nil;
                NSLog(@"SLVideoTool , messege: audioTrackOutput can not be added.");
            }
        }
        assetReader_ = assetReader;
    }
    
}


#pragma  mark - 配置AVassetWriter

- (void)configurationAssetReaderWithOutPutURL:(NSURL*)outPutURL{
    
    NSError *error;
    AVAssetWriter *assetWriter = [AVAssetWriter assetWriterWithURL:outPutURL fileType:AVFileTypeQuickTimeMovie error:&error];
    if (error) {
        NSLog(@"初始化AVAssetWriter Erro:%@",error);
        return ;
    }
    
    //音频编码
    NSDictionary *audioInputSetting = [self configAudioInput];
    AVAssetWriterInput *audioTrackInput = [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeAudio outputSettings:audioInputSetting];
    //视频编码
    NSDictionary *videoInputSetting = [self configVideoInput];
    AVAssetWriterInput *videoTrackInput = [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeVideo outputSettings:videoInputSetting];
    videoTrackInput.expectsMediaDataInRealTime = YES;
    
    if ([assetWriter canAddInput:audioTrackInput]) {
        [assetWriter addInput:audioTrackInput];
    } else {
        NSLog(@"配置音频输出出错");
        return;
    }
    if ([assetWriter canAddInput:videoTrackInput]) {
        [assetWriter addInput:videoTrackInput];
    } else {
        NSLog(@"配置视频输出出错");
        return;
    }
    [self writerWithAssetReader:assetReader_
                    assetWriter:assetWriter
          assetWriterAudioInput:audioTrackInput
          assetWriterVideoInput:videoTrackInput];
}

/**
 编码音频
 
 @return 返回编码字典
 */
- (NSDictionary *)configAudioInput{
    AudioChannelLayout channelLayout = {
        .mChannelLayoutTag = kAudioChannelLayoutTag_Stereo,
        .mChannelBitmap = kAudioChannelBit_Left,
        .mNumberChannelDescriptions = 0
    };
    NSData *channelLayoutData = [NSData dataWithBytes:&channelLayout length:offsetof(AudioChannelLayout, mChannelDescriptions)];
    NSDictionary *audioInputSetting = @{
                                        AVFormatIDKey: @(kAudioFormatMPEG4AAC),
                                        AVSampleRateKey: @(44100),
                                        AVNumberOfChannelsKey: @(2),
                                        AVChannelLayoutKey:channelLayoutData
                                        };
    return audioInputSetting;
}

/**
 编码视频
 
 @return 返回编码字典
 */
- (NSDictionary *)configVideoInput{

    //@{AVVideoAverageBitRateKey : [NSNumber numberWithDouble:3.0 * 1024.0 * 1024.0]};

    NSDictionary *videoInputSetting = @{
                                        AVVideoCodecKey:AVVideoCodecH264,
                                        AVVideoWidthKey: @(374),
                                        AVVideoHeightKey: @(666)
                                        };
    return videoInputSetting;
}

/**
 输出工作
 
 @param assetReader assetReader
 @param assetWriter assetWriter
 @param assetWriterAudioInput   写音频输出
 @param assetWriterVideoInput   写视频输出
 */
- (void)writerWithAssetReader:(AVAssetReader *)assetReader
                  assetWriter:(AVAssetWriter *)assetWriter
        assetWriterAudioInput:(AVAssetWriterInput *)assetWriterAudioInput
        assetWriterVideoInput:(AVAssetWriterInput *)assetWriterVideoInput {
    
    dispatch_queue_t rwAudioSerializationQueue = dispatch_queue_create("Audio Queue", DISPATCH_QUEUE_SERIAL);
    dispatch_queue_t rwVideoSerializationQueue = dispatch_queue_create("Video Queue", DISPATCH_QUEUE_SERIAL);
    dispatch_group_t dispatchGroup = dispatch_group_create();

    BOOL isReadingSuccess = [assetReader startReading];
    BOOL isWritingSuccess = [assetWriter startWriting];
    NSLog(@"==>%ld",assetReader.status);
    
    if (!isReadingSuccess || !isWritingSuccess) {
        NSLog(@"写入失败");
        return;
    }
   
    //这里开始时间是可以自己设置的
    [assetWriter startSessionAtSourceTime:kCMTimeZero];

    __weak __typeof(&*self) weakSelf = self;
    

    dispatch_group_enter(dispatchGroup);
    __block BOOL isAudioFirst = YES;
    [assetWriterAudioInput requestMediaDataWhenReadyOnQueue:rwAudioSerializationQueue usingBlock:^{
        
        while ([assetWriterAudioInput isReadyForMoreMediaData]&&assetReader.status == AVAssetReaderStatusReading) {
            CMSampleBufferRef nextSampleBuffer = [audioTrackOutput_ copyNextSampleBuffer];

            [weakSelf.delegate copyAudioSampleBufferRef:nextSampleBuffer];
        
            if (isAudioFirst) {
                isAudioFirst = !isAudioFirst;
                continue;
            }
            if (nextSampleBuffer) {
                [assetWriterAudioInput appendSampleBuffer:nextSampleBuffer];
                CFRelease(nextSampleBuffer);
            } else {
                [assetWriterAudioInput markAsFinished];
                dispatch_group_leave(dispatchGroup);
                break;
            }
            
        }
        
    }];
    
    dispatch_group_enter(dispatchGroup);
    __block BOOL isVideoFirst = YES;
    [assetWriterVideoInput requestMediaDataWhenReadyOnQueue:rwVideoSerializationQueue usingBlock:^{
        NSLog(@"%ld",assetReader.status);
        while ([assetWriterVideoInput isReadyForMoreMediaData]&&assetReader.status == AVAssetReaderStatusReading) {
            
            CMSampleBufferRef nextSampleBuffer = [videoTrackOutput_ copyNextSampleBuffer];
        
        while ([assetWriterVideoInput isReadyForMoreMediaData]&&assetReader.status == AVAssetReaderStatusReading) {
            
            CMSampleBufferRef nextSampleBuffer = [videoTrackOutput_ copyNextSampleBuffer];
            if (isVideoFirst) {
                isVideoFirst = !isVideoFirst;
                continue;
            }
      
            if (reverseCacheBlocks_.count >= reverseBlockSize_) {
                
                //开始倒叙
                NSUInteger cacheBuffersCound = reverseCacheBlocks_.count;
                @autoreleasepool {
                    for (int m = 0; m < reverseCacheBlocks_.count; m++) {
                        OISamplebufferRef *reverseBuffer = [reverseCacheBlocks_ objectAtIndex:cacheBuffersCound - 1 - m];
                        CMTime bufferInputTime;
                        [[reverseCacheFramesCMtimes_ objectAtIndex:m] getValue:&bufferInputTime];
                        if (reverseBuffer.sampleBuffer) {
                            [assetWriterVideoInput appendSampleBuffer:reverseBuffer.sampleBuffer];
                            NSLog(@"%f",CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(reverseBuffer.sampleBuffer)));
                            CFRelease(reverseBuffer.sampleBuffer);
                            
                        }
                    }
                }
                if (!nextSampleBuffer) {
                    [assetWriterVideoInput markAsFinished];
                    dispatch_group_leave(dispatchGroup);
                    break;
                }
                [reverseCacheBlocks_ removeAllObjects];
                [reverseCacheFramesCMtimes_ removeAllObjects];
            }
            
            OISamplebufferRef *reverseBuffer = [[OISamplebufferRef alloc] init];
            reverseBuffer.sampleBuffer = nextSampleBuffer;
            [reverseCacheBlocks_ addObject:reverseBuffer];
            [reverseCacheFramesCMtimes_ addObject:[NSValue valueWithCMTime:CMSampleBufferGetPresentationTimeStamp(nextSampleBuffer)]];
            
        }
    
        }
  
    }];

    dispatch_group_notify(dispatchGroup, dispatch_get_main_queue(), ^{
        [assetWriter finishWritingWithCompletionHandler:^{
            BOOL isFinsh;
            if (assetWriter.status == AVAssetWriterStatusCompleted) {
                isFinsh = YES;
                NSLog(@"加载完毕");
                
            } else {
                isFinsh = NO;
                NSLog(@"加载失败");
            }
            
            if ([weakSelf.delegate respondsToSelector:@selector(synthesisResult:)]) {
                [weakSelf.delegate synthesisResult:isFinsh];
                if ([self.delegate respondsToSelector:@selector(synthesisResult:)]) {
                    [self.delegate synthesisResult:isFinsh];
                }
                
            }
        }];
        
        
    });
}

                  



#pragma  mark - 拼接

- (BOOL)spliceOperationSpliceAssetUrl:(NSURL *)spliceAssetUrl timeRange:(CMTimeRange)timeRange{
    
    AVAsset *selectAsset = self.AVAsset;
    
    if (mainComposition_) {
        
    } else {
        
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
    AVURLAsset *mixAsset = [AVURLAsset assetWithURL:spliceAssetUrl];
    
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
    
    mainComposition_ = mainComposition;
    selectVideoComposition_ = select_videoComposition;
    videoAudioMixTools_ = videoAudioMixTools;
    return YES;
}

- (void)runBackward{

//    AVAsset *selectVideoAsset = nil;
//    CMTimeRange clipRange = CMTimeRangeMake(kCMTimeZero, selectVideoAsset.duration);
    AVMutableComposition *mainComposition = [[AVMutableComposition alloc] init];
    AVMutableCompositionTrack *compositionVideoTrack = [mainComposition addMutableTrackWithMediaType:AVMediaTypeVideo preferredTrackID:kCMPersistentTrackID_Invalid];
    AVMutableCompositionTrack *soundtrackTrack = [mainComposition addMutableTrackWithMediaType:AVMediaTypeAudio preferredTrackID:kCMPersistentTrackID_Invalid];
    
    CMTime VideostartTime = kCMTimeZero;
    
    NSArray<AVAssetTrack *> *videoTrackers = [AVAsset_ tracksWithMediaType:AVMediaTypeVideo];
    if(0 >= videoTrackers.count){
        return ;
    }
    AVAssetTrack *video_track = [videoTrackers objectAtIndex:0];
    
    float video_times = CMTimeGetSeconds(AVAsset_.duration);
    NSError *error = nil;
    
    AVMutableVideoComposition *first_vcn = [AVMutableVideoComposition videoCompositionWithPropertiesOfAsset:AVAsset_];
    
    CMTime forceFrameDuration = first_vcn.frameDuration;
    VideostartTime.timescale = forceFrameDuration.timescale;
    CMTime readTrackFrameStartTime = CMTimeAdd(kCMTimeZero, CMTimeSubtract(AVAsset_.duration, forceFrameDuration));
    
    NSMutableArray<NSValue *> *framesRangeArray = [[NSMutableArray alloc] init];
    NSMutableArray<AVAssetTrack *> *framesTrackersArray = [[NSMutableArray alloc] init];
    
    compositionVideoTrack.preferredTransform = video_track.preferredTransform;
    
    //            [compositionVideoTrack insertTimeRange:clipRange ofTrack:video_track atTime:kCMTimeZero error:&error];
    
    for(; ;){
        
        [framesRangeArray addObject:[NSValue valueWithCMTimeRange:CMTimeRangeMake(readTrackFrameStartTime, forceFrameDuration)]];
        [framesTrackersArray addObject:video_track];
        
        if(forceFrameDuration.value >= readTrackFrameStartTime.value){
            
            CMTime offsetTime = readTrackFrameStartTime;
            
            [framesRangeArray addObject:[NSValue valueWithCMTimeRange:CMTimeRangeMake(kCMTimeZero, offsetTime)]];
            [framesTrackersArray addObject:video_track];
            break;
        }
        
        readTrackFrameStartTime = CMTimeSubtract(readTrackFrameStartTime, forceFrameDuration);
    }
    
    [compositionVideoTrack insertTimeRanges:framesRangeArray ofTracks:framesTrackersArray atTime:VideostartTime error:&error];
    
    if(error){
        NSLog(@"error:%@", error);
        return ;
    }
    NSArray<AVAssetTrack *> *soundTrackers = [AVAsset_ tracksWithMediaType:AVMediaTypeAudio];
    if(0 >= soundTrackers.count){
        return ;
    }
    
    AVAssetTrack *audio_track = [soundTrackers objectAtIndex:0];
    int audio_time_scale = audio_track.naturalTimeScale;
    CMTime audio_duration = CMTimeMake(video_times * audio_time_scale, audio_time_scale);
    float audio_scale_start_time = CMTimeGetSeconds(kCMTimeZero);
    
    CMTime audio_start_time = CMTimeMake(audio_scale_start_time, audio_time_scale);
    
    //            float single_audio_step = (float)audio_time_scale / 2.0;
    int single_audio_step = audio_time_scale / (int)(1024.0f / audio_time_scale * 1000) * 2.0;
    
    CMTime forceAudioDuration = CMTimeMake(single_audio_step, audio_time_scale);
    CMTime readTrackAudioStartTime = CMTimeAdd(audio_start_time, CMTimeSubtract(audio_duration, forceAudioDuration));
    
    [framesRangeArray removeAllObjects];
    [framesTrackersArray removeAllObjects];
    for(; ;){
        
        [framesRangeArray addObject:[NSValue valueWithCMTimeRange:CMTimeRangeMake(readTrackAudioStartTime, forceAudioDuration)]];
        [framesTrackersArray addObject:audio_track];
        
        if(single_audio_step >= readTrackAudioStartTime.value){
            
            CMTime offsetTime = readTrackAudioStartTime;
            
            [framesRangeArray addObject:[NSValue valueWithCMTimeRange:CMTimeRangeMake(kCMTimeZero, offsetTime)]];
            [framesTrackersArray addObject:audio_track];
            break;
        }
        
        readTrackAudioStartTime = CMTimeSubtract(readTrackAudioStartTime, forceAudioDuration);
    }
    
    [soundtrackTrack insertTimeRanges:framesRangeArray ofTracks:framesTrackersArray atTime:kCMTimeZero error:&error];
    [framesRangeArray removeAllObjects];
    [framesTrackersArray removeAllObjects];
    
    //            [soundtrackTrack insertTimeRange:CMTimeRangeMake(audio_start_time, audio_duration)
    //                                     ofTrack:audio_track atTime:VideostartTime error:&error];
    if(error){
        NSLog(@"error:%@", error);
        return ;
    }
    
    AVMutableVideoComposition *select_videoComposition = [AVMutableVideoComposition videoCompositionWithPropertiesOfAsset:mainComposition];
    
    //            NSArray<AVMutableVideoCompositionInstruction *> *videocomIns = select_videoComposition.instructions;
    //
    //            CGAffineTransform original_t = video_track.preferredTransform;
    //            original_t = CGAffineTransformScale(original_t, 1080.0f / 1920.0f, 1080.0f / 1920.0f);
    ////            CGSize o_size = mainComposition.naturalSize;
    ////            CGSize dd_size = CGSizeApplyAffineTransform(o_size, original_t);
    //
    //            for(AVMutableVideoCompositionInstruction *t_video_com_ins in videocomIns){
    //                AVMutableVideoCompositionLayerInstruction *t_layer_ins = [self copyAndResetVideoLayerInstruction:[t_video_com_ins.layerInstructions objectAtIndex:0] withStartTransform:original_t endTransform:original_t timeRange:t_video_com_ins.timeRange desiredEasy:NO];
    //                t_video_com_ins.layerInstructions = @[t_layer_ins];
    //            }
    select_videoComposition.renderSize = first_vcn.renderSize;
    //            select_videoComposition.instructions = videocomIns;
    
    AVMutableAudioMix *videoAudioMixTools = [AVMutableAudioMix audioMix];
    
    mainComposition_ = mainComposition;
    selectVideoComposition_ = select_videoComposition;
    videoAudioMixTools_ = videoAudioMixTools;

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


- (void)spliceVideoWithArray:(NSArray *)arrayAssetFile type:(SLVideoTransitionType)type{
    
    NSMutableArray *arrayAsset = [NSMutableArray array];
    for (NSString *file in arrayAssetFile) {
        AVURLAsset *asset = [AVURLAsset assetWithURL:[NSURL fileURLWithPath:file]];
        [arrayAsset addObject:asset];
    }
    AVMutableComposition *composition = [AVMutableComposition composition];
    AVMutableCompositionTrack *trackVideoA = [composition addMutableTrackWithMediaType:AVMediaTypeVideo preferredTrackID:kCMPersistentTrackID_Invalid];
    AVMutableCompositionTrack *trackVideoB = [composition addMutableTrackWithMediaType:AVMediaTypeVideo preferredTrackID:kCMPersistentTrackID_Invalid];
    NSArray *videoTracks = @[trackVideoA, trackVideoB];
    
    AVMutableCompositionTrack *trackAudioA = [composition addMutableTrackWithMediaType:AVMediaTypeAudio preferredTrackID:kCMPersistentTrackID_Invalid];
    AVMutableCompositionTrack *trackAudioB = [composition addMutableTrackWithMediaType:AVMediaTypeAudio preferredTrackID:kCMPersistentTrackID_Invalid];
    NSArray *audioTracks = @[trackAudioA,trackAudioB];
    
    
    NSMutableArray *videoAssets = (NSMutableArray *)arrayAsset;
    CMTime cursorTime = kCMTimeZero;
    CMTime transitionDuration = CMTimeMakeWithSeconds(2, 600);
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
        
        AVMutableCompositionTrack *currenAudioTrack = audioTracks[trackIndex];
        NSArray <AVAssetTrack *> *arrayAudioTrack = [asset tracksWithMediaType:AVMediaTypeAudio];
        if (arrayTrack.count > 0) {
            AVAssetTrack *assetAudioTrack = [arrayAudioTrack firstObject];
            [currenAudioTrack insertTimeRange:timeRange
                                 ofTrack:assetAudioTrack
                                       atTime:cursorTime
                                        error:nil];
        }
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
    
    //穿件组合 和 层指令
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
            AVCompositionTrack *backgroundTrack = tracks[1 - trackIndex];
            AVMutableVideoCompositionInstruction *instruction = [AVMutableVideoCompositionInstruction videoCompositionInstruction];
            CMTimeRange timeRange = [transitionTimeRnages[i] CMTimeRangeValue];
        
            instruction.timeRange = timeRange;
            AVMutableVideoCompositionLayerInstruction *fromlayerinstruction = [AVMutableVideoCompositionLayerInstruction videoCompositionLayerInstructionWithAssetTrack:foregroundTrack];
            AVMutableVideoCompositionLayerInstruction *tolayerInstruction = [AVMutableVideoCompositionLayerInstruction videoCompositionLayerInstructionWithAssetTrack:backgroundTrack];
            if (type == SLVideoTransitionTypeDissolve) {
                [fromlayerinstruction setOpacityRampFromStartOpacity:1.0
                                                        toEndOpacity:0.0
                                                           timeRange:timeRange];
                
                [tolayerInstruction setOpacityRampFromStartOpacity:0.0
                                                      toEndOpacity:1.0
                                                         timeRange:timeRange];
            } else if (type == SLVideoTransitionTypePush) {
                CGAffineTransform identityTransform = CGAffineTransformIdentity;
                CGFloat videoWidth = CGSizeMake(1080.0f, 1440.0f).width;
                CGAffineTransform fromDestTransform = CGAffineTransformMakeTranslation(-videoWidth, 0.0);
                CGAffineTransform toStartTransform  = CGAffineTransformMakeTranslation(videoWidth, 0.0);
                [fromlayerinstruction setTransformRampFromStartTransform:identityTransform
                                                          toEndTransform:fromDestTransform
                                                               timeRange:timeRange];
                [tolayerInstruction setTransformRampFromStartTransform:toStartTransform
                                                        toEndTransform:identityTransform
                                                             timeRange:timeRange];
            } else if (type == SLVideoTransitionTypeWipe) {
                CGFloat videoWidth  = CGSizeMake(1080.0f, 1440.0f).width;
                CGFloat videoHeight = CGSizeMake(1080.0f, 1440.0f).height;
                
                CGRect startRect = CGRectMake(0.0f, 0.0f, videoWidth, videoHeight);
                CGRect endRect   = CGRectMake(0.0f, videoHeight, videoWidth, videoHeight);
                
                [fromlayerinstruction setCropRectangleRampFromStartCropRectangle:startRect
                                                              toEndCropRectangle:endRect
                                                                       timeRange:timeRange];
                [tolayerInstruction setCropRectangleRampFromStartCropRectangle:endRect
                                                            toEndCropRectangle:startRect
                                                                     timeRange:timeRange];
                
            } else {
                
            }
            
            //音频设置声音的转换
            AVMutableCompositionTrack *foregroundAudioTrack = audioTracks[trackIndex];
            AVMutableAudioMixInputParameters *foregroundAudioMixInputParameters = [AVMutableAudioMixInputParameters audioMixInputParametersWithTrack:foregroundAudioTrack];
            [foregroundAudioMixInputParameters setVolumeRampFromStartVolume:1.0f toEndVolume:0.0f timeRange:timeRange];
            
            AVMutableCompositionTrack *backgroundAudioTrack = audioTracks[1 - trackIndex];
            AVMutableAudioMixInputParameters *backgroundAudioMixInputParameters = [AVMutableAudioMixInputParameters audioMixInputParametersWithTrack:backgroundAudioTrack];
            
            [backgroundAudioMixInputParameters setVolumeRampFromStartVolume:0.0f toEndVolume:1.0f timeRange:timeRange];
            
            instruction.layerInstructions = @[fromlayerinstruction,tolayerInstruction];
            [compositionInstructions addObject:instruction];
        }
    }
    
    
    //配置声音
    
    
    //配置AVvideoComposition
    AVMutableVideoComposition *videoComposition = [AVMutableVideoComposition videoComposition];
    videoComposition.instructions = compositionInstructions;
    videoComposition.renderSize = CGSizeMake(1080.0f, 1440.0f);
    videoComposition.frameDuration = CMTimeMake(1, 30);
    videoComposition.renderScale = 1.0f;
    
    selectVideoComposition_ = videoComposition;
    videoAudioMixTools_ = [AVMutableAudioMix audioMix];
    mainComposition_ = composition;
    
    
}
#pragma mark - 输出
- (void)writerFile:(NSURL *)fileUrl {
    [self initializeAssetReader];
    [self configurationAssetReaderWithOutPutURL:fileUrl];
}
@end
