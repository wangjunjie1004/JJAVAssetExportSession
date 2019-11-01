//
//  JJAVAssetExportSession.m
//  JJAVAssetExportSession
//
//  Created by wjj on 2019/10/30.
//  Copyright © 2019 wjj. All rights reserved.
//

#import "JJAVAssetExportSession.h"

@interface JJAVAssetExportSession ()

@property (nonatomic, assign, readwrite) float progress;

@property (nonatomic, strong) AVAssetReader *reader;
@property (nonatomic, strong) AVAssetWriter *writer;

@property (nonatomic, strong) AVAssetReaderVideoCompositionOutput *videoOutput;
@property (nonatomic, strong) AVAssetReaderAudioMixOutput *audioOutput;

@property (nonatomic, strong) AVAssetWriterInput *videoInput;
@property (nonatomic, strong) AVAssetWriterInput *audioInput;

@property (nonatomic, strong) dispatch_queue_t inputQueue;
@property (nonatomic, strong) void (^completionHandler)(void);

@property (nonatomic, assign) CMTimeRange timeRange;
@property (nonatomic, strong) NSDictionary *videoSettings;

@end

@implementation JJAVAssetExportSession {
    NSError *_error;
    NSTimeInterval duration;
    CMTime lastSamplePresentationTime;
}

+ (id)exportSessionWithAsset:(AVAsset *)asset {
    return [JJAVAssetExportSession.alloc initWithAsset:asset];
}

- (void)dealloc {
    _error = nil;
    _progress = 0;
    _reader = nil;
    _videoOutput = nil;
    _audioOutput = nil;
    _writer = nil;
    _videoInput = nil;
    _audioInput = nil;
    _inputQueue = nil;
    _completionHandler = nil;
}

- (id)initWithAsset:(AVAsset *)asset {
    self = [super init];
    if (self) {
        _asset = asset;
        _timeRange = CMTimeRangeMake(kCMTimeZero, kCMTimePositiveInfinity);
    }
    
    return self;
}

- (CGSize)sizeWithQuality:(ExportSessionQuality)quality {
    switch (quality) {
        case ExportSessionLowQuality:
            return CGSizeMake(480.0, 480.0);
            
        case ExportSessionMediumQuality:
            return CGSizeMake(960.0, 960.0);
            
        case ExportSessionHighestQuality:
            return CGSizeMake(1920.0, 1920.0);
            
        default:
            return CGSizeMake(960.0, 960.0);
    }
}

- (NSInteger)rateWithQuality:(ExportSessionQuality)quality {
    switch (quality) {
        case ExportSessionLowQuality:
            return 1600 * 1000;
            
        case ExportSessionMediumQuality:
            return 3200 * 1000;
            
        case ExportSessionHighestQuality:
            return 6400 * 1000;
            
        default:
            return 3200 * 1000;
    }
}

- (NSDictionary *)audioSettings {
    return @{AVFormatIDKey: @(kAudioFormatMPEG4AAC),
             AVNumberOfChannelsKey: @1,
             AVSampleRateKey: @44100,
             AVEncoderBitRateKey: @128000
    };
}

- (NSDictionary *)videoSettingsWithTrack:(AVAssetTrack *)track quality:(ExportSessionQuality)quality {
    CGAffineTransform transform = track.preferredTransform;
    CGSize naturalSize;
    if (transform.a == 0) {
        naturalSize = CGSizeMake(track.naturalSize.height, track.naturalSize.width);
    } else {
        naturalSize = CGSizeMake(track.naturalSize.width, track.naturalSize.height);
    }
    
    CGSize maxSize = [self sizeWithQuality:quality];
    CGSize size = [self fitSize:naturalSize toSize:maxSize];
    
    return @{AVVideoCodecKey: AVVideoCodecTypeH264,
             AVVideoWidthKey: @(size.width),
             AVVideoHeightKey: @(size.height),
             AVVideoCompressionPropertiesKey: @{AVVideoAverageBitRateKey: @([self rateWithQuality:quality]),
                                                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel
             }
    };
}

