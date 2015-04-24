//
//  M5Dispatch.h
//  M5Dispatch
//

#import <Foundation/Foundation.h>

#pragma mark - M5Dispatch -

#pragma mark Macros

/* Dispatches block once. */
#define M5DispatchOnce(BLOCK) \
({ \
    static dispatch_once_t onceToken; \
    dispatch_once(&onceToken, BLOCK); \
})

/* Returns result of calling block once. */
#define M5DispatchOnceReturn(TYPE, BLOCK) \
({ \
    static TYPE obj; \
    M5DispatchOnce(^{ obj = BLOCK(); }); \
    obj; \
})

/* Use as the case in an if statement to have the statement only execute once. */
#define M5Once \
({ \
    __block BOOL once = NO; \
    M5DispatchOnce(^{ once = YES; }); \
    once; \
})

/* Use as the case in an if statement to have the statement not execute more than once every SECS. */
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

/* Dispatches block synchronously and returns result. */
#define M5DispatchSyncReturn(QUEUE, TYPE, BLOCK) \
({ \
    __block TYPE obj; \
    M5DispatchSync(QUEUE, ^{ obj = BLOCK(); }); \
    obj; \
})

#pragma mark Functions

/** Dispatch block async to main queue. */
extern void M5DispatchMain(dispatch_block_t block);

/** Dispatch block async async to main queue after seconds. */
extern void M5DispatchAfter(float seconds, dispatch_block_t block);

/** Dispatch block sync to queue. Simply calls block if currently on that queue (deadlock safe). */
extern void M5DispatchSync(dispatch_queue_t queue, dispatch_block_t block);

/** Dispatch block async to queue. */
extern void M5DispatchAsync(dispatch_queue_t queue, dispatch_block_t block);

#pragma mark -