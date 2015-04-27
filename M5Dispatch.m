//
//  M5Dispatch.m
//  M5Dispatch
//

#import "M5Dispatch.h"

#pragma mark - M5Dispatch -

#pragma mark Functions

void M5DispatchMain(dispatch_block_t block) {
    dispatch_async(dispatch_get_main_queue(), block);
}

void M5DispatchAfter(float seconds, dispatch_block_t block) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(seconds * NSEC_PER_SEC)), dispatch_get_main_queue(), block);
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