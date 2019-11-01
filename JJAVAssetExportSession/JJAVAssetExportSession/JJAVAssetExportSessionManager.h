//
//  JJAVAssetExportSessionManager.h
//  JJAVAssetExportSession
//
//  Created by wjj on 2019/10/30.
//  Copyright © 2019 wjj. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "JJAVAssetExportSession.h"

NS_ASSUME_NONNULL_BEGIN

typedef void(^VideoExportProgressHandler)(double progress);
typedef void(^VideoExportCompletionHandler)(NSURL * __nullable pathURL, NSString * __nullable videoName, NSError * __nullable error);

@interface JJAVAssetExportSessionManager : NSObject

+ (instancetype)shareManager;

- (void)startExportWithKey:(NSString *)key
                     asset:(AVAsset *)asset
                   quality:(ExportSessionQuality)quality
                  optimize:(BOOL)optimize
            outputFileType:(NSString *)outputFileType
                 outputURL:(NSURL *)outputURL
                  progress:(nullable VideoExportProgressHandler)progress
                completion:(VideoExportCompletionHandler)completion;

- (void)cancelExportVideoWithKey:(NSString *)key;

@end

NS_ASSUME_NONNULL_END
