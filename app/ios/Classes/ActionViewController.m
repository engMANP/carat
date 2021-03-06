//
//  ActionViewController.m
//  Carat
//
//  Created by Adam Oliner on 2/7/12.
//  Copyright (c) 2012 UC Berkeley. All rights reserved.
//

#import "ActionViewController.h"
#import "Utilities.h"
#import "ActionItemCell.h"
#import "UIImageDoNotCache.h"
#import "InstructionViewController.h"
#import "FlurryAnalytics.h"
#import "ActionObject.h"
#import "SHK.h"
#import "CoreDataManager.h"
#import "Reachability.h"

@implementation ActionViewController

@synthesize actionList, actionTable;

- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil
{
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if (self) {
        self.title = @"Actions";
        self.tabBarItem.image = [UIImage imageNamed:@"53-house"];
    }
    return self;
}

- (void)didReceiveMemoryWarning
{
    DLog(@"Memory warning.");
    // Releases the view if it doesn't have a superview.
    [super didReceiveMemoryWarning];
}

#pragma mark - Data management

- (void)loadDataWithHUD:(id)obj {
    [self loadDataWithHUD];
}

- (void)loadDataWithHUD
{
    if ([[CoreDataManager instance] getReportUpdateStatus] != nil) {
        // update in progress, only update footer
        [self.actionTable reloadData];
        [self.view setNeedsDisplay];
    } else {
        // *probably* no update in progress, reload table data while locking out view
        HUD = [[MBProgressHUD alloc] initWithView:self.tabBarController.view];
        [self.tabBarController.view addSubview:HUD];
        
        HUD.dimBackground = YES;
        
        // Register for HUD callbacks so we can remove it from the window at the right time
        HUD.delegate = self;
        HUD.labelText = @"Updating Action List";
        
        [HUD showWhileExecuting:@selector(loadData)
                       onTarget:self
                     withObject:nil
                       animated:YES];
    }
}

- (void)loadData
{    
    [self updateView];
    
    // The checkmark image is based on the work by http://www.pixelpressicons.com, http://creativecommons.org/licenses/by/2.5/ca/
//    UIImage *icon = [UIImage newImageNotCached:@"37x-Checkmark.png"];
//    UIImageView *imgView = [[UIImageView alloc] initWithImage:icon];
//    HUD.customView = imgView;
//    [HUD setMode:MBProgressHUDModeCustomView];
//    HUD.labelText = @"List Update Complete";
//    [icon release];
//    [imgView release];
//    sleep(1);
}

- (BOOL) isFresh
{
    return [[CoreDataManager instance] secondsSinceLastUpdate] < 600; // 600 == 10 minutes
}

#pragma mark - MBProgressHUDDelegate method

- (void)hudWasHidden:(MBProgressHUD *)hud
{
    // Remove HUD from screen when the HUD was hidded
    [HUD removeFromSuperview];
    [HUD release];
	HUD = nil;
}


#pragma mark - table methods

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return [actionList count];
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
    return @"To improve battery life...";
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *CellIdentifier = @"ActionItemCell";
    
    ActionItemCell *cell = [tableView dequeueReusableCellWithIdentifier:CellIdentifier];
    if (cell == nil) {
        NSArray *topLevelObjects = [[NSBundle mainBundle] loadNibNamed:@"ActionItemCell" owner:nil options:nil];
        for (id currentObject in topLevelObjects) {
            if ([currentObject isKindOfClass:[ActionItemCell class]]) {
                cell = (ActionItemCell *)currentObject;
                break;
            }
        }
    }
    
    // Set up the cell...
    ActionObject *act = [self.actionList objectAtIndex:indexPath.row];
    cell.actionString.text = act.actionText;
    if (act.actionBenefit <= 0) { // already filtered out benefits < 60 seconds
        cell.actionValue.text = @"+100 karma!";
        cell.actionType = ActionTypeSpreadTheWord;
    } else {
        cell.actionValue.text = [Utilities formatNSTimeIntervalAsNSString:[[NSNumber numberWithInt:act.actionBenefit] doubleValue]];
        cell.actionType = act.actionType;
    }
    
    return cell;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section
{
    NSString *tmpStatus = [[CoreDataManager instance] getReportUpdateStatus];
    if (tmpStatus == nil) {
        return [Utilities formatNSTimeIntervalAsUpdatedNSString:[[NSDate date] timeIntervalSinceDate:[[CoreDataManager instance] getLastReportUpdateTimestamp]]];
    } else {
        return tmpStatus;
    }
}

