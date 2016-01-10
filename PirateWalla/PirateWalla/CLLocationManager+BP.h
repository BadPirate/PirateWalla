//
//  CLLocationManager+BP.h
//  drunkcircle
//
//  Created by Kevin Lohman on 8/17/14.
//  Copyright (c) 2014 Logic High. All rights reserved.
//

#import <CoreLocation/CoreLocation.h>

typedef void(^BPLocationHandler)( CLLocation * _Nullable location, NSError * _Nullable error);

@interface CLLocationManager (BP)
/***
 *  Often times you just want the location, not continous updates, etc.  This method will attempt to get permission
 *  From the user to get their location, and if able to obtain permission, return that value (or an error).
 *  @param requestReason String to use with alert prior to requesting permission for users location, if not already provided.
 *  @param completionHandler method will always be called upon success or failure
 */
+ (void)getCurrentLocationAlways:(BOOL)always completion:(_Nonnull BPLocationHandler)completionHandler;
+ (CLLocation * _Nullable)lastLocation;
@end
