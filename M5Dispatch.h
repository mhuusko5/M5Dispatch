//
//  M5Dispatch.h
//  M5Dispatch
//

#import <Foundation/Foundation.h>

#pragma mark - M5Dispatch -

#pragma mark Macros

/* Return block for dispatching block once. Usage: M5DispatchOnce(^{ NSLog(@"Hello!"); }); */
#define M5DispatchOnce \
({ \
    static dispatch_once_t onceToken; \
    ^(dispatch_block_t block) { \
        dispatch_once(&onceToken, block); \
    }; \
})

/* Return block for dispatching block max of once every SECS. Usage: M5DispatchThrottle(2.8)(^{ NSLog(@"Hello!"); }); */
#define M5DispatchThrottle(SECS) \
({ \
    static NSDate *lastCall = nil; \
    ^(dispatch_block_t block) { \
        @synchronized(lastCall) { \
            if (!lastCall || fabs(lastCall.timeIntervalSinceNow) > SECS) { \
                lastCall = NSDate.date; \
                block(); \
            } \
        } \
    }; \
})

/* Return block for returning result of dispatching block once. Usage: M5DispatchOnceReturn(NSArray*)(^{ return NSArray.new; }); */
#define M5DispatchOnceReturn(TYPE) \
({ \
    static TYPE obj; \
    static dispatch_once_t onceToken; \
    ^ TYPE (TYPE (^block)()) { \
        dispatch_once(&onceToken, ^{ obj = block(); }); \
        return obj; \
    }; \
})

/* Returns block for returning result of dispatching block synchronously. Usage: M5DispatchSyncReturn(BOOL)(dispatch_get_main_queue(), ^{ return NO; }); */
#define M5DispatchSyncReturn(TYPE) \
({ \
    ^ TYPE (dispatch_queue_t queue, TYPE (^block)()) { \
        __block TYPE obj; \
        M5DispatchSync(queue, ^{ obj = block(); }); \
        return obj; \
    }; \
})

/* Returns YES only once, then NO. Usage: if (M5Once) { NSLog(@"Hello!"); } */
#define M5Once \
({ \
    __block BOOL once = NO; \
    M5DispatchOnce(^{ once = YES; }); \
    once; \
})

/* Returns YES only if last YES was more than SECS ago. Usage: if (M5Throttle(2.3)) { NSLog(@"Hello!"); } */
#define M5Throttle(SECS) \
({ \
    static NSDate *lastCall = nil; \
    BOOL throttled = NO; \
    @synchronized(lastCall) { \
        if (!lastCall || fabs(lastCall.timeIntervalSinceNow) > SECS) { \
            lastCall = NSDate.date; \
            throttled = YES; \
        } \
    } \
    throttled; \
})

#pragma mark Types

typedef void (^M5VoidBlock)();

typedef void (^M5QueuedDispatchBlock)(M5VoidBlock finished);

#pragma mark Functions

/** Dispatch block async on queue if limit of concurrent context/key dispatches has not been met, else enqueue.
    For async/nested operations, keep (by simply referencing) and call the 'finished' block when you're done. */
extern void M5DispatchQueued(dispatch_queue_t queue, NSObject *context, const void *key, NSUInteger limit, M5QueuedDispatchBlock block);

/** Dispatch block async async to main queue after seconds. */
extern void M5DispatchAfter(float seconds, dispatch_block_t block);

/** Dispatch block sync to queue. Simply calls block if currently on that queue (deadlock safe). */
extern void M5DispatchSync(dispatch_queue_t queue, dispatch_block_t block);

/** Dispatch block async to queue. */
extern void M5DispatchAsync(dispatch_queue_t queue, dispatch_block_t block);

/** Dispatch block async to main queue. */
extern void M5DispatchMain(dispatch_block_t block);

/** Checks if queue is the current queue. */
extern BOOL M5OnQueue(dispatch_queue_t queue);

/** Returns main queue. */
extern dispatch_queue_t M5MainQueue();

#pragma mark -