- (CGSize)fitSize:(CGSize)size toSize:(CGSize)toSize {
    if (MAX(size.width, size.height) <= MAX(toSize.width, toSize.height)) {
        return size;
    } else {
        CGFloat scale = MAX(toSize.width, toSize.height) * 1.0 / MAX(size.width, size.height);
        NSInteger width = scale * size.width;
        width = width / 4 * 4;
        NSInteger height = scale * size.height;
        height = height / 4 * 4;
        return CGSizeMake(width, height);
    }
}

- (void)exportAsynchronouslyWithCompletionHandler:(void (^)(void))handler {
    NSParameterAssert(handler != nil);
    
    [self cancelExport];
    self.completionHandler = handler;
    
    if (!self.outputURL) {
        _error = [NSError errorWithDomain:AVFoundationErrorDomain code:AVErrorExportFailed userInfo:@{NSLocalizedDescriptionKey: @"Output URL not set"}];
        handler();
        return;
    } else {
        if ([NSFileManager.defaultManager fileExistsAtPath:self.outputURL.path]) {
            [NSFileManager.defaultManager removeItemAtPath:self.outputURL.path error:nil];
        }
    }
    
    NSError *readerError;
    self.reader = [AVAssetReader.alloc initWithAsset:self.asset error:&readerError];
    if (readerError) {
        _error = readerError;
        handler();
        return;
    }
    
    NSError *writerError;
    self.writer = [AVAssetWriter assetWriterWithURL:self.outputURL fileType:self.outputFileType error:&writerError];
    if (writerError) {
        _error = writerError;
        handler();
        return;
    }
    
    self.reader.timeRange = self.timeRange;
    self.writer.shouldOptimizeForNetworkUse = self.shouldOptimizeForNetworkUse;
    
    if (CMTIME_IS_VALID(self.timeRange.duration) && !CMTIME_IS_POSITIVE_INFINITY(self.timeRange.duration)) {
        duration = CMTimeGetSeconds(self.timeRange.duration);
    } else {
        duration = CMTimeGetSeconds(self.asset.duration);
    }
    
    NSArray *videoTracks = [self.asset tracksWithMediaType:AVMediaTypeVideo];
    if (videoTracks.count > 0) {
        /*
         * video output
         */
        self.videoSettings = [self videoSettingsWithTrack:videoTracks.firstObject quality:self.quality];
        self.videoOutput = [AVAssetReaderVideoCompositionOutput assetReaderVideoCompositionOutputWithVideoTracks:videoTracks videoSettings:nil];
        self.videoOutput.alwaysCopiesSampleData = NO;
        self.videoOutput.videoComposition = [self buildVideoComposition];
        
        if ([self.reader canAddOutput:self.videoOutput]) {
            [self.reader addOutput:self.videoOutput];
        }
        
        /*
         * video input
         */
        self.videoInput = [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeVideo outputSettings:self.videoSettings];
        self.videoInput.expectsMediaDataInRealTime = NO;
        if ([self.writer canAddInput:self.videoInput]) {
            [self.writer addInput:self.videoInput];
        }
    }
    
    NSArray *audioTracks = [self.asset tracksWithMediaType:AVMediaTypeAudio];
    if (audioTracks.count > 0) {
        /*
         * audio output
         */
        self.audioOutput = [AVAssetReaderAudioMixOutput assetReaderAudioMixOutputWithAudioTracks:audioTracks audioSettings:nil];
        self.audioOutput.alwaysCopiesSampleData = NO;
        if ([self.reader canAddOutput:self.audioOutput]) {
            [self.reader addOutput:self.audioOutput];
        }
        
        /*
         * audio input
         */
        self.audioInput = [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeAudio outputSettings:self.audioSettings];
        self.audioInput.expectsMediaDataInRealTime = NO;
        if ([self.writer canAddInput:self.audioInput]) {
            [self.writer addInput:self.audioInput];
        }
    }
    
    [self.writer startWriting];
    [self.reader startReading];
    [self.writer startSessionAtSourceTime:self.timeRange.start];
    
    __block BOOL videoCompleted = NO;
    __block BOOL audioCompleted = NO;
    __weak typeof(self) wself = self;
    self.inputQueue = dispatch_queue_create([[NSString stringWithFormat:@"export.video.queue.%ld",self.hash] UTF8String], DISPATCH_QUEUE_SERIAL);
    if (videoTracks.count > 0) {
        [self.videoInput requestMediaDataWhenReadyOnQueue:self.inputQueue usingBlock:^{
            if (![wself encodeReadySamplesFromOutput:wself.videoOutput toInput:wself.videoInput]) {
                @synchronized(wself) {
                    videoCompleted = YES;
                    if (audioCompleted) {
                        [wself finishExport];
                    }
                }
            }
        }];
    } else {
        videoCompleted = YES;
    }
    
    if (!self.audioOutput) {
        audioCompleted = YES;
    } else {
        [self.audioInput requestMediaDataWhenReadyOnQueue:self.inputQueue usingBlock:^{
            if (![wself encodeReadySamplesFromOutput:wself.audioOutput toInput:wself.audioInput]) {
                @synchronized(wself) {
                    audioCompleted = YES;
                    if (videoCompleted) {
                        [wself finishExport];
                    }
                }
            }
        }];
    }
}

