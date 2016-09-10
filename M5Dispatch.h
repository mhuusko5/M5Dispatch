//
//  M5Dispatch.h
//  M5Dispatch
//

#import <Foundation/Foundation.h>

#import "M5Macros.h"

NS_ASSUME_NONNULL_BEGIN

#if defined __cplusplus
extern "C" {
#endif

#pragma mark - M5Dispatch -

#pragma mark Macros

/* Return block for dispatching block once.
   Usage: M5DispatchOnce(^{ NSLog(@"Hello!"); }); */
#define M5DispatchOnce \
({ \
    static dispatch_once_t onceToken; \
    ^(dispatch_block_t block) { \
        dispatch_once(&onceToken, block); \
    }; \
})

/* Return block for dispatching block max of once every SECS.
   Usage: M5DispatchThrottle(2.8)(^{ NSLog(@"Hello!"); }); */
#define M5DispatchThrottle(SECS...) \
({ \
    static NSDate *calledOn = nil; \
    ^(dispatch_block_t block) { \
        @synchronized (calledOn) { \
            if (!calledOn || -calledOn.timeIntervalSinceNow > SECS) { \
                calledOn = NSDate.date; \
                block(); \
            } \
        } \
    }; \
})

/* Return block for returning result of dispatching block once.
   Usage: M5DispatchOnceReturn(NSArray*)(^{ return [NSArray new]; }); */
#define M5DispatchOnceReturn(TYPE...) \
({ \
    static TYPE obj; \
    static dispatch_once_t onceToken; \
    ^ TYPE (TYPE (^block)()) { \
        dispatch_once(&onceToken, ^{ obj = block(); }); \
        return obj; \
    }; \
})

/* Returns block for returning result of dispatching block synchronously.
   Usage: M5DispatchSyncReturn(BOOL)(M5MainQueue(), ^{ return NO; }); */
#define M5DispatchSyncReturn(TYPE...) \
({ \
    ^ TYPE (dispatch_queue_t queue, TYPE (^block)()) { \
        __block TYPE obj; \
        M5DispatchSync(queue, ^{ obj = block(); }); \
        return obj; \
    }; \
})

/* Returns YES only once, then NO.
   Usage: if (M5Once) { NSLog(@"Hello!"); } */
#define M5Once \
({ \
    __block BOOL once = NO; \
    M5DispatchOnce(^{ once = YES; }); \
    once; \
})

/* Returns YES only if last YES was more than SECS ago.
   Usage: if (M5Throttle(2.3)) { NSLog(@"Hello!"); } */
#define M5Throttle(SECS...) \
({ \
    static NSDate *calledOn = nil; \
    BOOL allow = NO; \
    @synchronized (calledOn) { \
        if (!calledOn || -calledOn.timeIntervalSinceNow > SECS) { \
            calledOn = NSDate.date; \
            allow = YES; \
        } \
    } \
    allow; \
})

#pragma mark Types

typedef void (^M5VoidBlock)() NS_SWIFT_NAME(VoidBlock);

NS_SWIFT_NAME(QueuedDispatchToken)
@interface M5QueuedDispatchToken : NSObject

@property (nonatomic, readonly) BOOL isCancelled;

- (void)finish;

@end

typedef void (^M5QueuedDispatchBlock)(M5QueuedDispatchToken *token) NS_SWIFT_NAME(QueuedDispatchBlock);

NS_SWIFT_NAME(QueuedDispatcher)
@interface M5QueuedDispatcher : NSObject

/** Creates dispatcher with concurrent limit, and max before discard. */
+ (instancetype)dispatcherWithCurrentLimit:(NSUInteger)currentLimit queueLimit:(NSUInteger)queueLimit;

/** Queues block to be dispatched, with optional timeout. */
- (void)queue:(M5QueuedDispatchBlock)block
         next:(BOOL)next
  withTimeout:(NSTimeInterval)timeout
      onQueue:(dispatch_queue_t)queue;

/** Clears queue. */
- (void)clearQueue;

@end

NS_SWIFT_NAME(DebouncedDispatcher)
@interface M5DebouncedDispatcher : NSObject

/** Creates dispatcher with interval. */
+ (instancetype)dispatcherWithInterval:(NSTimeInterval)interval;

/** Dispatches (or bounces) block. */
- (void)debounce:(M5VoidBlock)block onQueue:(dispatch_queue_t)queue;

@end

typedef struct {
    NSUInteger curLimit;
    NSUInteger queLimit;
    NSTimeInterval opTimeout;
    BOOL opNext;
} M5DispatchQueuedOptions;

#pragma mark Functions

/** Set queueing queue override. */
extern void M5DispatchSetQueueingQueue(dispatch_queue_t _Nullable queue) NS_SWIFT_NAME(dispatchSetQueueingQueue(_:));

/** Dispatch block async on queue if limit of concurrent context/key dispatches has not been met, else enqueue.
    For async/nested operations, keep (by simply referencing) and call the 'finished' block when you're done. */
NS_SWIFT_NAME(dispatchQueued(_:context:key:currentLimit:queueLimit:operationTimeout:operationNext:_:))
extern void M5DispatchQueuedI(dispatch_queue_t queue,
                              id<NSObject> context, const void *key,
                              NSUInteger curLimit, NSUInteger queLimit, NSTimeInterval opTimeout, BOOL opNext,
                              M5QueuedDispatchBlock block);

/** Struct options version of M5DispatchQueued. */
extern void M5DispatchQueued(dispatch_queue_t queue,
                             id<NSObject> context, const void *key,
                             M5DispatchQueuedOptions options,
                             M5QueuedDispatchBlock block);

/** Dispatch block, or discard if last block dispatched less than 'interval' seconds ago. */
NS_SWIFT_NAME(dispatchDebounced(_:context:key:interval:_:))
extern void M5DispatchDebounced(dispatch_queue_t queue,
                                id<NSObject> context, const void *key,
                                NSTimeInterval interval,
                                M5VoidBlock block);

/** Dispatch block async to queue after seconds. */
NS_SWIFT_NAME(dispatchAfter(_:_:_:))
extern void M5DispatchAfter(NSTimeInterval seconds, dispatch_queue_t queue, dispatch_block_t block);

/** Dispatch block async to queue after seconds, call returned block to cancel. */
NS_SWIFT_NAME(dispatchAfterCancel(_:_:_:))
extern M5VoidBlock M5DispatchAfterCancel(NSTimeInterval seconds, dispatch_queue_t queue, dispatch_block_t block);
    
/** Dispatch block async to queue after seconds, with strict leeway. */
NS_SWIFT_NAME(dispatchAfter(_:leeway:_:_:))
extern void M5DispatchAfterS(NSTimeInterval seconds, double leeway, dispatch_queue_t queue, dispatch_block_t block);

/** Dispatch block async to queue after seconds, with strict leeway, call returned block to cancel. */
NS_SWIFT_NAME(dispatchAfterCancel(_:leeway:_:_:))
extern M5VoidBlock M5DispatchAfterCancelS(NSTimeInterval seconds, double leeway, dispatch_queue_t queue, dispatch_block_t block);

/** Dispatch block sync to queue. Calls block if currently on that queue (deadlock safe). */
extern void M5DispatchSync(dispatch_queue_t queue, dispatch_block_t block) NS_SWIFT_NAME(dispatchSync(_:_:));

/** Dispatch block async to queue. Calls block if currently on that queue. */
extern void M5DispatchAsync(dispatch_queue_t queue, dispatch_block_t block) NS_SWIFT_NAME(dispatchAsync(_:_:));

/** Dispatch block async to queue. */
extern void M5DispatchDefer(dispatch_queue_t queue, dispatch_block_t block) NS_SWIFT_NAME(dispatchDefer(_:_:));

/** Dispatch block async to main queue. */
extern void M5DispatchMain(dispatch_block_t block) NS_SWIFT_NAME(dispatchMain(_:));

/** Associated queue with itself via dispatch_set_specific, for M5OnQueue lookup. */
extern void M5MarkQueue(dispatch_queue_t queue) NS_SWIFT_NAME(markQueue(_:));

/** Checks if queue is the current queue. */
extern BOOL M5OnQueue(dispatch_queue_t queue) NS_SWIFT_NAME(onQueue(_:));

/** Returns main queue. */
extern dispatch_queue_t M5MainQueue() NS_SWIFT_NAME(mainQueue());

#if defined __cplusplus
}
#endif

NS_ASSUME_NONNULL_END
