//
//  PINRemoteImageDownloadQueue.m
//  PINRemoteImage
//
//  Created by Garrett Moon on 3/1/17.
//  Copyright © 2017 Pinterest. All rights reserved.
//

#import "PINRemoteImageDownloadQueue.h"

#import "PINURLSessionManager.h"
#import "PINRemoteLock.h"

@interface PINRemoteImageDownloadQueue ()
{
    PINRemoteLock *_lock;
    
    NSMutableOrderedSet <NSURLSessionDataTask *> *_highPriorityQueuedOperations;
    NSMutableOrderedSet <NSURLSessionDataTask *> *_defaultPriorityQueuedOperations;
    NSMutableOrderedSet <NSURLSessionDataTask *> *_lowPriorityQueuedOperations;
    NSMutableSet <NSURLSessionTask *> *_runningTasks;
    NSMutableSet <NSNumber *> *_identifiers;
}

@end

@implementation PINRemoteImageDownloadQueue

@synthesize maxNumberOfConcurrentDownloads = _maxNumberOfConcurrentDownloads;

+ (PINRemoteImageDownloadQueue *)queueWithMaxConcurrentDownloads:(NSUInteger)maxNumberOfConcurrentDownloads
{
    return [[PINRemoteImageDownloadQueue alloc] initWithMaxConcurrentDownloads:maxNumberOfConcurrentDownloads];
}

- (PINRemoteImageDownloadQueue *)initWithMaxConcurrentDownloads:(NSUInteger)maxNumberOfConcurrentDownloads
{
    if (self = [super init]) {
        _maxNumberOfConcurrentDownloads = maxNumberOfConcurrentDownloads;
        
        _lock = [[PINRemoteLock alloc] initWithName:@"PINRemoteImageDownloadQueue Lock"];
        _highPriorityQueuedOperations = [[NSMutableOrderedSet alloc] init];
        _defaultPriorityQueuedOperations = [[NSMutableOrderedSet alloc] init];
        _lowPriorityQueuedOperations = [[NSMutableOrderedSet alloc] init];
        _runningTasks = [[NSMutableSet alloc] init];
        _identifiers = [[NSMutableSet alloc] init];
    }
    return self;
}

- (NSUInteger)maxNumberOfConcurrentDownloads
{
    [self lock];
        NSUInteger maxNumberOfConcurrentDownloads = _maxNumberOfConcurrentDownloads;
    [self unlock];
    return maxNumberOfConcurrentDownloads;
}

- (void)setMaxNumberOfConcurrentDownloads:(NSUInteger)maxNumberOfConcurrentDownloads
{
    [self lock];
        _maxNumberOfConcurrentDownloads = maxNumberOfConcurrentDownloads;
    [self unlock];
}

- (NSURLSessionDataTask *)addDownloadWithSessionManager:(PINURLSessionManager *)sessionManager
                                                request:(NSURLRequest *)request
                                               priority:(PINRemoteImageManagerPriority)priority
                                      completionHandler:(PINRemoteImageDownloadCompletion)completionHandler
{
    NSURLSessionDataTask *dataTask = [sessionManager dataTaskWithRequest:request completionHandler:^(NSURLSessionDataTask *dataTask, NSError *error) {
        completionHandler(dataTask.response, error);
        [self lock];
            [_runningTasks removeObject:dataTask];
        [self unlock];
        
        [self scheduleDownloadsIfNeeded];
    }];
    
    [self setQueuePriority:priority forTask:dataTask addIfNecessary:YES];
    
    [self scheduleDownloadsIfNeeded];
    
    return dataTask;
}

- (void)scheduleDownloadsIfNeeded
{
    [self lock];
        if (_runningTasks.count < _maxNumberOfConcurrentDownloads) {
            NSMutableArray <NSURLSessionDataTask *> *queue = nil;
            if (_highPriorityQueuedOperations.count > 0) {
                queue = _highPriorityQueuedOperations;
            } else if (_defaultPriorityQueuedOperations.count > 0) {
                queue = _defaultPriorityQueuedOperations;
            } else if (_lowPriorityQueuedOperations.count > 0) {
                queue = _lowPriorityQueuedOperations;
            }
            
            if (queue) {
                NSURLSessionDataTask *task = [queue firstObject];
                [queue removeObjectAtIndex:0];
                [task resume];
                
                [_runningTasks addObject:task];
                [_identifiers addObject:@(task.taskIdentifier)];
            }
        }
    [self unlock];
}

- (BOOL)removeDownloadTaskFromQueue:(NSURLSessionDataTask *)downloadTask
{
    BOOL containsTask = NO;
    [self lock];
        if ([_highPriorityQueuedOperations containsObject:downloadTask]) {
            containsTask = YES;
            [_highPriorityQueuedOperations removeObject:downloadTask];
        } else if ([_defaultPriorityQueuedOperations containsObject:downloadTask]) {
            containsTask = YES;
            [_defaultPriorityQueuedOperations removeObject:downloadTask];
        } else if ([_lowPriorityQueuedOperations containsObject:downloadTask]) {
            containsTask = YES;
            [_lowPriorityQueuedOperations removeObject:downloadTask];
        }
    [self unlock];
    return containsTask;
}

- (void)setQueuePriority:(PINRemoteImageManagerPriority)priority forTask:(NSURLSessionDataTask *)downloadTask
{
    [self setQueuePriority:priority forTask:downloadTask addIfNecessary:NO];
}

- (void)setQueuePriority:(PINRemoteImageManagerPriority)priority forTask:(NSURLSessionDataTask *)downloadTask addIfNecessary:(BOOL)addIfNecessary
{
    BOOL containsTask = [self removeDownloadTaskFromQueue:downloadTask];
    
    if (containsTask || addIfNecessary) {
        NSMutableArray <NSURLSessionDataTask *> *queue = nil;
        [self lock];
            switch (priority) {
                case PINRemoteImageManagerPriorityLow:
                    queue = _lowPriorityQueuedOperations;
                    break;
                    
                case PINRemoteImageManagerPriorityDefault:
                    queue = _defaultPriorityQueuedOperations;
                    break;
                    
                case PINRemoteImageManagerPriorityHigh:
                    queue = _highPriorityQueuedOperations;
                    break;
            }
            [queue addObject:downloadTask];
        [self unlock];
    }
}

- (void)lock
{
    [_lock lock];
}

- (void)unlock
{
    [_lock unlock];
}

@end
