#include "FloatingButtonController.h"
#include <iostream>
#import <UIKit/UIKit.h>

// Objective-C++ implementation of the button view
@interface FloatingButton : UIButton

@property (nonatomic, assign) iOS::FloatingButtonController* controller;
@property (nonatomic, assign) BOOL draggable;
@property (nonatomic, assign) CGPoint touchOffset;

@end

@implementation FloatingButton

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.draggable = YES;
        self.layer.cornerRadius = frame.size.width / 2.0;
        self.layer.masksToBounds = YES;
        self.backgroundColor = [UIColor colorWithRed:0.1 green:0.6 blue:0.9 alpha:1.0];
        
        // Add an icon or text
        [self setImage:[UIImage systemImageNamed:@"terminal"] forState:UIControlStateNormal];
        
        // Add shadow
        self.layer.shadowColor = [UIColor blackColor].CGColor;
        self.layer.shadowOffset = CGSizeMake(0, 2);
        self.layer.shadowOpacity = 0.5;
        self.layer.shadowRadius = 4.0;
        
        // Add a simple animation on creation
        self.transform = CGAffineTransformMakeScale(0.1, 0.1);
        [UIView animateWithDuration:0.3
                              delay:0
             usingSpringWithDamping:0.7
              initialSpringVelocity:0.5
                            options:UIViewAnimationOptionCurveEaseInOut
                         animations:^{
                             self.transform = CGAffineTransformIdentity;
                         }
                         completion:nil];
    }
    return self;
}

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    UITouch *touch = [touches anyObject];
    CGPoint touchPoint = [touch locationInView:self];
    self.touchOffset = touchPoint;
    
    // Add a subtle animation
    [UIView animateWithDuration:0.1 animations:^{
        self.transform = CGAffineTransformMakeScale(0.95, 0.95);
    }];
}

- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    if (!self.draggable) return;
    
    UITouch *touch = [touches anyObject];
    CGPoint location = [touch locationInView:self.superview];
    
    // Adjust by touch offset to keep the button under the finger
    CGPoint newCenter = CGPointMake(location.x - self.touchOffset.x + self.frame.size.width/2,
                                   location.y - self.touchOffset.y + self.frame.size.height/2);
    
    // Keep button within screen bounds
    newCenter.x = MAX(self.frame.size.width/2, MIN(newCenter.x, self.superview.frame.size.width - self.frame.size.width/2));
    newCenter.y = MAX(self.frame.size.height/2, MIN(newCenter.y, self.superview.frame.size.height - self.frame.size.height/2));
    
    self.center = newCenter;
    
    // Notify controller of movement
    if (self.controller) {
        float percentX = self.center.x / self.superview.frame.size.width;
        float percentY = self.center.y / self.superview.frame.size.height;
        self.controller->SetCustomPosition(percentX, percentY);
    }
}

- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    // Restore button size with animation
    [UIView animateWithDuration:0.1 animations:^{
        self.transform = CGAffineTransformIdentity;
    }];
    
    // Check if this was a tap (not a drag)
    UITouch *touch = [touches anyObject];
    CGPoint initialPoint = [touch locationInView:self];
    CGPoint finalPoint = [touch locationInView:self];
    
    // If touch didn't move much, consider it a tap
    if (hypot(finalPoint.x - initialPoint.x, finalPoint.y - initialPoint.y) < 10) {
        if (self.controller) {
            // Trigger tap callback
            self.controller->SetPosition(iOS::FloatingButtonController::Position::Custom);
        }
    }
    
    // Snap to nearest edge if desired
    [self snapToNearestEdge];
}

- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [UIView animateWithDuration:0.1 animations:^{
        self.transform = CGAffineTransformIdentity;
    }];
}

