//
//  JJAVAssetExportSessionManager.m
//  JJAVAssetExportSession
//
//  Created by wjj on 2019/10/30.
//  Copyright © 2019 wjj. All rights reserved.
//

#import "JJAVAssetExportSessionManager.h"

#define MaxExportCount 3 //don't modify this code

@interface JJVideoExportModel : NSObject

@property (nonatomic, assign) BOOL isStartRequest;
@property (nonatomic, strong) JJAVAssetExportSession *session;
@property (nonatomic, strong) NSString *key;
@property (nonatomic, strong) AVAsset *asset;
@property (nonatomic, assign) ExportSessionQuality quality;
@property (nonatomic, assign) BOOL optimize;
@property (nonatomic, strong) NSString *outputFileType;
@property (nonatomic, strong) NSURL *outputURL;
@property (nonatomic, copy) VideoExportProgressHandler progressHandler;
@property (nonatomic, copy) VideoExportCompletionHandler completionHandler;

@end

@implementation JJVideoExportModel

- (instancetype)init
{
    self = [super init];
    if (self) {
        _isStartRequest = NO;
    }
    return self;
}

- (void)dealloc
{
    _progressHandler = nil;
    _completionHandler = nil;
    [_session cancelExport];
    _session = nil;
}

@end

@interface JJAVAssetExportSessionManager ()

@property (nonatomic, strong)NSMutableDictionary *videoExportSessionCache;

@end

@implementation JJAVAssetExportSessionManager

+ (instancetype)shareManager {
    static JJAVAssetExportSessionManager *_manager;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _manager = [[JJAVAssetExportSessionManager alloc] init];
    });
    return _manager;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _videoExportSessionCache = [[NSMutableDictionary alloc] init];
    }
    return self;
}

- (void)startExportWithKey:(NSString *)key asset:(AVAsset *)asset quality:(ExportSessionQuality)quality optimize:(BOOL)optimize outputFileType:(NSString *)outputFileType outputURL:(NSURL *)outputURL progress:(VideoExportProgressHandler)progress completion:(VideoExportCompletionHandler)completion
{
    JJVideoExportModel *model = [[JJVideoExportModel alloc] init];
    model.key = key;
    model.asset = asset;
    model.quality = quality;
    model.optimize = optimize;
    model.outputFileType = outputFileType;
    model.outputURL = outputURL;
    model.progressHandler = progress;
    model.completionHandler = completion;
    if ([self.videoExportSessionCache objectForKey:key]) {
        [self.videoExportSessionCache removeObjectForKey:key];
    }
    [self.videoExportSessionCache setObject:model forKey:key];
    if ([self countRequestingVideo] < MaxExportCount) {
        JJVideoExportModel *exportModel = [self findNextVideoRequest];
        if (exportModel) {
            exportModel.isStartRequest = YES;
            [self exportVideoWithKey:[self.videoExportSessionCache allKeysForObject:exportModel].firstObject exportModel:exportModel];
        }
    }
}

- (void)exportVideoWithKey:(NSString *)key exportModel:(JJVideoExportModel *)model {
    JJAVAssetExportSession *session = [[JJAVAssetExportSession alloc] initWithAsset:model.asset];
    session.outputFileType = model.outputFileType;
    session.quality = model.quality;
    session.outputURL = model.outputURL;
    session.shouldOptimizeForNetworkUse = model.optimize;
    model.session = session;
    
    __block NSTimer *timer = [NSTimer timerWithTimeInterval:0.2 repeats:YES block:^(NSTimer * _Nonnull timer) {
        !model.progressHandler?:model.progressHandler(session.progress);
    }];
    [[NSRunLoop mainRunLoop] addTimer:timer forMode:NSRunLoopCommonModes];
    
    __block JJVideoExportModel *_model = model;
    __weak typeof(self)weakSelf = self;
    
    [session exportAsynchronouslyWithCompletionHandler:^{
        switch (session.status) {
            case AVAssetExportSessionStatusCompleted:
            {
                !_model.progressHandler?:_model.progressHandler(1.0);
                _model.completionHandler([NSURL fileURLWithPath:_model.outputURL.path],_model.outputURL.lastPathComponent,nil);
            }
                break;
            case AVAssetExportSessionStatusCancelled:
            {
                _model.completionHandler(nil,nil,[NSError errorWithDomain:@"export cancelled" code:-999 userInfo:nil]);
            }
                break;
            default:
            {
                _model.completionHandler(nil,nil,[NSError errorWithDomain:@"export failed" code:-1 userInfo:nil]);
            }
                break;
        }
        [timer invalidate];
        timer = nil;
        [weakSelf.videoExportSessionCache removeObjectForKey:key];
        JJVideoExportModel *nextModel = [weakSelf findNextVideoRequest];
        if (nextModel) {
            nextModel.isStartRequest = YES;
            [weakSelf exportVideoWithKey:[weakSelf.videoExportSessionCache allKeysForObject:nextModel].firstObject exportModel:nextModel];
        }
    }];
}

- (void)cancelExportVideoWithKey:(NSString *)key {
    JJVideoExportModel *model = [self.videoExportSessionCache objectForKey:key];
    if (model) {
        if (model.session) {
            [model.session cancelExport];
        } else {
            [self.videoExportSessionCache removeObjectForKey:key];
        }
    }
}

- (NSInteger)countRequestingVideo
{
    NSInteger count = 0;
    for (JJVideoExportModel *model in self.videoExportSessionCache.allValues) {
        if (model.isStartRequest) {
            count++;
        }
    }
    return count;
}

- (JJVideoExportModel *)findNextVideoRequest
{
    JJVideoExportModel *model = nil;
    for (JJVideoExportModel *temp in self.videoExportSessionCache.allValues) {
        if (!temp.isStartRequest) {
            model = temp;
            break;
        }
    }
    return model;
}

@end
