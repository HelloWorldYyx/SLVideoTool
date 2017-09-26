//
//  SLVideoTool.h
//  SLVideoSDK
//
//  Created by admin on 27/6/17.
//  Copyright © 2017年 YYX. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>

NS_ASSUME_NONNULL_BEGIN


enum SLVideoStatus_ {
    SLVideoStatusWaiting,
    SLVideoStatusPlaying,
    SLVideoStautsPaused
};

typedef enum SLVideoStatus_ SLVideoStatus;

typedef enum SLVideoOrientation_ {
    SLVideoOrientationUnKnown             ,
    SLVideoOrientationPortrait            ,
    SLVideoOrientationPOrtraitUpsideDown  ,
    SLVideoOrientationLandscapeLeft       ,
    SLvideoOrientationLandscapeRight      ,
} SLVideoOrientation;

typedef enum SLVideoTransitionType{
    SLVideoTransitionTypeDissolve         ,
    SLVideoTransitionTypePush             ,
    SLVideoTransitionTypeWipe             ,
} SLVideoTransitionType;

extern  NSString * _Nonnull const SLVideoMixingAudioParameterAudioAssetURLKey;
extern  NSString * _Nonnull const SLVideoMixingAudioParameterVideoVolumeKey;
extern  NSString * _Nonnull const SLVideoMixingAudioParameterAudioVolumeKey;
extern  NSString * _Nonnull const SLVideoMixingAudioParameterAudioStartTimeKey;
extern  NSString * _Nonnull const SLVideoMixingAudioParameterTimeRangeOfVideoKey;
extern  NSString * _Nonnull const SlVideoMixingAudioParameterTimeRangeOfAudioKey;

@protocol SLVideoToolDelegate <NSObject>

@optional
- (void)synthesisResult:(BOOL)result;
- (void)copyAudioSampleBufferRef:(CMSampleBufferRef)sampleBufferRef;
@end

@interface SLVideoTool : NSObject

- (instancetype)initWithAVAsset:(AVAsset *)asset;
- (instancetype)initWithURL:(NSURL *)URL;

@property (nonatomic, weak) id <SLVideoToolDelegate> delegate;

@property (nonatomic, strong) AVAsset *AVAsset;     //To set the AVAsset which be play by receiver.
@property (nonatomic, strong) NSURL *URL;   //If receiver do not init by (initWithURL:) and this property never be set, return nil. You can set the source video's URL by this, which be play by receiver.

@property (nonatomic, readonly) SLVideoStatus status;

@property (nonatomic, readonly) double duration;   //返回视频的总长度,单位为秒


/**
 @property progress
 @abstract 当前视频输出的帧的时间在争端视频时长中的百分比.
 @return 一个0.0 ~ 1.0之间的数值
 @discussion 如果此前调用过clipWithRange:方法,则此属性的返回值是一剪裁后的视频长度为基础计算的,0.0代表视频还没输出.
 */
@property (nonatomic, assign) double progress;


/**
 @property size
 @abstract 视频帧旋转的方向
 @discussion 不同于AVAssetTrack里读到的naturalSize,此属性的款高数值已经根据视频的方向调整.
 */
@property (nonatomic, assign) CGSize size;

@property (nonatomic, assign) SLVideoOrientation orientation;

@property (nonatomic, strong) AVMutableComposition *mainComposition;
@property (nonatomic, strong) AVMutableAudioMix *videoAudioMixTools;
@property (nonatomic, strong) AVMutableVideoComposition *selectVideoComposition;

@property (nonatomic, strong) AVAssetReader *assetReader;

/**
 剪切视频
 
 @param timeRange 剪切视频时间 类型为CMTimeRange 取值在视频的时间方位之内.
 */
- (void)clipWithTimeRange:(CMTimeRange)timeRange;

/**
 混音
 
 @param parameters 混音携带参数字典 URL => 混音音频资源; VideoVolume 视频音量 取值范围 0 ~ 1; AudioVolume 混音音量 取值范围 0 ~ 1; AudioStartTime 音频开始时间,该值是相对音频时间.而且取得值在音频范围内 类型 CMTime; TimeRangeOfAudio 音频的时间范围,该值是在音频资料上掘取的.不允许超过音频资料的时间范围 类型:CMTimeRange; TimeRangeOfVideo 混音的时间范围,该值在视频资源上获取,不允许超过视频资料的时间范围.
 @return BOOL 类型 返回YES 表示混音成功,返回NO 表示混音失败,并会打印失败LOG
 */
- (BOOL)mixAudioWithParameters:(NSDictionary *)parameters;

/**
 输出
 @param fileUrl 写入的地址
 */
- (void)writerFile:(NSURL *)fileUrl;


- (BOOL)spliceOperationSpliceAssetUrl:(NSURL *)spliceAssetUrl timeRange:(CMTimeRange)timeRange;
- (void)spliceVideoWithArray:(NSArray *)arrayAssetFile type:(SLVideoTransitionType)type;
//倒放
- (void)runBackward;
- (void)upendVideo;
@end
NS_ASSUME_NONNULL_END