// loads the selected detail view
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    ActionItemCell *selectedCell = (ActionItemCell *)[tableView cellForRowAtIndexPath:indexPath];
    [selectedCell setSelected:NO animated:YES];
    
    if (selectedCell.actionType == ActionTypeSpreadTheWord) {
        [self shareHandler];
    } else {
        InstructionViewController *ivController = [[InstructionViewController alloc] initWithNibName:@"InstructionView" actionType:selectedCell.actionType];
        [self.navigationController pushViewController:ivController animated:YES];
        [ivController release];
        [FlurryAnalytics logEvent:@"selectedInstructionView"];
    }
}

#pragma mark - reachability

- (void) setupReachabilityNotifications
{
    [[NSNotificationCenter defaultCenter] addObserver:self 
                                             selector:@selector(checkForUpdatable:) 
                                                 name:kReachabilityChangedNotification 
                                               object:nil];
    internetReachable = [Reachability reachabilityWithHostName:@"server.caratproject.com"];
    if ([internetReachable startNotifier]) { DLog(@"%s Success!", __PRETTY_FUNCTION__); }
}

- (void) teardownReachabilityNotifications
{
    [[NSNotificationCenter defaultCenter] removeObserver:self
                                                name:kReachabilityChangedNotification
                                              object:nil];
    [internetReachable stopNotifier];
}

- (void) checkForUpdatable:(NSNotification *) notice
{
    DLog(@"%s", __PRETTY_FUNCTION__);
    NetworkStatus internetStatus = [internetReachable currentReachabilityStatus];
    switch (internetStatus)
    {
        case NotReachable:
        {
            break;
        }
        case ReachableViaWiFi:
        case ReachableViaWWAN:
        {
            DLog(@"Checking if update needed with new reachability status...");
            if (![self isFresh] && // need to update
                [[CoreDataManager instance] getReportUpdateStatus] == nil) // not already updating
            {
                DLog(@"Update possible; initiating.");
                [[CoreDataManager instance] updateLocalReportsFromServer];
            }
            break;
        }
    }

}

#pragma mark - share handler

- (void)shareHandler {
//    UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Temporarily Disabled" 
//                                                    message:@"This feature is disabled while Carat is in beta." 
//                                                   delegate:nil 
//                                          cancelButtonTitle:@"OK"
//                                          otherButtonTitles:nil];
//    [alert show];
//    [alert release];

    // Create the item to share (in this example, a url)
    NSURL *url = [NSURL URLWithString:@"http://carat.cs.berkeley.edu"];
    SHKItem *item = [SHKItem URL:url title:[[@"My J-Score is "
             stringByAppendingString:[[NSNumber numberWithInt:(int)(MIN( MAX([[CoreDataManager instance] getJScore], -1.0), 1.0)*100)] stringValue]]
             stringByAppendingString:@". Find out yours and improve your battery life!"]];
                                            
    // Get the ShareKit action sheet
    SHKActionSheet *actionSheet = [SHKActionSheet actionSheetForItem:item];
       
    // Display the action sheet
    [actionSheet showFromTabBar:self.tabBarController.tabBar];
    
    [FlurryAnalytics logEvent:@"selectedSpreadTheWord"];
}


#pragma mark - View lifecycle

- (void)viewDidLoad
{
    [super viewDidLoad];
    // Do any additional setup after loading the view from its nib.
    [self updateView];
}

- (void)viewDidUnload
{
    [HUD release];
    [actionList release];
    [self setActionList:nil];
    [actionTable release];
    [self setActionTable:nil];
    [super viewDidUnload];
    // Release any retained subviews of the main view.
    // e.g. self.myOutlet = nil;
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    
    [self.navigationController setNavigationBarHidden:YES animated:YES];
    
    // UPDATE REPORT DATA
    if ([[CommunicationManager instance] isInternetReachable] == YES && // online
        ![self isFresh] && // need to update
        [[CoreDataManager instance] getReportUpdateStatus] == nil) // not already updating
    {
        [[CoreDataManager instance] updateLocalReportsFromServer];
    } else if ([[CommunicationManager instance] isInternetReachable] == NO) {
        DLog(@"Starting without reachability; setting notification.");
        [self setupReachabilityNotifications];
    }
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    
    if ([[CoreDataManager instance] getReportUpdateStatus] == nil) {
        // For this screen, let's put sending samples/registrations here so that we don't conflict
        // with the report syncing (need to limit memory/CPU/thread usage so that we don't get killed).
        [[CoreDataManager instance] checkConnectivityAndSendStoredDataToServer];
    }
    
    [self loadDataWithHUD];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(loadDataWithHUD:) 
                                                 name:@"CCDMReportUpdateStatusNotification"
                                               object:nil];
}

