//
//  AWVersionAgent.h
//  AWVersionAgent
//
//  Created by Heyward Fann on 1/31/13.
//  Copyright (c) 2013 Appwill. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "MMInterface.h"

#define UPDATE_FOR_APPSTORE 1
#define UPDATE_FOR_MYSERVER 2

@interface AWVersionAgent : NSObject<InterfaceDelegate,UIAlertViewDelegate>

+ (AWVersionAgent *)sharedAgent;

@property (nonatomic) BOOL debug;

//1. 走appstore, 2走我们的服务器
@property (nonatomic,assign) int updateType;

-(void)checkNewVersion;

@end
