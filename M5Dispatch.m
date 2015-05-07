//
//  M5Dispatch.m
//  M5Dispatch
//

#import "M5Dispatch.h"

#import <objc/runtime.h>

#pragma mark - M5Dispatch -

#pragma mark Functions

void M5DispatchQueued(dispatch_queue_t queue, NSObject *context, const void *key, NSUInteger limit, M5QueuedDispatchBlock block) {
    static const void *queuedBlocksesKey = &queuedBlocksesKey;
    static const void *executingCountsKey = &executingCountsKey;
    
    static dispatch_queue_t queueingQueue;
    M5DispatchOnce(^{
        queueingQueue = dispatch_queue_create("com.mhuusko5.M5Dispatch.Queueing", DISPATCH_QUEUE_SERIAL);
    });
    
    __weak typeof(context) weakContext = context;
    
    M5DispatchAsync(queueingQueue, ^{
        typeof(weakContext) context = weakContext;
        
        if (!context) {
            return;
        }
        
        NSObject *queuedBlockses = objc_getAssociatedObject(context, queuedBlocksesKey);
        
        if (!queuedBlockses) {
            objc_setAssociatedObject(context, queuedBlocksesKey, (queuedBlockses = NSObject.new), OBJC_ASSOCIATION_RETAIN);
        }
        
        NSMutableArray *queuedBlocks = objc_getAssociatedObject(queuedBlockses, key);
        
        if (!queuedBlocks) {
            objc_setAssociatedObject(queuedBlockses, key, (queuedBlocks = NSMutableArray.new), OBJC_ASSOCIATION_RETAIN);
        }
        
        NSObject *executingCounts = objc_getAssociatedObject(context, executingCountsKey);
        
        if (!executingCounts) {
            objc_setAssociatedObject(context, executingCountsKey, (executingCounts = NSObject.new), OBJC_ASSOCIATION_RETAIN);
        }
        
        NSUInteger executingCount = [objc_getAssociatedObject(executingCounts, key) unsignedIntegerValue];
        
        if (executingCount < limit) {
            objc_setAssociatedObject(executingCounts, key, @(++executingCount), OBJC_ASSOCIATION_RETAIN);
            
            M5VoidBlock blockExecuted = ^{
                M5DispatchAsync(queueingQueue, ^{
                    typeof(weakContext) context = weakContext;
                    
                    if (!context) {
                        return;
                    }
                    
                    objc_setAssociatedObject(executingCounts, key, @([objc_getAssociatedObject(executingCounts, key) unsignedIntegerValue] - 1), OBJC_ASSOCIATION_RETAIN);
                    
                    M5QueuedDispatchBlock queuedBlock = queuedBlocks.firstObject;
                    if (queuedBlock) {
                        [queuedBlocks removeObject:queuedBlock];
                        
                        M5DispatchQueued(queue, context, key, limit, queuedBlock);
                    }
                });
            };
            
            M5DispatchAsync(queue, ^{
                __weak M5VoidBlock weakFinished = nil;
                M5VoidBlock finished = nil;
                
                weakFinished = finished = ^{
                    blockExecuted();
                };
                
                block(finished);
                finished = nil;
                
                if (!weakFinished) {
                    blockExecuted();
                }
            });
        } else {
            [queuedBlocks addObject:block];
        }
    });
}

void M5DispatchMain(dispatch_block_t block) {
    M5DispatchAsync(M5MainQueue(), block);
}

void M5DispatchAfter(float seconds, dispatch_block_t block) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(seconds * NSEC_PER_SEC)), M5MainQueue(), block);
}

void M5DispatchSync(dispatch_queue_t queue, dispatch_block_t block) {
    #pragma clang diagnostic push
    #pragma clang diagnostic ignored "-Wdeprecated-declarations"
    if (!strcmp(dispatch_queue_get_label(queue), dispatch_queue_get_label(DISPATCH_CURRENT_QUEUE_LABEL))) {
        block();
    } else {
        dispatch_sync(queue, block);
    }
    #pragma clang diagnostic pop
}

void M5DispatchAsync(dispatch_queue_t queue, dispatch_block_t block) {
    dispatch_async(queue, block);
}

dispatch_queue_t M5MainQueue() {
    return dispatch_get_main_queue();
}

#pragma mark -