- (void)viewWillDisappear:(BOOL)animated
{
	[super viewWillDisappear:animated];
    
    [[NSNotificationCenter defaultCenter] removeObserver:self
                                            name:@"CCDMReportUpdateStatusNotification" object:nil];
    [self teardownReachabilityNotifications];
    [self.navigationController setNavigationBarHidden:NO animated:YES];
}

- (void)viewDidDisappear:(BOOL)animated
{
	[super viewDidDisappear:animated];
}

- (BOOL) shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)orientation {
    return YES;
}

- (void)updateView {
    NSMutableArray *myList = [[[NSMutableArray alloc] init] autorelease];
    
    ActionObject *tmpAction;
    
    DLog(@"Loading Hogs");
    // get Hogs, filter negative actionBenefits, fill mutable array
    NSArray *tmp = [[CoreDataManager instance] getHogs:YES].hbList;
    if (tmp != nil) {
        for (HogsBugs *hb in tmp) {
            if ([hb appName] != nil &&
                [hb expectedValue] > 0 &&
                [hb expectedValueWithout] > 0) {
                
                NSInteger benefit = (int) (100/[hb expectedValueWithout] - 100/[hb expectedValue]);
                DLog(@"Benefit is %d for hog '%@'", benefit, [hb appName]);
                if (benefit > 60) {
                    tmpAction = [[ActionObject alloc] init];
                    [tmpAction setActionText:[@"Kill " stringByAppendingString:[hb appName]]];
                    [tmpAction setActionType:ActionTypeKillApp];
                    [tmpAction setActionBenefit:benefit];
                    [myList addObject:tmpAction];
                    [tmpAction release];
                }
            }
        }
    }
    
    DLog(@"Loading Bugs");
    // get Bugs, add to array
    tmp = [[CoreDataManager instance] getBugs:YES].hbList;
    if (tmp != nil) {
        for (HogsBugs *hb in tmp) {
            if ([hb appName] != nil &&
                [hb expectedValue] > 0 &&
                [hb expectedValueWithout] > 0) {
                
                NSInteger benefit = (int) (100/[hb expectedValueWithout] - 100/[hb expectedValue]);
                DLog(@"Benefit is %d for bug '%@'", benefit, [hb appName]);
                if (benefit > 60) {
                    tmpAction = [[ActionObject alloc] init];
                    [tmpAction setActionText:[@"Restart " stringByAppendingString:[hb appName]]];
                    [tmpAction setActionType:ActionTypeRestartApp];
                    [tmpAction setActionBenefit:benefit];
                    [myList addObject:tmpAction];
                    [tmpAction release];
                }
            }
        }
    }
    
    DLog(@"Loading OS");
    // get OS
    DetailScreenReport *dscWith = [[[CoreDataManager instance] getOSInfo:YES] retain];
    DetailScreenReport *dscWithout = [[[CoreDataManager instance] getOSInfo:NO] retain];
    
    if (dscWith != nil && dscWithout != nil) {
        if (dscWith.expectedValue > 0 &&
            dscWithout.expectedValue > 0) {
            NSInteger benefit = (int) (100/dscWithout.expectedValue - 100/dscWith.expectedValue);
            DLog(@"OS benefit is %d", benefit);
            if (benefit > 60) {
                tmpAction = [[ActionObject alloc] init];
                [tmpAction setActionText:@"Upgrade the Operating System"];
                [tmpAction setActionType:ActionTypeUpgradeOS];
                [tmpAction setActionBenefit:benefit];
                [myList addObject:tmpAction];
                [tmpAction release];
            }
        }
    }
    
    [dscWith release];
    [dscWithout release];

    DLog(@"Loading Action");
    // sharing Action
    tmpAction = [[ActionObject alloc] init];
    [tmpAction setActionText:@"Help Spread the Word!"];
    [tmpAction setActionType:ActionTypeSpreadTheWord];
    [tmpAction setActionBenefit:-1];
    [myList addObject:tmpAction];
    [tmpAction release];
    
    //the "key" is the *name* of the @property as a string.  So you can also sort by @"label" if you'd like
    [myList sortUsingDescriptors:[NSArray arrayWithObject:[NSSortDescriptor sortDescriptorWithKey:@"actionBenefit" ascending:NO]]];
    
    [self setActionList:myList];
    [self.actionTable reloadData];
    [self.view setNeedsDisplay];
}

- (void)dealloc {
    [HUD release];
    [actionList release];
    [actionTable release];
    [internetReachable release];
    [super dealloc];
}
@end