- (BOOL)encodeReadySamplesFromOutput:(AVAssetReaderOutput *)output toInput:(AVAssetWriterInput *)input
{
    while (input.isReadyForMoreMediaData) {
        CMSampleBufferRef sampleBuffer = [output copyNextSampleBuffer];
        if (sampleBuffer) {
            BOOL handled = NO;
            BOOL error = NO;
            
            if (self.reader.status != AVAssetReaderStatusReading || self.writer.status != AVAssetWriterStatusWriting) {
                handled = YES;
                error = YES;
            }
            
            if (!handled && self.videoOutput == output) {
                // update the video progress
                lastSamplePresentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer);
                lastSamplePresentationTime = CMTimeSubtract(lastSamplePresentationTime, self.timeRange.start);
                self.progress = duration == 0 ? 1 : CMTimeGetSeconds(lastSamplePresentationTime) / duration;
            }
            if (!handled && ![input appendSampleBuffer:sampleBuffer]) {
                error = YES;
            }
            CFRelease(sampleBuffer);
            
            if (error) {
                return NO;
            }
        } else {
            [input markAsFinished];
            return NO;
        }
    }
    
    return YES;
}

- (AVMutableVideoComposition *)buildVideoComposition
{
    AVMutableVideoComposition *videoComposition = [AVMutableVideoComposition videoComposition];
    AVAssetTrack *videoTrack = [[self.asset tracksWithMediaType:AVMediaTypeVideo] objectAtIndex:0];
    
    float trackFrameRate = 0;
    if (self.videoSettings) {
        NSDictionary *videoCompressionProperties = [self.videoSettings objectForKey:AVVideoCompressionPropertiesKey];
        if (videoCompressionProperties) {
            NSNumber *frameRate = [videoCompressionProperties objectForKey:AVVideoAverageNonDroppableFrameRateKey];
            if (frameRate) {
                trackFrameRate = frameRate.floatValue;
            }
        }
    } else {
        trackFrameRate = [videoTrack nominalFrameRate];
    }
    
    if (trackFrameRate == 0) {
        trackFrameRate = 30;
    }
    
    videoComposition.frameDuration = CMTimeMake(1, trackFrameRate);
    CGSize targetSize = CGSizeMake([self.videoSettings[AVVideoWidthKey] floatValue], [self.videoSettings[AVVideoHeightKey] floatValue]);
    CGSize naturalSize = [videoTrack naturalSize];
    CGAffineTransform transform = videoTrack.preferredTransform;
    
    CGFloat videoAngleInDegree  = atan2(transform.b, transform.a) * 180 / M_PI;
    if (videoAngleInDegree == 0) {
        transform.tx = 0;
        transform.ty = 0;
    }
    if (videoAngleInDegree == 90) {
        transform.tx = naturalSize.height;
        transform.ty = 0;
        
        CGFloat width = naturalSize.width;
        naturalSize.width = naturalSize.height;
        naturalSize.height = width;
    }
    if (videoAngleInDegree == 180) {
        transform.tx = naturalSize.width;
        transform.ty = naturalSize.height;
    }
    if (videoAngleInDegree == -90) {
        transform.ty = naturalSize.width;
        transform.tx = 0;
        
        CGFloat width = naturalSize.width;
        naturalSize.width = naturalSize.height;
        naturalSize.height = width;
    }
    videoComposition.renderSize = naturalSize;
    
    // center inside
    float ratio;
    float xratio = targetSize.width / naturalSize.width;
    float yratio = targetSize.height / naturalSize.height;
    ratio = MIN(xratio, yratio);
    
    float postWidth = naturalSize.width * ratio;
    float postHeight = naturalSize.height * ratio;
    float transx = (targetSize.width - postWidth) / 2;
    float transy = (targetSize.height - postHeight) / 2;
    
    CGAffineTransform matrix = CGAffineTransformMakeTranslation(transx / xratio, transy / yratio);
    matrix = CGAffineTransformScale(matrix, ratio / xratio, ratio / yratio);
    transform = CGAffineTransformConcat(transform, matrix);
    
    // Make a "pass through video track" video composition.
    AVMutableVideoCompositionInstruction *passThroughInstruction = [AVMutableVideoCompositionInstruction videoCompositionInstruction];
    passThroughInstruction.timeRange = CMTimeRangeMake(kCMTimeZero, self.asset.duration);
    
    AVMutableVideoCompositionLayerInstruction *passThroughLayer = [AVMutableVideoCompositionLayerInstruction videoCompositionLayerInstructionWithAssetTrack:videoTrack];
    
    [passThroughLayer setTransform:transform atTime:kCMTimeZero];
    
    passThroughInstruction.layerInstructions = @[passThroughLayer];
    videoComposition.instructions = @[passThroughInstruction];
    
    return videoComposition;
}

