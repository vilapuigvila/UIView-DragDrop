//
//  UIView+DragDrop.m
//
//  Created by Ryan Meisters
//

#import "UIView+DragDrop.h"
#import <objc/runtime.h>

/**
 * A Category on UIView to add drag and drop functionality
 * to a UIView.
 *
 * Note: Uses objective-c runtime API to keep track of drop
 *   views and starting position of the drag
 */

// duration of animation back to starting position
#define RESET_ANIMATION_DURATION .5

#define STRONG_N OBJC_ASSOCIATION_RETAIN_NONATOMIC
#define ASSIGN   OBJC_ASSOCIATION_ASSIGN

/// SH: addresses used as keys for associated objects
static char _delegate, _dropViews, _startPos, _isHovering, _mode;



@implementation UIView (DragDrop)

- (void) makeDraggable {
    [self makeDraggableWithDropViews:nil delegate:nil];
}

- (void) makeDraggableWithDropViews:(NSArray *)views delegate:(id<UIViewDragDropDelegate>)delegate {
    //Save pertinent info
    
    objc_setAssociatedObject(self, &_delegate, delegate, ASSIGN);
    objc_setAssociatedObject(self, &_isHovering, @NO, STRONG_N);
    objc_setAssociatedObject(self, &_mode, @(UIViewDragDropModeNormal), STRONG_N);
    
    [self setDropViews:views];
    
    //add the pan gesture
    [self addPanGesture];
}

#pragma mark - Setters

- (void) setDelegate:(id<UIViewDragDropDelegate>)delegate {
    objc_setAssociatedObject(self, &_delegate, delegate, ASSIGN);
}

- (void) setDragMode:(UIViewDragDropMode)mode {
    objc_setAssociatedObject(self, &_mode, @(mode), STRONG_N);
}

- (void) setDropViews:(NSArray*)views {
    objc_setAssociatedObject(self, &_dropViews, views, STRONG_N);
}

#pragma mark - Private API

- (void) addPanGesture {
    UIPanGestureRecognizer *rec;
    rec = [[UIPanGestureRecognizer alloc] initWithTarget: self
                                                  action: @selector(dragging:)];
    [self addGestureRecognizer:rec];
}

// Handle UIPanGestureRecognizer events
- (void) dragging:(UIPanGestureRecognizer *)recognizer {
    //get pertinent info
    id delegate        = objc_getAssociatedObject(self, &_delegate);
    NSArray *dropViews = objc_getAssociatedObject(self, &_dropViews);
    UIViewDragDropMode mode = [objc_getAssociatedObject(self, &_mode) integerValue];
    
    // Move to superview
    CGFloat moveUpToFinger;
    if (recognizer.state == UIGestureRecognizerStateBegan) {
        if ([delegate respondsToSelector:@selector(moveUpToFinger)]) {
            moveUpToFinger        = [delegate moveUpToFinger];
            CGRect rect           = recognizer.view.frame;
            rect.origin.y         = rect.origin.y - moveUpToFinger;
            recognizer.view.frame = rect;
        }
        
        // tell the delegate we're being dragged
        if ([delegate respondsToSelector:@selector(draggingDidBeginForView:)]) {
            [delegate draggingDidBeginForView:self];
        }
        
        //save the starting position of the view
        NSDictionary *startPos = @{@"x": @(self.center.x), @"y": @(self.center.y + moveUpToFinger)};
        
        objc_setAssociatedObject(self, &_startPos, startPos, STRONG_N);
    }
    
    //process the drag
    CGPoint pointInWindow;
    CGRect frameInWindow;
    
    if (recognizer.state == UIGestureRecognizerStateChanged ||
        (recognizer.state == UIGestureRecognizerStateEnded)) {
        
        pointInWindow = [recognizer locationInView:recognizer.view.window];
        frameInWindow = [recognizer.view.window convertRect:recognizer.view.frame
                                                   fromView:self.superview];
        
        if ([delegate respondsToSelector:@selector(view:pointInView:rectInWindow:)]) {
            [delegate view:self pointInView:pointInWindow rectInWindow:frameInWindow];
        }
        
        CGPoint trans = [recognizer translationInView:self.superview];
        CGFloat newX, newY;
        
        newX = self.center.x;
        newY = self.center.y;
        
        if (mode == UIViewDragDropModeNormal || mode == UIViewDragDropModeRestrictY) {
            newY += trans.y;
        }
        if (mode == UIViewDragDropModeNormal || mode == UIViewDragDropModeRestrictX) {
            newX += trans.x;
        }
        
        self.center = CGPointMake(newX, newY);
        
        BOOL isHovering = [objc_getAssociatedObject(self, &_isHovering) boolValue];
        
        // check if we're on a drop view
        for (UIView *v in dropViews) {
            if (CGRectIntersectsRect(self.frame, v.frame)) {
                //notify delegate if we're on a drop view
                if (isHovering == NO) {
                    if ([delegate respondsToSelector:@selector(view:didHoverOverDropView:)]) {
                        [delegate view:self didHoverOverDropView:v];
                    }
                    isHovering = YES;
                }
            } else {
                if (isHovering == YES) {
                    isHovering = NO;
                    if ([delegate respondsToSelector:@selector(view:didUnhoverOverDropView:)]) {
                        [delegate view:self didUnhoverOverDropView:v];
                    }
                }
            }
        }
        
        objc_setAssociatedObject(self, &_isHovering, @(isHovering), STRONG_N);
        
        //reset the gesture's translation
        [recognizer setTranslation:CGPointZero inView:self.superview];
    }
    
    // if the drag is over, check if we were dropped on a dropview
    if (recognizer.state == UIGestureRecognizerStateEnded) {
        BOOL goBack = NO;
        if ( [delegate respondsToSelector:@selector(viewShouldReturnToStartingPosition:)] ) {
            goBack = [delegate viewShouldReturnToStartingPosition:self];
        }
        
        for (UIView *v in dropViews) {
            if (CGRectIntersectsRect(self.frame, v.frame)) {
                //notify delegate
                [delegate view:self wasDroppedOnDropView:v];
            } else {
                if ([delegate respondsToSelector:@selector(draggingDidEndWithoutDropForView:)]){
                    [delegate draggingDidEndWithoutDropForView:self];
                }
            }
        }
        
        if ([delegate respondsToSelector:@selector(view:didEndDraggingInPoint:rectInWindow:)]) {
            [delegate view:self didEndDraggingInPoint:pointInWindow rectInWindow:frameInWindow];
        }
        
        // animate back to starting point if enabled
        if (goBack) {
            NSDictionary *start = objc_getAssociatedObject(self, &_startPos);
            
            CGFloat x = [start[@"x"] floatValue];
            CGFloat y = [start[@"y"] floatValue];
            CGPoint c = CGPointMake(x, y);
            
            [UIView animateWithDuration:RESET_ANIMATION_DURATION
                             animations:^{ self.center = c; }];
        }
    }
}


@end
