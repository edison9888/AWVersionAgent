//
//  AWVersionAgent.m
//  AWVersionAgent
//
//  Created by Heyward Fann on 1/31/13.
//  Copyright (c) 2013 Appwill. All rights reserved.
//

#import "AWVersionAgent.h"

#import "JSONKit.h"



#define kAppleLookupURLTemplate     @"http://itunes.apple.com/lookup?id=%@"
#define kAppStoreURLTemplate        @"itms-apps://itunes.apple.com/app/id%@"

#define kUpgradeAlertMessage    @"New version is released, current version: %@, new version: %@. Get it from App Store right now."
#define kUpgradeAlertAction     @"kUpgradeAlertAction"
#define kUpgradeAlertDelay      3

#define kAWVersionAgentLastNotificationDateKey      @"lastNotificationDate"
#define kAWVersionAgentLastCheckVersionDateKey      @"lastCheckVersionDate"

@interface AWVersionAgent ()

@property (nonatomic, copy) NSString *appid;
@property (nonatomic) BOOL newVersionAvailable;

@end

@implementation AWVersionAgent

+ (AWVersionAgent *)sharedAgent
{
    static AWVersionAgent *sharedAgent = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedAgent = [[AWVersionAgent alloc] init];
    });

    return sharedAgent;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [super dealloc];
}

- (id)init
{
    self = [super init];
    if (self) {
        _newVersionAvailable = NO;
        _debug = NO;
        
        NSDictionary* infoDict = [[NSBundle mainBundle] infoDictionary];
        NSString* AppChannelID = [infoDict objectForKey:@"AppChannelID"];
        NSString* AppStoreId = [infoDict objectForKey:@"AppStoreId"];
        self.appid = AppStoreId;
        
        if ([AppChannelID isEqualToString:@"1"]) {
            //查询appstore是否有更新
            self.updateType = UPDATE_FOR_APPSTORE   ;
        } else {
            self.updateType = UPDATE_FOR_MYSERVER   ;
        }

        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(showUpgradeNotification)
                                                     name:UIApplicationDidEnterBackgroundNotification
                                                   object:nil];
    }

    return self;
}

-(void)showUpdateAlert {
    NSString *url = [Api loadRms:@"kAppNewVersionUrl"];
    
    if ([url length]>10){
    NSDictionary* infoDict = [[NSBundle mainBundle] infoDictionary];
    NSString* appName = [infoDict objectForKey:@"CFBundleDisplayName"];
    NSString *msg = [NSString stringWithFormat:@"%@有新版本，是否去更新？",appName];
    
    UIAlertView *alertView = [[UIAlertView alloc] initWithTitle:@"升级提醒"
                                                        message:msg
                                                       delegate:self
                                              cancelButtonTitle:@"升级"
                                              otherButtonTitles:@"下次再说", nil];
    
    [alertView show];
    }
}

- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex {
    
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    [defaults setDouble:now forKey:kAWVersionAgentLastNotificationDateKey];
    [defaults synchronize];
    NSString *url = [Api loadRms:@"kAppNewVersionUrl"];
    [Api saveRms:@"kAppNewVersionUrl" value:@""];
    [Api saveAll];
    
    if (buttonIndex==0) {//升级
        [[UIApplication sharedApplication] openURL:[NSURL URLWithString:url]];
    }
    
}

-(void)checkNewVersion {
    [self showUpdateAlert];
    if (self.updateType == UPDATE_FOR_APPSTORE) {
        if ([self.appid length]>3) {
            [self checkNewVersionForApp:self.appid];
        }
    } else {
        MMInterface *it = [[[MMInterface alloc]initWithDelegate:self]autorelease];
        [it getNewestVersionInfo];
    }
}

-(void)onSuccess:(NSDictionary *)data tag:(int)tag {
    if (tag == getNewestVersionInfo_TAG) {
        int hashCode = [data getIntValueForKey:@"ipaversion"];
        NSString *appVersion = [Api loadRms:@"app_version"];
        int oldHashCode = [Api hashCode:appVersion];
        NSLog(@"oldHashCode = %d,hashCode=%d, appVersion=%@",oldHashCode,hashCode,appVersion);
        
        NSString *new_version_url = @"";
        if (oldHashCode != hashCode) {
            new_version_url = [data getStringValueForKey:@"ipaurl" def:@""];
            [[NSUserDefaults standardUserDefaults] setObject:[NSString stringWithFormat:@"itms-services://?action=download-manifest&url=%@", new_version_url]
                                                      forKey:@"kAppNewVersionUrl"];
            [[NSUserDefaults standardUserDefaults] synchronize];
            self.newVersionAvailable = YES;
        }
    }
}

- (void)checkNewVersionForApp:(NSString *)appid
{
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSString *url = [NSString stringWithFormat:kAppleLookupURLTemplate, self.appid];
        NSData *data = [NSData dataWithContentsOfURL:[NSURL URLWithString:url]];
        if (data && [data length]>0) {
            id obj = [data objectFromJSONData];
            if (obj && [obj isKindOfClass:[NSDictionary class]]) {
                NSDictionary *dict = (NSDictionary *)obj;
                NSArray *array = dict[@"results"];
                if (array && [array count]>0) {
                    NSDictionary *app = array[0];
                    NSString *newVersion = app[@"version"];
                    [[NSUserDefaults standardUserDefaults] setObject:newVersion
                                                              forKey:@"kAppNewVersion"];
                    [[NSUserDefaults standardUserDefaults] synchronize];
                    NSString *curVersion = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleVersion"];
                    if (newVersion && curVersion && ![newVersion isEqualToString:curVersion]) {
                        self.newVersionAvailable = YES;
                    }
                }
            }
        }
    });
}

- (BOOL)conditionHasBeenMet
{
    if (_debug) {
        return YES;
    }

    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSTimeInterval last = [defaults doubleForKey:kAWVersionAgentLastNotificationDateKey];
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    if (last <= 0) {
        [defaults setDouble:now forKey:kAWVersionAgentLastNotificationDateKey];
        [defaults synchronize];

        return NO;
    }
    if (now - last < 60*60*24) {
        return NO;
    }

    return _newVersionAvailable;
}

- (void)showUpgradeNotification {
    if ([self conditionHasBeenMet]) {
        NSString *newVersionUrl = [[NSUserDefaults standardUserDefaults] objectForKey:@"kAppNewVersionUrl"];
        if (self.updateType==UPDATE_FOR_APPSTORE) {
            newVersionUrl = [NSString stringWithFormat:kAppStoreURLTemplate, self.appid];
        }
        
        [Api saveRms:@"kAppNewVersionUrl" value:newVersionUrl];
        NSLog(@"newVersinUrl = %@",newVersionUrl);
        [Api saveAll];
    }
}


@end