- (void)snapToNearestEdge {
    CGRect bounds = self.superview.bounds;
    CGPoint center = self.center;
    
    // Calculate distances to each edge
    CGFloat distToLeft = center.x;
    CGFloat distToRight = bounds.size.width - center.x;
    CGFloat distToTop = center.y;
    CGFloat distToBottom = bounds.size.height - center.y;
    
    // Find the minimum distance
    CGFloat minDist = MIN(MIN(distToLeft, distToRight), MIN(distToTop, distToBottom));
    
    // Determine which edge is closest
    iOS::FloatingButtonController::Position newPosition;
    
    if (minDist == distToLeft) {
        // Snap to left edge
        if (center.y < bounds.size.height / 2) {
            newPosition = iOS::FloatingButtonController::Position::TopLeft;
        } else {
            newPosition = iOS::FloatingButtonController::Position::BottomLeft;
        }
    } else if (minDist == distToRight) {
        // Snap to right edge
        if (center.y < bounds.size.height / 2) {
            newPosition = iOS::FloatingButtonController::Position::TopRight;
        } else {
            newPosition = iOS::FloatingButtonController::Position::BottomRight;
        }
    } else if (minDist == distToTop) {
        // Snap to top edge
        if (center.x < bounds.size.width / 2) {
            newPosition = iOS::FloatingButtonController::Position::TopLeft;
        } else {
            newPosition = iOS::FloatingButtonController::Position::TopRight;
        }
    } else {
        // Snap to bottom edge
        if (center.x < bounds.size.width / 2) {
            newPosition = iOS::FloatingButtonController::Position::BottomLeft;
        } else {
            newPosition = iOS::FloatingButtonController::Position::BottomRight;
        }
    }
    
    // Notify controller to update position
    if (self.controller) {
        self.controller->SetPosition(newPosition);
    }
}

@end

namespace iOS {
    // Constructor
    FloatingButtonController::FloatingButtonController(Position initialPosition, float size, float opacity)
        : m_buttonView(nullptr), m_isVisible(false), m_position(initialPosition),
          m_opacity(opacity), m_customX(0.0f), m_customY(0.0f), m_size(size),
          m_tapCallback(nullptr), m_isBeingDragged(false) {
        
        // Create the button
        CGRect frame = CGRectMake(0, 0, m_size, m_size);
        FloatingButton* button = [[FloatingButton alloc] initWithFrame:frame];
        button.controller = this;
        button.alpha = m_opacity;
        
        // Get the key window
        UIWindow* keyWindow = nil;
        if (@available(iOS 13.0, *)) {
            NSSet<UIScene *> *connectedScenes = [[UIApplication sharedApplication] connectedScenes];
            NSArray<UIScene *> *scenes = [connectedScenes allObjects];
            for (UIScene *scene in scenes) {
                if (scene.activationState == UISceneActivationStateForegroundActive && [scene isKindOfClass:[UIWindowScene class]]) {
                    UIWindowScene *windowScene = (UIWindowScene *)scene;
                    for (UIWindow *window in windowScene.windows) {
                        if (window.isKeyWindow) {
                            keyWindow = window;
                            break;
                        }
                    }
                }
            }
        } else {
            keyWindow = [UIApplication sharedApplication].keyWindow;
        }
        
        if (keyWindow) {
            [keyWindow addSubview:button];
            
            // Add tap gesture recognizer
            UITapGestureRecognizer* tapGesture = [[UITapGestureRecognizer alloc] initWithTarget:button action:@selector(handleTap:)];
            [button addGestureRecognizer:tapGesture];
            
            // Store the button and apply initial position (manual memory management)
            m_buttonView = (void*)button;
            [button retain]; // Explicitly retain the button since we're not using ARC
            UpdateButtonPosition();
            
            // Initially hidden
            button.hidden = YES;
        }
    }
    
    // Destructor
    FloatingButtonController::~FloatingButtonController() {
        if (m_buttonView) {
            FloatingButton* button = (FloatingButton*)m_buttonView;
            [button removeFromSuperview];
            [button release]; // Explicitly release since we're manually retaining
            m_buttonView = nullptr;
        }
    }
    
