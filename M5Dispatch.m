//
//  M5Dispatch.m
//  M5Dispatch
//

#import "M5Dispatch.h"

#import <objc/runtime.h>

#pragma mark - M5Dispatch -

#pragma mark Functions

void M5DispatchQueued(dispatch_queue_t queue, id context, const void *key, NSUInteger limit, NSTimeInterval timeout, M5QueuedDispatchBlock block) {
    static dispatch_queue_t queueingQueue;
    M5DispatchOnce(^{
        queueingQueue = dispatch_queue_create("com.mhuusko5.M5Dispatch.Queueing", DISPATCH_QUEUE_SERIAL);
    });
    
    __weak typeof(context) weakContext = context;
    
    NSMutableArray* (^queuedBlocks)() = ^{
        static const void *queuedBlocksesKey = &queuedBlocksesKey;
        
        typeof(weakContext) context = weakContext;
        
        NSObject *queuedBlockses = objc_getAssociatedObject(context, queuedBlocksesKey);
        
        if (!queuedBlockses) {
            objc_setAssociatedObject(context, queuedBlocksesKey, (queuedBlockses = NSObject.new), OBJC_ASSOCIATION_RETAIN);
        }
        
        NSMutableArray *queuedBlocks = objc_getAssociatedObject(queuedBlockses, key);
        
        if (!queuedBlocks) {
            objc_setAssociatedObject(queuedBlockses, key, (queuedBlocks = NSMutableArray.new), OBJC_ASSOCIATION_RETAIN);
        }
        
        return queuedBlocks;
    };
    
    NSObject* (^executingCounts)() = ^{
        static const void *executingCountsKey = &executingCountsKey;
        
        typeof(weakContext) context = weakContext;
        
        NSObject *executingCounts = objc_getAssociatedObject(context, executingCountsKey);
        
        if (!executingCounts) {
            objc_setAssociatedObject(context, executingCountsKey, (executingCounts = NSObject.new), OBJC_ASSOCIATION_RETAIN);
        }

        return executingCounts;
    };
    
    __block BOOL dispatchAlreadyFinished = NO;
    
    M5VoidBlock dispatchFinished = ^{
        typeof(weakContext) context = weakContext;
        
        if (!context || dispatchAlreadyFinished) {
            return;
        }
        
        dispatchAlreadyFinished = YES;
        
        objc_setAssociatedObject(executingCounts(), key, @([objc_getAssociatedObject(executingCounts(), key) unsignedIntegerValue] - 1), OBJC_ASSOCIATION_RETAIN);
        
        M5QueuedDispatchBlock queuedBlock = queuedBlocks().firstObject;
        if (queuedBlock) {
            [queuedBlocks() removeObject:queuedBlock];
            
            M5DispatchQueued(queue, context, key, limit, timeout, queuedBlock);
        }
    };
    
    M5VoidBlock queueDispatch = ^{
        typeof(weakContext) context = weakContext;
        
        if (!context) {
            return;
        }
        
        NSUInteger executingCount = [objc_getAssociatedObject(executingCounts(), key) unsignedIntegerValue];
        
        if (executingCount < limit) {
            objc_setAssociatedObject(executingCounts(), key, @(++executingCount), OBJC_ASSOCIATION_RETAIN);
            
            M5DispatchAsync(queue, ^{
                __weak M5VoidBlock weakFinished = nil;
                M5VoidBlock finished = nil;
                
                weakFinished = finished = ^{
                    M5DispatchAsync(queueingQueue, dispatchFinished);
                };
                
                block(finished);
                finished = nil;
                
                if (!weakFinished) {
                    M5DispatchAsync(queueingQueue, dispatchFinished);
                } else if (!isinf(timeout)) {
                    M5DispatchAfter(timeout, queueingQueue, dispatchFinished);
                }
            });
        } else {
            [queuedBlocks() addObject:block];
        }
    };
    
    if (M5OnQueue(queueingQueue)) {
        queueDispatch();
    } else {
        M5DispatchAsync(queueingQueue, queueDispatch);
    }
}

void M5DispatchAfter(float seconds, dispatch_queue_t queue, dispatch_block_t block) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(seconds * NSEC_PER_SEC)), queue, block);
}

void M5DispatchSync(dispatch_queue_t queue, dispatch_block_t block) {
    if (M5OnQueue(queue)) {
        block();
    } else {
        dispatch_sync(queue, block);
    }
}

void M5DispatchAsync(dispatch_queue_t queue, dispatch_block_t block) {
    dispatch_async(queue, block);
}

void M5DispatchMain(dispatch_block_t block) {
    M5DispatchAsync(M5MainQueue(), block);
}

BOOL M5OnQueue(dispatch_queue_t queue) {
    return !strcmp(dispatch_queue_get_label(queue), dispatch_queue_get_label(DISPATCH_CURRENT_QUEUE_LABEL));
}

dispatch_queue_t M5MainQueue() {
    return dispatch_get_main_queue();
}

#pragma mark -