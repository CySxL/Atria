#import <UIKit/UIKit.h>

typedef NS_ENUM(NSInteger, ARICategoryEditorMode) {
    ARICategoryEditorModeApps,
    ARICategoryEditorModeOrder,
};

@interface ARICategoryEditorController : UITableViewController
- (instancetype)initWithMode:(ARICategoryEditorMode)mode;
@end
