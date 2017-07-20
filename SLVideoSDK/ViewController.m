//
//  ViewController.m
//  SLVideoSDK
//
//  Created by admin on 27/6/17.
//  Copyright © 2017年 YYX. All rights reserved.
//

#import "ViewController.h"
#import "SLVideoTool.h"
#import <AVFoundation/AVFoundation.h>


@interface ViewController ()<SLVideoToolDelegate>
@property (nonatomic,strong) SLVideoTool *videoTool;
@property (nonatomic,strong) AVAssetReader *assetReader;
@property (nonatomic,strong) AVAsset *AVAsset;
@property (nonatomic,strong) AVAssetReaderTrackOutput *videoTrackOutput;
@property (nonatomic,strong) AVAssetReaderTrackOutput *audioTrackOutput;
@property (nonatomic,strong) AVMutableAudioMix *audioMix;
@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    NSURL *audioInpitUrl2 = [NSURL fileURLWithPath:[[NSBundle mainBundle] pathForResource:@"五环之歌" ofType:@"mp3"]];
    // 视频来源
    NSURL *videoInputUrl = [[NSBundle mainBundle] URLForResource:@"IMG_2283" withExtension:@"MOV"];
    _videoTool = [[SLVideoTool alloc]initWithURL:videoInputUrl];
    BOOL isMix;
    NSMutableDictionary *parametersDic = [NSMutableDictionary dictionary];
    [parametersDic setObject:audioInpitUrl2 forKey:SLVideoMixingAudioParameterAudioAssetURLKey];
    [parametersDic setObject:@"0" forKey:SLVideoMixingAudioParameterVideoVolumeKey];
    [parametersDic setObject:@"1" forKey:SLVideoMixingAudioParameterAudioVolumeKey];
    [parametersDic setValue:[NSValue valueWithCMTime:CMTimeMake(100, 100)] forKey:SLVideoMixingAudioParameterAudioStartTimeKey];
    [parametersDic setValue:[NSValue valueWithCMTimeRange:CMTimeRangeMake(CMTimeMake(100, 100), CMTimeMake(300, 100))] forKey:SlVideoMixingAudioParameterTimeRangeOfAudioKey];
    [parametersDic setValue:[NSValue valueWithCMTimeRange:CMTimeRangeMake(CMTimeMake(0, 100), CMTimeMake(500, 100))] forKey:SLVideoMixingAudioParameterTimeRangeOfVideoKey];
    isMix = [_videoTool mixAudioWithParameters:parametersDic];
    
//    if (isMix) {
//        NSLog(@"混音成功");
//    } else {
//        NSLog(@"混音失败");
//    }
    
    [self adfasd];
    
}





- (void)adfasd{
    AVPlayerItem *item = [AVPlayerItem playerItemWithAsset:_videoTool.mainComposition];
    [item setAudioMix:_videoTool.videoAudioMixTools];
    AVPlayer *tmpPlayer = [AVPlayer playerWithPlayerItem:item];
    AVPlayerLayer *playerLayer = [AVPlayerLayer playerLayerWithPlayer:tmpPlayer];
    playerLayer.frame = self.view.bounds;
    playerLayer.videoGravity = AVLayerVideoGravityResize;
    [self.view.layer addSublayer:playerLayer];
    [tmpPlayer play];
}
- (void)synthesisResult:(BOOL)result{
    if (result) {
        //新的视频文件编码完毕，写入相册。
        NSString *documentPath = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
        NSString *videoFileName = @"TempVideo.mp4";
        NSString *targetPath = [documentPath stringByAppendingPathComponent:videoFileName]; // 重新编码后的视频保存路径。
        NSLog(@"==>%@",targetPath);
        UISaveVideoAtPathToSavedPhotosAlbum(targetPath, self, @selector(video:didFinishSavingWithError:contextInfo:), nil);
    } else {
        NSLog(@"失败");
    }
}
- (void)video:(NSString *)videoPath didFinishSavingWithError:(NSError *)error contextInfo:(void *)contextInfo
{
    UIAlertView *alertView = [[UIAlertView alloc] initWithTitle:@"编码完毕" message:@"已写入系统相册" delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil];
    [alertView show];
}











@end
