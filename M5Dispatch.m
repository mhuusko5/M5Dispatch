//
//  M5Dispatch.m
//  M5Dispatch
//

#import <objc/runtime.h>

#import "M5Dispatch.h"

NS_ASSUME_NONNULL_BEGIN

#pragma mark - M5Dispatch -

#pragma mark Types

static dispatch_queue_t _Nullable queueingQueue = nil;

dispatch_queue_t M5QueueingQueue() {
    return queueingQueue ?: M5DispatchOnceReturn(dispatch_queue_t)(^{
        dispatch_queue_t queue = dispatch_queue_create("com.mhuusko5.M5Dispatch.Queueing", DISPATCH_QUEUE_SERIAL);

        M5MarkQueue(queue);

        return queue;
    });
}

@interface M5QueuedOperation : NSObject

@property (nonatomic, readonly) M5QueuedDispatchBlock block;
@property (nonatomic, readonly) NSTimeInterval timeout;
@property (nonatomic, readonly) dispatch_queue_t queue;

@end

@implementation M5QueuedOperation

- (instancetype)initWithBlock:(M5QueuedDispatchBlock)block
                      timeout:(NSTimeInterval)timeout
                        queue:(dispatch_queue_t)queue {

    if (!(self = [self init])) { return nil; }

    _block = block;
    _timeout = timeout;
    _queue = queue;

    return self;
}

@end

@interface M5QueuedDispatchToken ()

@property (nonatomic, nullable) M5VoidBlock finished;

@end

@implementation M5QueuedDispatchToken

- (instancetype)initWithFinished:(M5VoidBlock)finished {
    if (!(self = [self init])) { return nil; }

    _finished = finished;

    return self;
}

- (BOOL)isCancelled {
    @synchronized (self) {
        return !self.finished;
    }
}

- (void)finish {
    @synchronized (self) {
        if (self.finished) {
            self.finished();
            self.finished = nil;
        }
    }
}

- (void)dealloc {
    [self finish];
}

@end

@interface M5QueuedDispatcher ()

@property (nonatomic, readonly) NSMutableArray<M5QueuedOperation*> *queued;
@property (nonatomic) NSInteger currentCount;

@property (nonatomic, readonly) NSUInteger currentLimit;
@property (nonatomic, readonly) NSUInteger queueLimit;

@property (nonatomic, readonly) NSMutableArray<M5QueuedDispatchToken*> *timedOut;

@end

@implementation M5QueuedDispatcher

- (instancetype)initWithCurrentLimit:(NSUInteger)currentLimit queueLimit:(NSUInteger)queueLimit {
    if (!(self = [self init])) { return nil; }

    _queued = [NSMutableArray new];

    _currentLimit = currentLimit;
    _queueLimit = queueLimit;

    _timedOut = [NSMutableArray new];

    return self;
}

+ (instancetype)dispatcherWithCurrentLimit:(NSUInteger)currentLimit queueLimit:(NSUInteger)queueLimit {
    return [[self alloc] initWithCurrentLimit:currentLimit queueLimit:queueLimit];
}

- (void)queue:(M5QueuedDispatchBlock)block
         next:(BOOL)next
  withTimeout:(NSTimeInterval)timeout
      onQueue:(dispatch_queue_t)queue {

    M5DispatchAsync(M5QueueingQueue(), ^{
        M5QueuedOperation *operation = [[M5QueuedOperation alloc] initWithBlock:block
                                                                        timeout:timeout
                                                                          queue:queue];
        if (next) {
            [self.queued insertObject:operation atIndex:0];
        } else {
            [self.queued addObject:operation];
        }

        [self trimQueue];

        [self dequeue];

        [self checkTimedOut];
    });
}

- (void)checkTimedOut {
    M5DispatchAsync(M5QueueingQueue(), ^{
        if (self.timedOut.count) {
            NSArray *timedOut = self.timedOut.copy;
            [self.timedOut removeAllObjects];

            for (M5QueuedDispatchToken *token in timedOut) {
                [token finish];
            }
        }
    });
}

- (void)trimQueue {
    M5DispatchAsync(M5QueueingQueue(), ^{
        if (self.queueLimit && self.queued.count) {
            M5QueuedDispatchToken *token = [[M5QueuedDispatchToken alloc] initWithFinished:^{}];
            [token finish];

            while (self.queued.count > self.queueLimit) {
                M5QueuedOperation *operation = self.queued.lastObject;
                [self.queued removeLastObject];

                return M5DispatchAsync(operation.queue, ^{ operation.block(token); });
            }
        }
    });
}

