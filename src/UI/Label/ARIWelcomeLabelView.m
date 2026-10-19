//
// Created by ren7995 on 2023-05-30 18:39:12
// Copyright (c) 2023 ren7995. All rights reserved.
//

#import "ARIWelcomeLabelView.h"
#import "../../Manager/ARITweakManager.h"

#import <objc/runtime.h>

static NSString *const ARIGeocodeCachePath = @"/var/mobile/Documents/locationQueryGeocodeCacheFolder";

@implementation ARIWelcomeLabelView {
    NSCalendar *_calendar;
    NSTimer *_updateTimer;
    UIImageView *_imageView;
    WALockscreenWidgetViewController *_weatherUpdater;
    NSDate *_lastWeatherFetch;
}

- (instancetype)init {
    self = [super init];
    if(self) {
        _calendar = [[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierGregorian];

        [self _startUpdateTimer];

        // System time was set listener
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(updateText:) name:NSSystemClockDidChangeNotification object:nil];

        // Notification for showing/hiding label
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(updateLabelVisibility:) name:ARIUpdateLabelVisibilityNotification object:nil];

        [self _updateWeatherUpdater];
    }
    return self;
}

- (void)_startUpdateTimer {
    if([_updateTimer isValid]) return;
    __weak __typeof(self) weakSelf = self;
    _updateTimer = [NSTimer scheduledTimerWithTimeInterval:60
                                                   repeats:YES
                                                     block:^(NSTimer *timer) {
                                                         __typeof(self) strongSelf = weakSelf;
                                                         if(!strongSelf) {
                                                             [timer invalidate];
                                                             return;
                                                         }
                                                         [strongSelf _refreshWeatherIfDue];
                                                         [strongSelf updateText:timer];
                                                     }];
}

// removeFromSuperview stops the timer, and the same label can be added back
- (void)didMoveToSuperview {
    [super didMoveToSuperview];
    if(self.superview) [self _startUpdateTimer];
}

- (BOOL)_needsWeather {
    ARITweakManager *manager = [ARITweakManager sharedInstance];
    if([manager boolValueForKey:@"showWeatherIcon"]) return YES;

    NSString *text = [manager stringValueForKey:@"labelText"];
    return [text containsString:@"%TEMPERATURE%"] || [text containsString:@"%LOCATION%"];
}

- (void)_updateWeatherUpdater {
    if(![self _needsWeather]) {
        _weatherUpdater = nil;
        _lastWeatherFetch = nil;
        [self _purgeGeocodeCache];
        return;
    }

    if(_weatherUpdater) return;
    _weatherUpdater = [[objc_getClass("WALockscreenWidgetViewController") alloc] init];
    _lastWeatherFetch = [NSDate date];
    [_weatherUpdater updateWeather];
}

- (void)_refreshWeatherIfDue {
    if(!_weatherUpdater) return;

    NSInteger minutes = [[ARITweakManager sharedInstance] intValueForKey:@"weatherRefreshInterval"];
    if(minutes <= 0) return;
    if(_lastWeatherFetch && [[NSDate date] timeIntervalSinceDate:_lastWeatherFetch] < minutes * 60) return;

    _lastWeatherFetch = [NSDate date];
    [_weatherUpdater updateWeather];
}

- (void)_purgeGeocodeCache {
    static dispatch_once_t token;
    dispatch_once(&token, ^{
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
            NSFileManager *manager = [NSFileManager defaultManager];
            if([manager fileExistsAtPath:ARIGeocodeCachePath])
                [manager removeItemAtPath:ARIGeocodeCachePath error:nil];
        });
    });
}

- (void)setupTextField:(UITextField *)textField {
    _imageView = [[UIImageView alloc] init];
    _imageView.translatesAutoresizingMaskIntoConstraints = NO;
    [NSLayoutConstraint activateConstraints:@[
        [_imageView.widthAnchor constraintEqualToConstant:30],
        [_imageView.heightAnchor constraintEqualToConstant:30],
    ]];

    textField.leftView = _imageView;
}

- (NSString *)loadRawText {
    return [[ARITweakManager sharedInstance] stringValueForKey:@"labelText"];
}

- (NSString *)processRawText:(NSString *)rawText isScheduledUpdate:(BOOL)scheduled {
    NSString *greeting = @"Welcome";
    NSDateComponents *components = [_calendar components:NSCalendarUnitHour fromDate:[NSDate date]];
    if(components.hour >= 4 && components.hour < 12) {
        greeting = @"Good morning";
    } else if(components.hour >= 12 && components.hour < 18) {
        greeting = @"Good afternoon";
    } else if(components.hour >= 18 || components.hour < 4) {
        greeting = @"Good evening";
    }

    rawText = [rawText stringByReplacingOccurrencesOfString:@"\%GREETING\%" withString:greeting];
    rawText = [rawText stringByReplacingOccurrencesOfString:@"\%TEMPERATURE\%" withString:[_weatherUpdater _temperature] ?: @"--"];
    rawText = [rawText stringByReplacingOccurrencesOfString:@"\%LOCATION\%" withString:[_weatherUpdater _locationName] ?: @"Unknown"];
    _imageView.image = [_weatherUpdater _conditionsImage];
    return rawText;
}

- (void)saveTextValue:(NSString *)text {
    [[ARITweakManager sharedInstance] setValue:text forKey:@"labelText"];
    [self _updateWeatherUpdater];
}

- (void)updateView {
    [super updateView];
    [self _updateWeatherUpdater];
    self.textField.leftViewMode = [[ARITweakManager sharedInstance] boolValueForKey:@"showWeatherIcon"]
                                      ? UITextFieldViewModeAlways // UnlessEditing
                                      : UITextFieldViewModeNever;
}

- (void)removeFromSuperview {
    [super removeFromSuperview];
    [_updateTimer invalidate];
}

- (void)dealloc {
    [_updateTimer invalidate];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

@end