- (void)finishExport {
    if (self.reader.status == AVAssetReaderStatusCancelled || self.writer.status == AVAssetWriterStatusCancelled) {
        return;
    }
    
    if (self.writer.status == AVAssetWriterStatusFailed) {
        [self complete];
    }
    else if (self.reader.status == AVAssetReaderStatusFailed) {
        [self.writer cancelWriting];
        [self complete];
    } else {
        [self.writer finishWritingWithCompletionHandler:^{
            [self complete];
        }];
    }
}

- (void)complete {
    if (self.writer.status == AVAssetWriterStatusFailed || self.writer.status == AVAssetWriterStatusCancelled) {
        [NSFileManager.defaultManager removeItemAtURL:self.outputURL error:nil];
    }
    
    if (self.completionHandler) {
        self.completionHandler();
        self.completionHandler = nil;
    }
}

- (void)cancelExport {
    if (self.inputQueue) {
        dispatch_async(self.inputQueue, ^{
            [self.writer cancelWriting];
            [self.reader cancelReading];
            [self complete];
        });
    }
}

- (AVAssetExportSessionStatus)status {
    switch (self.writer.status) {
        default:
        case AVAssetWriterStatusUnknown:
            return AVAssetExportSessionStatusUnknown;
        case AVAssetWriterStatusWriting:
            return AVAssetExportSessionStatusExporting;
        case AVAssetWriterStatusFailed:
            return AVAssetExportSessionStatusFailed;
        case AVAssetWriterStatusCompleted:
            return AVAssetExportSessionStatusCompleted;
        case AVAssetWriterStatusCancelled:
            return AVAssetExportSessionStatusCancelled;
    }
}

- (NSError *)error {
    if (_error) {
        return _error;
    } else {
        return self.writer.error ? : self.reader.error;
    }
}

@end