- (void)clearQueue {
    M5DispatchAsync(M5QueueingQueue(), ^{
        if (self.queued.count) {
            M5QueuedDispatchToken *token = [[M5QueuedDispatchToken alloc] initWithFinished:^{}];
            [token finish];

            NSArray *queued = self.queued.copy;
            [self.queued removeAllObjects];

            for (M5QueuedOperation *operation in queued) {
                M5DispatchAsync(operation.queue, ^{ operation.block(token); });
            }
        }
    });
}

- (void)dequeue {
    M5DispatchAsync(M5QueueingQueue(), ^{
        if (self.currentCount < self.currentLimit && self.queued.count) {
            self.currentCount += 1;

            M5QueuedOperation *operation = self.queued.firstObject;
            [self.queued removeObjectAtIndex:0];

            M5Weakify(self);
            __block M5QueuedDispatchToken *token = [[M5QueuedDispatchToken alloc] initWithFinished:^{
                M5Strongify(self);

                M5DispatchAsync(M5QueueingQueue(), ^{
                    self.currentCount -= 1;

                    [self dequeue];
                });
            }];

            M5DispatchAsync(operation.queue, ^{
                operation.block(token);

                __weak typeof(token) weakToken = token;
                token = nil;

                if (weakToken && !weakToken.isCancelled && operation.timeout && !isinf(operation.timeout)) {

                    M5Weakify(self);
                    M5DispatchAfter(operation.timeout, M5QueueingQueue(), ^{
                        M5Strongify(self);

                        typeof(weakToken) token = weakToken;

                        if (token && !token.isCancelled) {
                            if (!self || self.queued.count) {
                                [token finish];
                            } else {
                                [self.timedOut addObject:token];
                            }
                        }
                    });
                }
            });
        }
    });
}

@end

@interface M5DebouncedDispatcher ()

@property (nonatomic) NSDate *calledOn;
@property (nonatomic, nullable) M5VoidBlock lastCancel;

@property (nonatomic, readonly) NSTimeInterval interval;

@end

@implementation M5DebouncedDispatcher

- (instancetype)initWithInterval:(NSTimeInterval)interval {
    if (!(self = [self init])) { return nil; }

    _calledOn = [[NSDate new] dateByAddingTimeInterval:-interval];

    _interval = interval;

    return self;
}

+ (instancetype)dispatcherWithInterval:(NSTimeInterval)interval {
    return [[M5DebouncedDispatcher alloc] initWithInterval:interval];
}

- (void)debounce:(M5VoidBlock)block onQueue:(dispatch_queue_t)queue {
    M5DispatchAsync(M5QueueingQueue(), ^{
        if (self.lastCancel) {
            self.lastCancel();
            self.lastCancel = nil;
        }

        M5VoidBlock dispatch = ^{
            self.calledOn = [NSDate new];
            self.lastCancel = nil;

            M5DispatchAsync(queue, block);
        };

        if (-self.calledOn.timeIntervalSinceNow >= self.interval) {
            dispatch();
        } else {
            self.lastCancel = M5DispatchAfterCancel([self.calledOn dateByAddingTimeInterval:
                                                     self.interval].timeIntervalSinceNow,
                                                    M5QueueingQueue(),
                                                    dispatch);
        }
    });
}

@end

#pragma mark Functions

void M5DispatchSetQueueingQueue(dispatch_queue_t _Nullable queue) {
    queueingQueue = queue;

    if (queueingQueue) {
        M5MarkQueue(queueingQueue);
    }
}

