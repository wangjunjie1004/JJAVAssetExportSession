//
//  JJAVAssetExportSession.h
//  JJAVAssetExportSession
//
//  Created by wjj on 2019/10/30.
//  Copyright © 2019 wjj. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>

typedef NS_ENUM(NSInteger){
    ExportSessionLowQuality,
    ExportSessionMediumQuality,
    ExportSessionHighestQuality,
}ExportSessionQuality;

@interface JJAVAssetExportSession : NSObject

@property (nonatomic, strong, readonly) AVAsset *asset;

@property (nonatomic, assign) ExportSessionQuality quality;

@property (nonatomic, assign) BOOL shouldOptimizeForNetworkUse;

@property (nonatomic, strong) NSString *outputFileType;

@property (nonatomic, strong) NSURL *outputURL;

@property (nonatomic, strong, readonly) NSError *error;

@property (nonatomic, assign, readonly) float progress;

@property (nonatomic, assign, readonly) AVAssetExportSessionStatus status;

+ (id)exportSessionWithAsset:(AVAsset *)asset;

- (id)initWithAsset:(AVAsset *)asset;

- (void)exportAsynchronouslyWithCompletionHandler:(void (^)(void))handler;

- (void)cancelExport;

@end