    // Update button position based on current settings
    void FloatingButtonController::UpdateButtonPosition() {
        if (!m_buttonView) return;
        
        FloatingButton* button = (__bridge FloatingButton*)m_buttonView;
        UIView* superView = button.superview;
        if (!superView) return;
        
        CGRect bounds = superView.bounds;
        CGFloat safeAreaTop = 0, safeAreaBottom = 0, safeAreaLeft = 0, safeAreaRight = 0;
        
        // Account for safe area (notch, etc.)
        if (@available(iOS 11.0, *)) {
            UIEdgeInsets safeArea = superView.safeAreaInsets;
            safeAreaTop = safeArea.top;
            safeAreaBottom = safeArea.bottom;
            safeAreaLeft = safeArea.left;
            safeAreaRight = safeArea.right;
        }
        
        // Calculate the new position
        CGPoint newCenter;
        CGFloat margin = 10.0f; // Margin from edges
        
        switch (m_position) {
            case Position::TopLeft:
                newCenter = CGPointMake(safeAreaLeft + button.frame.size.width/2 + margin,
                                       safeAreaTop + button.frame.size.height/2 + margin);
                break;
                
            case Position::TopRight:
                newCenter = CGPointMake(bounds.size.width - safeAreaRight - button.frame.size.width/2 - margin,
                                       safeAreaTop + button.frame.size.height/2 + margin);
                break;
                
            case Position::BottomLeft:
                newCenter = CGPointMake(safeAreaLeft + button.frame.size.width/2 + margin,
                                       bounds.size.height - safeAreaBottom - button.frame.size.height/2 - margin);
                break;
                
            case Position::BottomRight:
                newCenter = CGPointMake(bounds.size.width - safeAreaRight - button.frame.size.width/2 - margin,
                                       bounds.size.height - safeAreaBottom - button.frame.size.height/2 - margin);
                break;
                
            case Position::Custom:
                newCenter = CGPointMake(m_customX * bounds.size.width,
                                       m_customY * bounds.size.height);
                break;
        }
        
        // Animate the move
        [UIView animateWithDuration:0.3
                              delay:0
             usingSpringWithDamping:0.7
              initialSpringVelocity:0.5
                            options:UIViewAnimationOptionCurveEaseOut
                         animations:^{
                             button.center = newCenter;
                         }
                         completion:nil];
        
        // Save position for future sessions
        SavePosition();
    }
    
    // Save position to user defaults
    void FloatingButtonController::SavePosition() {
        NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
        
        // Save position enum
        [defaults setInteger:(NSInteger)m_position forKey:@"FloatingButton_Position"];
        
        // Save custom position
        [defaults setFloat:m_customX forKey:@"FloatingButton_CustomX"];
        [defaults setFloat:m_customY forKey:@"FloatingButton_CustomY"];
        
        // Save other settings
        [defaults setFloat:m_opacity forKey:@"FloatingButton_Opacity"];
        [defaults setFloat:m_size forKey:@"FloatingButton_Size"];
        [defaults setBool:m_isVisible forKey:@"FloatingButton_Visible"];
        
        [defaults synchronize];
    }
    
    // Load position from user defaults
    void FloatingButtonController::LoadPosition() {
        NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
        
        // Load position if available
        if ([defaults objectForKey:@"FloatingButton_Position"]) {
            m_position = (Position)[defaults integerForKey:@"FloatingButton_Position"];
        }
        
        // Load custom position
        if ([defaults objectForKey:@"FloatingButton_CustomX"]) {
            m_customX = [defaults floatForKey:@"FloatingButton_CustomX"];
        }
        
        if ([defaults objectForKey:@"FloatingButton_CustomY"]) {
            m_customY = [defaults floatForKey:@"FloatingButton_CustomY"];
        }
        
        // Load other settings
        if ([defaults objectForKey:@"FloatingButton_Opacity"]) {
            m_opacity = [defaults floatForKey:@"FloatingButton_Opacity"];
        }
        
        if ([defaults objectForKey:@"FloatingButton_Size"]) {
            m_size = [defaults floatForKey:@"FloatingButton_Size"];
        }
        
        if ([defaults objectForKey:@"FloatingButton_Visible"]) {
            m_isVisible = [defaults boolForKey:@"FloatingButton_Visible"];
        }
        
        // Apply loaded settings
        if (m_buttonView) {
            FloatingButton* button = (__bridge FloatingButton*)m_buttonView;
            button.alpha = m_opacity;
            button.hidden = !m_isVisible;
            
            // Resize button
            CGRect frame = button.frame;
            frame.size.width = m_size;
            frame.size.height = m_size;
            button.frame = frame;
            button.layer.cornerRadius = m_size / 2.0;
            
            UpdateButtonPosition();
        }
    }
    
    // Show the button
    void FloatingButtonController::Show() {
        if (!m_buttonView) return;
        
        FloatingButton* button = (__bridge FloatingButton*)m_buttonView;
        
        // Only animate if currently hidden
        if (button.hidden) {
            button.hidden = NO;
            button.transform = CGAffineTransformMakeScale(0.1, 0.1);
            button.alpha = 0;
            
            [UIView animateWithDuration:0.3
                                  delay:0
                 usingSpringWithDamping:0.7
                  initialSpringVelocity:0.5
                                options:UIViewAnimationOptionCurveEaseOut
                             animations:^{
                                 button.transform = CGAffineTransformIdentity;
                                 button.alpha = m_opacity;
                             }
                             completion:nil];
        }
        
        m_isVisible = true;
        SavePosition();
    }
    