void M5DispatchQueuedI(dispatch_queue_t queue,
                       id<NSObject> context, const void *key,
                       NSUInteger curLimit, NSUInteger queLimit, NSTimeInterval opTimeout, BOOL opNext,
                       M5QueuedDispatchBlock block) {

    static const void *dispatcherkey = &dispatcherkey;

    M5DispatchAsync(M5QueueingQueue(), ^{
        NSObject *dispatchContext = objc_getAssociatedObject(context, dispatcherkey);
        if (!dispatchContext) {
            objc_setAssociatedObject(context, dispatcherkey,
                                     (dispatchContext = NSObject.new),
                                     OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }

        M5QueuedDispatcher *dispatcher = objc_getAssociatedObject(dispatchContext, key);
        if (!dispatcher) {
            objc_setAssociatedObject(dispatchContext, key,
                                     (dispatcher = [M5QueuedDispatcher dispatcherWithCurrentLimit:curLimit
                                                                                       queueLimit:queLimit]),
                                     OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }

        [dispatcher queue:block next:opNext withTimeout:opTimeout onQueue:queue];
    });
}

void M5DispatchQueued(dispatch_queue_t queue,
                      id<NSObject> context, const void *key,
                      M5DispatchQueuedOptions options,
                      M5QueuedDispatchBlock block) {

    M5DispatchQueuedI(queue, context, key,
                      options.curLimit, options.queLimit, options.opTimeout, options.opNext, block);
}

void M5DispatchDebounced(dispatch_queue_t queue,
                         id<NSObject> context, const void *key,
                         NSTimeInterval interval,
                         M5VoidBlock block) {

    static const void *dispatcherkey = &dispatcherkey;

    M5DispatchAsync(M5QueueingQueue(), ^{
        NSObject *dispatchContext = objc_getAssociatedObject(context, dispatcherkey);
        if (!dispatchContext) {
            objc_setAssociatedObject(context, dispatcherkey,
                                     (dispatchContext = NSObject.new),
                                     OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }

        M5DebouncedDispatcher *dispatcher = objc_getAssociatedObject(dispatchContext, key);
        if (!dispatcher) {
            objc_setAssociatedObject(dispatchContext, key,
                                     (dispatcher = [M5DebouncedDispatcher dispatcherWithInterval:interval]),
                                     OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }

        [dispatcher debounce:block onQueue:queue];
    });
}

void M5DispatchAfter(NSTimeInterval seconds, dispatch_queue_t queue, dispatch_block_t block) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(seconds * NSEC_PER_SEC)), queue, block);
}

M5VoidBlock M5DispatchAfterCancel(NSTimeInterval seconds, dispatch_queue_t queue, dispatch_block_t block) {
    dispatch_block_t cancellableBlock = dispatch_block_create(DISPATCH_BLOCK_DETACHED, block);

    M5DispatchAfter(seconds, queue, cancellableBlock);

    return ^{ dispatch_block_cancel(cancellableBlock); };
}

void M5DispatchAfterS(NSTimeInterval seconds, double leeway, dispatch_queue_t queue, dispatch_block_t block) {
    dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER,
                                                     0,
                                                     DISPATCH_TIMER_STRICT,
                                                     queue);

    dispatch_source_set_event_handler(timer, ^{
        dispatch_source_cancel(timer);
        block();
    });

    dispatch_source_set_timer(timer,
                              dispatch_time(DISPATCH_TIME_NOW, (int64_t)(seconds * NSEC_PER_SEC)),
                              DISPATCH_TIME_FOREVER,
                              (int64_t)(seconds * leeway * NSEC_PER_SEC));
    dispatch_resume(timer);
}

M5VoidBlock M5DispatchAfterCancelS(NSTimeInterval seconds, double leeway, dispatch_queue_t queue, dispatch_block_t block) {
    dispatch_block_t cancellableBlock = dispatch_block_create(DISPATCH_BLOCK_DETACHED, block);

    M5DispatchAfterS(seconds, leeway, queue, cancellableBlock);

    return ^{ dispatch_block_cancel(cancellableBlock); };
}

void M5DispatchSync(dispatch_queue_t queue, dispatch_block_t block) {
    if (M5OnQueue(queue)) {
        block();
    } else {
        dispatch_sync(queue, block);
    }
}

void M5DispatchAsync(dispatch_queue_t queue, dispatch_block_t block) {
    if (M5OnQueue(queue)) {
        block();
    } else {
        dispatch_async(queue, block);
    }
}

void M5DispatchDefer(dispatch_queue_t queue, dispatch_block_t block) {
    dispatch_async(queue, block);
}

void M5DispatchMain(dispatch_block_t block) {
    M5DispatchDefer(M5MainQueue(), block);
}

static const void *queueSpecificKey = &queueSpecificKey;

void M5MarkQueue(dispatch_queue_t queue) {
    dispatch_queue_set_specific(queue, queueSpecificKey, (__bridge void *)queue, nil);
}

BOOL M5OnQueue(dispatch_queue_t queue) {
    void *specificValue = dispatch_get_specific(queueSpecificKey);
    if (specificValue) {
        return specificValue == (__bridge void *)queue;
    }
    
    return NO;
}

dispatch_queue_t M5MainQueue() {
    return M5DispatchOnceReturn(dispatch_queue_t)(^{
        dispatch_queue_t queue = dispatch_get_main_queue();
        
        M5MarkQueue(queue);
        
        return queue;
    });
}

NS_ASSUME_NONNULL_END
