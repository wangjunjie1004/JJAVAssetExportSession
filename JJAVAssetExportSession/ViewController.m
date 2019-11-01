//
//  ViewController.m
//  JJAVAssetExportSession
//
//  Created by wjj on 2019/10/30.
//  Copyright © 2019 wjj. All rights reserved.
//

#import "ViewController.h"
#import "JJAVAssetExportSessionManager.h"

@interface ViewController ()

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view.
    NSString *path = [[NSBundle mainBundle] pathForResource:@"IMG_0038" ofType:@"MOV"];
    AVURLAsset *asset = [[AVURLAsset alloc] initWithURL:[NSURL fileURLWithPath:path] options:nil];
    
    //export only one video
//    JJAVAssetExportSession *session = [[JJAVAssetExportSession alloc] initWithAsset:asset];
//    session.quality = ExportSessionHighestQuality;
//    session.outputFileType = AVFileTypeMPEG4;
//    session.outputURL = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:[@"IMG_0038" stringByAppendingPathExtension:@"mp4"]]];
//    [session exportAsynchronouslyWithCompletionHandler:^{
//        //do something
//        switch (session.status) {
//            case AVAssetExportSessionStatusCompleted:
//            {
//                NSLog(@"finished");
//            }
//                break;
//            case AVAssetExportSessionStatusCancelled:
//            {
//                NSLog(@"cancel");
//            }
//                break;
//            default:
//            {
//                NSLog(@"failed");
//            }
//                break;
//        }
//    }];
    
    //export muti video
    for (int i = 0; i < 10; i++) {
        [JJAVAssetExportSessionManager.shareManager startExportWithKey:[NSString stringWithFormat:@"export%d",i] asset:asset quality:ExportSessionMediumQuality optimize:NO outputFileType:AVFileTypeMPEG4 outputURL:[NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:[[NSString stringWithFormat:@"video-%d",i] stringByAppendingPathExtension:@"mp4"]]] progress:nil completion:^(NSURL * _Nullable pathURL, NSString * _Nullable videoName, NSError * _Nullable error) {
            NSLog(@"%@",pathURL);
        }];
    }
}


@end