    // Hide the button
    void FloatingButtonController::Hide() {
        if (!m_buttonView) return;
        
        FloatingButton* button = (__bridge FloatingButton*)m_buttonView;
        
        // Only animate if currently visible
        if (!button.hidden) {
            [UIView animateWithDuration:0.2
                             animations:^{
                                 button.transform = CGAffineTransformMakeScale(0.1, 0.1);
                                 button.alpha = 0;
                             }
                             completion:^(BOOL finished) {
                                 button.hidden = YES;
                                 button.transform = CGAffineTransformIdentity;
                             }];
        }
        
        m_isVisible = false;
        SavePosition();
    }
    
    // Toggle visibility
    bool FloatingButtonController::Toggle() {
        if (m_isVisible) {
            Hide();
        } else {
            Show();
        }
        return m_isVisible;
    }
    
    // Check visibility
    bool FloatingButtonController::IsVisible() const {
        return m_isVisible;
    }
    
    // Set position
    void FloatingButtonController::SetPosition(Position position) {
        m_position = position;
        UpdateButtonPosition();
    }
    
    // Set custom position
    void FloatingButtonController::SetCustomPosition(float x, float y) {
        m_customX = std::max(0.0f, std::min(1.0f, x));
        m_customY = std::max(0.0f, std::min(1.0f, y));
        m_position = Position::Custom;
        UpdateButtonPosition();
    }
    
    // Get position
    FloatingButtonController::Position FloatingButtonController::GetPosition() const {
        return m_position;
    }
    
    // Get custom X
    float FloatingButtonController::GetCustomX() const {
        return m_customX;
    }
    
    // Get custom Y
    float FloatingButtonController::GetCustomY() const {
        return m_customY;
    }
    
    // Set opacity
    void FloatingButtonController::SetOpacity(float opacity) {
        m_opacity = std::max(0.0f, std::min(1.0f, opacity));
        
        if (m_buttonView) {
            FloatingButton* button = (__bridge FloatingButton*)m_buttonView;
            button.alpha = m_opacity;
        }
        
        SavePosition();
    }
    
    // Get opacity
    // Implementation of performTapAction
    void FloatingButtonController::performTapAction() {
        if (m_tapCallback) {
            m_tapCallback();
        }
    }
    
    float FloatingButtonController::GetOpacity() const {
        return m_opacity;
    }
    
    // Set size
    void FloatingButtonController::SetSize(float size) {
        m_size = std::max(20.0f, std::min(100.0f, size));
        
        if (m_buttonView) {
            FloatingButton* button = (__bridge FloatingButton*)m_buttonView;
            
            CGRect frame = button.frame;
            frame.size.width = m_size;
            frame.size.height = m_size;
            button.frame = frame;
            button.layer.cornerRadius = m_size / 2.0;
            
            UpdateButtonPosition();
        }
        
        SavePosition();
    }
    
    // Get size
    float FloatingButtonController::GetSize() const {
        return m_size;
    }
    
    // Set tap callback
    void FloatingButtonController::SetTapCallback(TapCallback callback) {
        m_tapCallback = callback;
    }
    
    // Enable/disable dragging
    void FloatingButtonController::SetDraggable(bool enabled) {
        if (m_buttonView) {
            FloatingButton* button = (__bridge FloatingButton*)m_buttonView;
            button.draggable = enabled;
        }
    }
    
    // Check if being dragged
    bool FloatingButtonController::IsBeingDragged() const {
        return m_isBeingDragged;
    }
}

// Objective-C category extension to handle the tap gesture
@implementation FloatingButton (TapGesture)

- (void)handleTap:(UITapGestureRecognizer *)gesture {
    if (self.controller && self.controller->IsVisible()) {
        // Perform tap animation
        [UIView animateWithDuration:0.1
                         animations:^{
                             self.transform = CGAffineTransformMakeScale(0.9, 0.9);
                         }
                         completion:^(BOOL finished) {
                             [UIView animateWithDuration:0.1
                                              animations:^{
                                                  self.transform = CGAffineTransformIdentity;
                                              }
                                              completion:^(BOOL finished) {
                                                  // Call the tap callback
                                                  // Cast to id to avoid the warning about non-id receiver
                                                  if (self.controller) {
                                                      [(id)self.controller performTapAction];
                                                  }
                                              }];
                         }];
    }
}

@end
