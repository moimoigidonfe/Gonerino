#import "CustomSettings.h"

#import "ChangelogData.h"
#import "Localization.h"
#import "Settings.h"
#import "Util.h"

static void RequestPortraitOrientation(UIViewController *viewController)
{
    UIWindowScene *scene = viewController.view.window.windowScene;
    if (!scene)
        return;

    if (@available(iOS 16.0, *))
    {
        UIWindowSceneGeometryPreferencesIOS *preferences =
            [[UIWindowSceneGeometryPreferencesIOS alloc]
                initWithInterfaceOrientations:UIInterfaceOrientationMaskPortrait];
        [scene requestGeometryUpdateWithPreferences:preferences errorHandler:nil];
    }
}

static void ShowToast(UIViewController *viewController, NSString *message)
{
    [Util showToast:message fromView:viewController.view];
}

static UIImage *GonerinoDiscordImage(void)
{
    NSString *path = [[[NSBundle mainBundle] pathForResource:@"Gonerino" ofType:@"bundle"]
        stringByAppendingPathComponent:@"discord.png"];
    if (![[NSFileManager defaultManager] fileExistsAtPath:path])
        path = @"/Library/Application Support/Gonerino.bundle/discord.png";
    if (![[NSFileManager defaultManager] fileExistsAtPath:path])
        path = @"/var/jb/Library/Application Support/Gonerino.bundle/discord.png";
    UIImage *image = [UIImage imageWithContentsOfFile:path];
    if (!image)
        return nil;
    UIGraphicsImageRenderer *renderer =
        [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(28.0, 28.0)];
    return [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
        [image drawInRect:CGRectMake(0.0, 0.0, 28.0, 28.0)];
    }];
}

static UIButton *NavigationBackButton(NSString *title, id target, SEL action)
{
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    if (@available(iOS 15.0, *))
    {
        UIButtonConfiguration *configuration = [UIButtonConfiguration plainButtonConfiguration];
        configuration.image                  = [UIImage systemImageNamed:@"chevron.backward"];
        configuration.title                  = title;
        configuration.imagePadding           = 4.0;
        configuration.contentInsets          = NSDirectionalEdgeInsetsMake(0.0, 12.0, 0.0, 12.0);
        button.configuration                 = configuration;
    }
    else
    {
        [button setImage:[UIImage systemImageNamed:@"chevron.backward"]
                forState:UIControlStateNormal];
        [button setTitle:title forState:UIControlStateNormal];
        button.imageEdgeInsets   = UIEdgeInsetsMake(0.0, 0.0, 0.0, 4.0);
        button.contentEdgeInsets = UIEdgeInsetsMake(0.0, 12.0, 0.0, 12.0);
    }
    button.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
    button.frame = CGRectMake(0.0, 0.0, MAX(44.0, button.intrinsicContentSize.width), 44.0);
    button.accessibilityLabel = title;
    [button addTarget:target action:action forControlEvents:UIControlEventTouchUpInside];
    return button;
}


static void PresentTextInputAlert(UIViewController *presenter, NSString *title, NSString *message,
                                  NSString *placeholder, void (^completion)(NSString *text))
{
    UIAlertController *alert =
        [UIAlertController alertControllerWithTitle:title
                                            message:message
                                     preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.placeholder            = placeholder;
        textField.autocapitalizationType = UITextAutocapitalizationTypeNone;
        textField.autocorrectionType     = UITextAutocorrectionTypeNo;
    }];
    __weak UIAlertController *weakAlert = alert;
    [alert addAction:[UIAlertAction
                         actionWithTitle:LocalizedString(@"Add")
                                   style:UIAlertActionStyleDefault
                                 handler:^(__unused UIAlertAction *action) {
                                     NSString *text = [weakAlert.textFields.firstObject.text
                                         stringByTrimmingCharactersInSet:
                                             [NSCharacterSet whitespaceAndNewlineCharacterSet]];
                                     if (text.length > 0 && completion)
                                         completion(text);
                                 }]];
    [alert addAction:[UIAlertAction actionWithTitle:LocalizedString(@"Cancel")
                                              style:UIAlertActionStyleCancel
                                            handler:nil]];
    [presenter presentViewController:alert animated:YES completion:nil];
}

static NSString *ChannelKindDescription(NSString *entry)
{
    switch ([ChannelManager kindOfEntry:entry])
    {
        case GNRChannelEntryKindID:
            return LocalizedString(@"Channel ID");
        case GNRChannelEntryKindHandle:
            return LocalizedString(@"Handle");
        default:
            return LocalizedString(@"Name (legacy)");
    }
}

@interface                                   SettingsEntry : NSObject
@property (nonatomic, copy) NSString        *title;
@property (nonatomic, copy) NSString        *subtitle;
@property (nonatomic, copy) dispatch_block_t action;
@property (nonatomic, copy) dispatch_block_t deleteAction;
+ (instancetype)entryWithTitle:(NSString *)title
                      subtitle:(NSString *)subtitle
                        action:(dispatch_block_t)action;
+ (instancetype)entryWithTitle:(NSString *)title
                      subtitle:(NSString *)subtitle
                  deleteAction:(dispatch_block_t)deleteAction;
+ (instancetype)entryWithTitle:(NSString *)title
                      subtitle:(NSString *)subtitle
                        action:(dispatch_block_t)action
                  deleteAction:(dispatch_block_t)deleteAction;
@end

@implementation SettingsEntry

+ (instancetype)entryWithTitle:(NSString *)title
                      subtitle:(NSString *)subtitle
                        action:(dispatch_block_t)action
{
    return [self entryWithTitle:title subtitle:subtitle action:action deleteAction:nil];
}

+ (instancetype)entryWithTitle:(NSString *)title
                      subtitle:(NSString *)subtitle
                  deleteAction:(dispatch_block_t)deleteAction
{
    SettingsEntry *entry = [self new];
    entry.title          = title ?: @"";
    entry.subtitle       = subtitle;
    entry.deleteAction   = deleteAction;
    return entry;
}

+ (instancetype)entryWithTitle:(NSString *)title
                      subtitle:(NSString *)subtitle
                        action:(dispatch_block_t)action
                  deleteAction:(dispatch_block_t)deleteAction
{
    SettingsEntry *entry = [self new];
    entry.title          = title ?: @"";
    entry.subtitle       = subtitle;
    entry.action         = action;
    entry.deleteAction   = deleteAction;
    return entry;
}

@end

@interface SettingsListViewController : UITableViewController <UISearchBarDelegate>
@property (nonatomic, copy) NSArray<SettingsEntry *> * (^entriesProvider)(void);
@property (nonatomic, copy) NSString                 *searchPlaceholder;
@property (nonatomic, copy) NSArray<SettingsEntry *> *entries;
@property (nonatomic, copy) NSArray<SettingsEntry *> *filteredEntries;
@property (nonatomic, strong) UISearchBar            *searchBar;
- (instancetype)initWithTitle:(NSString *)title
            searchPlaceholder:(NSString *)searchPlaceholder
              entriesProvider:(NSArray<SettingsEntry *> * (^)(void) )entriesProvider;
- (void)refreshEntries;
@end

@implementation SettingsListViewController

- (UIInterfaceOrientationMask)supportedInterfaceOrientations
{
    return UIInterfaceOrientationMaskPortrait;
}

- (UIInterfaceOrientation)preferredInterfaceOrientationForPresentation
{
    return UIInterfaceOrientationPortrait;
}

- (BOOL)shouldAutorotate
{
    return YES;
}

- (instancetype)initWithTitle:(NSString *)title
            searchPlaceholder:(NSString *)searchPlaceholder
              entriesProvider:(NSArray<SettingsEntry *> * (^)(void) )entriesProvider
{
    self = [super initWithStyle:UITableViewStyleInsetGrouped];
    if (self)
    {
        self.title         = title;
        _searchPlaceholder = [searchPlaceholder copy];
        _entriesProvider   = [entriesProvider copy];
        _entries           = @[];
        _filteredEntries   = @[];
    }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    self.tableView.rowHeight           = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight  = 56.0;

    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;
    self.navigationItem.hidesBackButton       = YES;
    self.navigationItem.leftBarButtonItem     = [[UIBarButtonItem alloc]
        initWithCustomView:NavigationBackButton(LocalizedString(@"Gonerino"), self,
                                                @selector(returnToSettingsPage))];
    self.searchBar                            = [UISearchBar new];
    self.searchBar.placeholder                = self.searchPlaceholder;
    self.searchBar.searchBarStyle             = UISearchBarStyleMinimal;
    self.searchBar.delegate                   = self;
    self.searchBar.frame            = CGRectMake(0.0, 0.0, self.tableView.bounds.size.width, 56.0);
    self.searchBar.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    self.tableView.tableHeaderView  = self.searchBar;
    [self refreshEntries];
}

- (void)viewDidLayoutSubviews
{
    [super viewDidLayoutSubviews];
    CGRect frame      = self.searchBar.frame;
    frame.size.width  = self.tableView.bounds.size.width;
    frame.size.height = 56.0;
    if (!CGRectEqualToRect(frame, self.searchBar.frame))
    {
        self.searchBar.frame           = frame;
        self.tableView.tableHeaderView = self.searchBar;
    }
}

- (void)returnToSettingsPage
{
    [self.navigationController popViewControllerAnimated:YES];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    RequestPortraitOrientation(self);
    [self refreshEntries];
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    RequestPortraitOrientation(self);
}

- (void)refreshEntries
{
    self.entries    = self.entriesProvider ? self.entriesProvider() : @[];
    NSString *query = self.searchBar.text;
    if (query.length == 0)
    {
        self.filteredEntries = self.entries;
    }
    else
    {
        NSString *normalizedQuery = query.lowercaseString;
        self.filteredEntries      = [self.entries
            filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(
                                                         SettingsEntry *entry,
                                                         NSDictionary  *bindings) {
                return [entry.title.lowercaseString containsString:normalizedQuery] ||
                       [entry.subtitle.lowercaseString containsString:normalizedQuery];
            }]];
    }
    [self.tableView reloadData];
}

- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)searchText
{
    [self refreshEntries];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return self.filteredEntries.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView
         cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    static NSString *cellIdentifier = @"SettingsListCell";
    UITableViewCell *cell           = [tableView dequeueReusableCellWithIdentifier:cellIdentifier];
    if (!cell)
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle
                                      reuseIdentifier:cellIdentifier];

    SettingsEntry *entry      = self.filteredEntries[indexPath.row];
    cell.textLabel.text       = entry.title;
    cell.detailTextLabel.text = entry.subtitle;
    cell.accessoryType =
        entry.action ? UITableViewCellAccessoryDisclosureIndicator : UITableViewCellAccessoryNone;
    cell.selectionStyle =
        entry.action ? UITableViewCellSelectionStyleDefault : UITableViewCellSelectionStyleNone;
    return cell;
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath
{
    return self.filteredEntries[indexPath.row].deleteAction != nil;
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView
    trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath
{
    SettingsEntry *entry = self.filteredEntries[indexPath.row];
    if (!entry.deleteAction)
        return nil;

    UIContextualAction *deleteAction = [UIContextualAction
        contextualActionWithStyle:UIContextualActionStyleDestructive
                            title:LocalizedString(@"Delete")
                          handler:^(__unused UIContextualAction *action,
                                    __unused UIView *sourceView, void (^completionHandler)(BOOL)) {
                              entry.deleteAction();
                              [self refreshEntries];
                              completionHandler(YES);
                          }];
    deleteAction.image               = [UIImage systemImageNamed:@"trash"];
    return [UISwipeActionsConfiguration configurationWithActions:@[ deleteAction ]];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    SettingsEntry *entry = self.filteredEntries[indexPath.row];
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (entry.action)
        entry.action();
}

@end

static NSAttributedString *RenderedGonerinoChangelog(void)
{
    UIFont *bodyFont                    = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    UIFont *sectionFont                 = [UIFont preferredFontForTextStyle:UIFontTextStyleTitle3];
    UIFont *titleFont                   = [UIFont preferredFontForTextStyle:UIFontTextStyleTitle1];
    NSMutableAttributedString *rendered = [NSMutableAttributedString new];
    for (NSString *line in [GONERINO_CHANGELOG componentsSeparatedByString:@"\n"])
    {
        NSString *text             = line;
        UIFont   *font             = bodyFont;
        CGFloat   paragraphSpacing = 4.0;
        if ([line hasPrefix:@"### "])
        {
            text = [line substringFromIndex:4];
            font = [UIFont systemFontOfSize:sectionFont.pointSize weight:UIFontWeightBold];
            paragraphSpacing = 14.0;
        }
        else if ([line hasPrefix:@"## "])
        {
            text = [line substringFromIndex:3];
            font = [UIFont systemFontOfSize:titleFont.pointSize weight:UIFontWeightBold];
            paragraphSpacing = 16.0;
        }
        else if ([line hasPrefix:@"# "])
        {
            text = [line substringFromIndex:2];
            font = [UIFont systemFontOfSize:titleFont.pointSize + 4.0 weight:UIFontWeightBold];
            paragraphSpacing = 18.0;
        }
        else if ([line hasPrefix:@"- "])
        {
            text = [NSString stringWithFormat:@"• %@", [line substringFromIndex:2]];
        }
        NSMutableParagraphStyle *paragraphStyle = [NSMutableParagraphStyle new];
        paragraphStyle.paragraphSpacing         = paragraphSpacing;
        if ([line hasPrefix:@"- "])
        {
            paragraphStyle.firstLineHeadIndent = 0.0;
            paragraphStyle.headIndent          = 18.0;
        }
        NSDictionary *attributes = @{
            NSFontAttributeName : font,
            NSForegroundColorAttributeName : UIColor.labelColor,
            NSParagraphStyleAttributeName : paragraphStyle
        };
        [rendered
            appendAttributedString:[[NSAttributedString alloc]
                                       initWithString:[NSString stringWithFormat:@"%@\n", text]
                                           attributes:attributes]];
    }
    return rendered;
}

@interface                                ChangelogViewController : UIViewController
@property (nonatomic, strong) UITextView *textView;
@end

@implementation ChangelogViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.title                = LocalizedString(@"What's New");
    self.view.backgroundColor = UIColor.systemBackgroundColor;
    self.navigationItem.rightBarButtonItem =
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone
                                                      target:self
                                                      action:@selector(close)];
    self.textView                                           = [UITextView new];
    self.textView.translatesAutoresizingMaskIntoConstraints = NO;
    self.textView.editable                                  = NO;
    self.textView.selectable                                = YES;
    self.textView.alwaysBounceVertical                      = YES;
    self.textView.backgroundColor                           = UIColor.systemBackgroundColor;
    self.textView.textColor                                 = UIColor.labelColor;
    self.textView.font           = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    self.textView.attributedText = RenderedGonerinoChangelog();
    [self.view addSubview:self.textView];
    [NSLayoutConstraint activateConstraints:@[
        [self.textView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [self.textView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.textView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.textView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor]
    ]];
}

- (void)close
{
    [self dismissViewControllerAnimated:YES completion:nil];
}

@end

@interface SettingsPageViewController
    : UIViewController <UITableViewDataSource, UITableViewDelegate, UIDocumentPickerDelegate>
@property (nonatomic, strong) UITableView                *tableView;
@property (nonatomic, weak) YTSettingsSectionItemManager *settingsManager;
@property (nonatomic, assign) BOOL                        importingSettings;
@property (nonatomic, strong) NSURL                      *exportFileURL;
@property (nonatomic, strong) UISwitch                   *updateSwitch;
- (instancetype)initWithSettingsManager:(YTSettingsSectionItemManager *)settingsManager;
@end

@implementation SettingsPageViewController

- (UIInterfaceOrientationMask)supportedInterfaceOrientations
{
    return UIInterfaceOrientationMaskPortrait;
}

- (UIInterfaceOrientation)preferredInterfaceOrientationForPresentation
{
    return UIInterfaceOrientationPortrait;
}

- (BOOL)shouldAutorotate
{
    return YES;
}

- (instancetype)initWithSettingsManager:(YTSettingsSectionItemManager *)settingsManager
{
    self = [super initWithNibName:nil bundle:nil];
    if (self)
    {
        self.title       = LocalizedString(@"Gonerino");
        _settingsManager = settingsManager;
    }
    return self;
}

- (void)returnToYouTubeSettings
{
    UINavigationController *navigationController = self.navigationController;
    if (navigationController && navigationController.viewControllers.count > 1)
    {
        [navigationController popToRootViewControllerAnimated:YES];
        return;
    }
    if (navigationController.presentingViewController)
    {
        [navigationController dismissViewControllerAnimated:YES completion:nil];
        return;
    }
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.systemBackgroundColor;
    self.tableView            = [[UITableView alloc] initWithFrame:self.view.bounds
                                                             style:UITableViewStyleInsetGrouped];
    self.tableView.autoresizingMask =
        UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.tableView.backgroundColor = UIColor.systemBackgroundColor;
    self.tableView.dataSource      = self;
    self.tableView.delegate        = self;
    [self.view addSubview:self.tableView];
    self.tableView.rowHeight                  = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight         = 56.0;
    self.updateSwitch = [UISwitch new];
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    self.updateSwitch.on = [defaults objectForKey:@"GonerinoCheckForUpdates"] == nil
                               ? YES
                               : [defaults boolForKey:@"GonerinoCheckForUpdates"];
    [self.updateSwitch addTarget:self
                          action:@selector(updateCheckChanged:)
                forControlEvents:UIControlEventValueChanged];
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;
    self.navigationItem.hidesBackButton       = YES;
    if (UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad)
    {
        self.navigationItem.leftBarButtonItem = nil;
    }
    else
    {
        self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc]
            initWithCustomView:NavigationBackButton(LocalizedString(@"Settings"), self,
                                                    @selector(returnToYouTubeSettings))];
    }
    [self.tableView reloadData];
}

- (void)viewDidLayoutSubviews
{
    [super viewDidLayoutSubviews];
    self.tableView.frame = self.view.bounds;
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    if (UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad)
    {
        self.navigationItem.hidesBackButton   = YES;
        self.navigationItem.leftBarButtonItem = nil;
        self.navigationItem.backBarButtonItem = nil;
    }
    RequestPortraitOrientation(self);
    [self.tableView reloadData];
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    RequestPortraitOrientation(self);
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return 5;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    switch (section)
    {
        case 0:
            return 1;
        case 1:
            return 4;
        case 2:
            return 3;
        case 3:
            return 2;
        default:
            return 3;
    }
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
    switch (section)
    {
        case 0:
            return LocalizedString(@"Support");
        case 1:
            return LocalizedString(@"Filtering");
        case 2:
            return LocalizedString(@"Blocked Content");
        case 3:
            return LocalizedString(@"Settings");
        default:
            return LocalizedString(@"About");
    }
}

- (NSString *)titleForRow:(NSIndexPath *)indexPath
{
    if (indexPath.section == 0)
        return LocalizedString(@"Donate on Ko-fi");
    if (indexPath.section == 1)
        return LocalizedString(@[
            @"Enable Gonerino", @"Show Gonerino Button", @"Block 'People also watched'",
            @"Block 'You might also like'"
        ][indexPath.row]);
    if (indexPath.section == 2)
        return LocalizedString(@[ @"Channels", @"Videos", @"Words" ][indexPath.row]);
    if (indexPath.section == 3)
        return LocalizedString(@[ @"Export Settings", @"Import Settings" ][indexPath.row]);
    if (indexPath.section == 4 && indexPath.row == 0)
        return LocalizedString(@"Check for Updates");
    if (indexPath.section == 4 && indexPath.row == 1)
        return LocalizedString(@"Discord");
    return [NSString stringWithFormat:@"%@ %@", LocalizedString(@"Version"), TWEAK_VERSION];
}

- (NSString *)subtitleForRow:(NSIndexPath *)indexPath
{
    if (indexPath.section == 1)
        return LocalizedString(@[
            @"Remove blocked content from YouTube feeds",
            @"Display the quick toggle in the top navigation bar",
            @"Remove this recommendation section", @"Remove this recommendation section"
        ][indexPath.row]);

    if (indexPath.section == 2)
    {
        if (indexPath.row == 0)
            return LocalizedCount(@"blocked channel", @"blocked channels",
                                  [ChannelManager sharedInstance].blockedChannels.count);
        if (indexPath.row == 1)
            return LocalizedCount(@"blocked video", @"blocked videos",
                                  [VideoManager sharedInstance].blockedVideos.count);
        return LocalizedCount(@"blocked word", @"blocked words",
                              [WordManager sharedInstance].blockedWords.count);
    }

    if (indexPath.section == 4 && indexPath.row == 0)
        return LocalizedString(@"Check for Gonerino updates on launch");
    if (indexPath.section == 4 && indexPath.row == 2)
        return LocalizedString(@"Read the latest changes");

    return nil;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section
{
    if (section == 0)
        return LocalizedString(@"Support Gonerino development");
    return nil;
}

- (BOOL)valueForSwitchRow:(NSInteger)row
{
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    switch (row)
    {
        case 0:
            return [defaults objectForKey:@"GonerinoEnabled"] == nil
                       ? YES
                       : [defaults boolForKey:@"GonerinoEnabled"];
        case 1:
            return [defaults objectForKey:@"GonerinoShowButton"] == nil
                       ? YES
                       : [defaults boolForKey:@"GonerinoShowButton"];
        case 2:
            return [defaults boolForKey:@"GonerinoPeopleWatched"];
        default:
            return [defaults boolForKey:@"GonerinoMightLike"];
    }
}

- (void)switchChanged:(UISwitch *)sender
{
    NSArray *keys = @[
        @"GonerinoEnabled", @"GonerinoShowButton", @"GonerinoPeopleWatched", @"GonerinoMightLike"
    ];
    [[NSUserDefaults standardUserDefaults] setBool:sender.isOn forKey:keys[sender.tag]];
    [[NSUserDefaults standardUserDefaults] synchronize];
    [Util refreshPreferenceSnapshot];
    [[NSNotificationCenter defaultCenter] postNotificationName:FeedFilterStateDidChangeNotification
                                                        object:nil];
}

- (void)updateCheckChanged:(UISwitch *)sender
{
    [[NSUserDefaults standardUserDefaults] setBool:sender.isOn forKey:@"GonerinoCheckForUpdates"];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

- (void)actionButtonTapped:(UIButton *)sender
{
    NSInteger section   = sender.tag / 100;
    NSInteger row       = sender.tag % 100;
    NSString *URLString = nil;
    if (section == 0)
        URLString = @"https://ko-fi.com/castdrian";
    else if (section == 3)
    {
        if (row == 0)
            [self exportSettings];
        else
            [self importSettings];
    }
    else if (section == 4 && row == 1)
        URLString = @"https://discord.gg/NdaBaxFKnn";
    else if (section == 4 && row == 2)
    {
        [self openChangelog];
    }
    if (URLString.length > 0)
        [[UIApplication sharedApplication] openURL:[NSURL URLWithString:URLString]
                                           options:@{}
                                 completionHandler:nil];
}

- (BOOL)hasUnreadChangelog
{
    NSString *lastOpenedVersion =
        [[NSUserDefaults standardUserDefaults] stringForKey:@"GonerinoLastOpenedChangelogVersion"];
    return ![lastOpenedVersion isEqualToString:TWEAK_VERSION];
}

- (void)openChangelog
{
    [[NSUserDefaults standardUserDefaults] setObject:TWEAK_VERSION
                                              forKey:@"GonerinoLastOpenedChangelogVersion"];
    [[NSUserDefaults standardUserDefaults] synchronize];
    [self.tableView reloadData];
    ChangelogViewController *changelogViewController = [ChangelogViewController new];
    UINavigationController  *navigationController =
        [[UINavigationController alloc] initWithRootViewController:changelogViewController];
    navigationController.modalPresentationStyle = UIModalPresentationFullScreen;
    [self presentViewController:navigationController animated:YES completion:nil];
}

- (UITableViewCell *)buttonCellForTableView:(UITableView *)tableView
                                  indexPath:(NSIndexPath *)indexPath
{
    static NSString *identifier = @"SettingsButtonCell";
    UITableViewCell *cell       = [tableView dequeueReusableCellWithIdentifier:identifier];
    if (!cell)
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault
                                      reuseIdentifier:identifier];

    for (UIView *subview in cell.contentView.subviews)
        [subview removeFromSuperview];

    NSString *title     = [self titleForRow:indexPath];
    BOOL      prominent = indexPath.section == 0;
    BOOL      discord   = indexPath.section == 4 && indexPath.row == 1;
    BOOL      changelog = indexPath.section == 4 && indexPath.row == 2;
    UIButton *button    = [UIButton buttonWithType:UIButtonTypeSystem];
    if (@available(iOS 15.0, *))
    {
        UIButtonConfiguration *configuration =
            prominent ? [UIButtonConfiguration tintedButtonConfiguration]
                      : [UIButtonConfiguration plainButtonConfiguration];
        configuration.image         = prominent
                                          ? [UIImage systemImageNamed:@"heart.fill"]
                                          : (discord
                                                 ? GonerinoDiscordImage()
                                                 : [UIImage
                                                       systemImageNamed:(changelog
                                                                             ? @"sparkles"
                                                                             : (indexPath.row == 0
                                                                                    ? @"square.and.arrow.up"
                                                                                    : @"square.and.arrow.down"))]);
        configuration.title         = title;
        configuration.imagePadding  = prominent ? 8.0 : 6.0;
        configuration.contentInsets = prominent
                                          ? NSDirectionalEdgeInsetsMake(12.0, 12.0, 12.0, 12.0)
                                          : NSDirectionalEdgeInsetsMake(8.0, 0.0, 8.0, 0.0);
        if (prominent)
            configuration.cornerStyle = UIButtonConfigurationCornerStyleMedium;
        button.configuration = configuration;
    }
    else
    {
        UIImage *image = prominent
                             ? [UIImage systemImageNamed:@"heart.fill"]
                             : (discord ? GonerinoDiscordImage()
                                         : [UIImage
                                               systemImageNamed:(changelog
                                                                     ? @"sparkles"
                                                                     : (indexPath.row == 0
                                                                            ? @"square.and.arrow.up"
                                                                            : @"square.and.arrow.down"))]);
        [button setImage:image forState:UIControlStateNormal];
        [button setTitle:title forState:UIControlStateNormal];
        button.imageEdgeInsets = UIEdgeInsetsMake(0.0, 0.0, 0.0, 6.0);
        button.contentEdgeInsets =
            UIEdgeInsetsMake(prominent ? 12.0 : 8.0, 0.0, prominent ? 12.0 : 8.0, 0.0);
    }
    button.tag                        = indexPath.section * 100 + indexPath.row;
    button.accessibilityLabel         = title;
    button.contentHorizontalAlignment = prominent ? UIControlContentHorizontalAlignmentCenter
                                                  : UIControlContentHorizontalAlignmentLeft;
    button.translatesAutoresizingMaskIntoConstraints = NO;
    [button addTarget:self
                  action:@selector(actionButtonTapped:)
        forControlEvents:UIControlEventTouchUpInside];
    UILabel *badge = nil;
    if (changelog && [self hasUnreadChangelog])
    {
        badge                                           = [UILabel new];
        badge.translatesAutoresizingMaskIntoConstraints = NO;
        badge.text                                      = LocalizedString(@"NEW");
        badge.textColor                                 = UIColor.whiteColor;
        badge.backgroundColor                           = UIColor.systemRedColor;
        badge.font               = [UIFont systemFontOfSize:11.0 weight:UIFontWeightBold];
        badge.textAlignment      = NSTextAlignmentCenter;
        badge.layer.cornerRadius = 8.0;
        badge.clipsToBounds      = YES;
        [cell.contentView addSubview:badge];
        [NSLayoutConstraint activateConstraints:@[
            [badge.centerYAnchor constraintEqualToAnchor:cell.contentView.centerYAnchor],
            [badge.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor
                                                 constant:-16.0],
            [badge.widthAnchor constraintEqualToConstant:42.0],
            [badge.heightAnchor constraintEqualToConstant:22.0]
        ]];
    }
    [cell.contentView addSubview:button];
    NSLayoutXAxisAnchor *buttonTrailingAnchor =
        badge ? badge.leadingAnchor : cell.contentView.trailingAnchor;
    CGFloat buttonTrailingConstant = badge ? -12.0 : -16.0;
    [NSLayoutConstraint activateConstraints:@[
        [button.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor constant:4.0],
        [button.leadingAnchor constraintEqualToAnchor:cell.contentView.leadingAnchor constant:16.0],
        [button.trailingAnchor constraintEqualToAnchor:buttonTrailingAnchor
                                              constant:buttonTrailingConstant],
        [button.bottomAnchor constraintEqualToAnchor:cell.contentView.bottomAnchor constant:-4.0]
    ]];
    cell.accessoryView   = nil;
    cell.accessoryType   = UITableViewCellAccessoryNone;
    cell.selectionStyle  = UITableViewCellSelectionStyleNone;
    cell.backgroundColor = UIColor.clearColor;
    if (@available(iOS 14.0, *))
        cell.backgroundConfiguration = [UIBackgroundConfiguration clearConfiguration];
    return cell;
}

- (UITableViewCell *)tableView:(UITableView *)tableView
         cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    if (indexPath.section == 0 || indexPath.section == 3 ||
        (indexPath.section == 4 && (indexPath.row == 1 || indexPath.row == 2)))
        return [self buttonCellForTableView:tableView indexPath:indexPath];

    BOOL switchRow = indexPath.section == 1 || (indexPath.section == 4 && indexPath.row == 0);
    NSString *identifier = switchRow ? (indexPath.section == 1 ? @"SettingsSwitchCell"
                                                               : @"SettingsUpdateCell")
                                     : @"SettingsNavigationCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:identifier];
    if (!cell)
        cell = [[UITableViewCell alloc]
              initWithStyle:switchRow && indexPath.section == 1 ? UITableViewCellStyleDefault
                                                                : UITableViewCellStyleSubtitle
            reuseIdentifier:identifier];

    cell.textLabel.text       = [self titleForRow:indexPath];
    cell.detailTextLabel.text = [self subtitleForRow:indexPath];
    if (indexPath.section == 4 && indexPath.row == 0)
    {
        cell.backgroundColor = UIColor.clearColor;
        cell.contentView.backgroundColor = UIColor.clearColor;
        cell.backgroundView = [UIView new];
        cell.backgroundView.backgroundColor = UIColor.clearColor;
        cell.selectedBackgroundView = [UIView new];
        cell.selectedBackgroundView.backgroundColor = UIColor.clearColor;
        if (@available(iOS 14.0, *))
            cell.backgroundConfiguration = [UIBackgroundConfiguration clearConfiguration];
    }
    if (indexPath.section == 1)
    {
        UISwitch *control = [UISwitch new];
        control.tag       = indexPath.row;
        control.on        = [self valueForSwitchRow:indexPath.row];
        [control addTarget:self
                      action:@selector(switchChanged:)
            forControlEvents:UIControlEventValueChanged];
        cell.accessoryView  = control;
        cell.accessoryType  = UITableViewCellAccessoryNone;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
    }
    else if (indexPath.section == 4 && indexPath.row == 0)
    {
        cell.detailTextLabel.text = [self subtitleForRow:indexPath];
        cell.accessoryView = self.updateSwitch;
        cell.accessoryType = UITableViewCellAccessoryNone;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
    }
    else
    {
        cell.accessoryView  = nil;
        cell.accessoryType  = UITableViewCellAccessoryDisclosureIndicator;
        cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    }
    return cell;
}

- (void)presentChoiceWithTitle:(NSString *)title
                       message:(NSString *)message
                       options:(NSArray<NSString *> *)options
                 selectedIndex:(NSInteger)selectedIndex
                    completion:(void (^)(NSInteger index))completion
{
    UIAlertController *alert =
        [UIAlertController alertControllerWithTitle:title
                                            message:message
                                     preferredStyle:UIAlertControllerStyleAlert];
    for (NSUInteger index = 0; index < options.count; index++)
    {
        NSString *optionTitle = (NSInteger) index == selectedIndex
                                    ? [NSString stringWithFormat:@"✓ %@", options[index]]
                                    : options[index];
        [alert addAction:[UIAlertAction actionWithTitle:optionTitle
                                                  style:UIAlertActionStyleDefault
                                                handler:^(__unused UIAlertAction *action) {
                                                    if (completion)
                                                        completion((NSInteger) index);
                                                }]];
    }
    [alert addAction:[UIAlertAction actionWithTitle:LocalizedString(@"Cancel")
                                              style:UIAlertActionStyleCancel
                                            handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)openChannels
{
    __weak __block SettingsListViewController *weakList;
    __weak typeof(self)                        weakSelf = self;
    // 表示の絞り込み: 0 = すべて, 1 = Channel ID, 2 = Handle, 3 = Name (legacy)
    __block NSInteger    listFilter = 0;
    NSArray<NSString *> *modeTitles = @[
        LocalizedString(@"ID + handle"), LocalizedString(@"ID only"),
        LocalizedString(@"Handle only")
    ];
    NSArray<NSString *> *filterTitles = @[
        LocalizedString(@"All"), LocalizedString(@"Channel ID"), LocalizedString(@"Handle"),
        LocalizedString(@"Name (legacy)")
    ];
    SettingsListViewController *list = [[SettingsListViewController alloc]
            initWithTitle:LocalizedString(@"Blocked Channels")
        searchPlaceholder:LocalizedString(@"Search channels")
          entriesProvider:^NSArray<SettingsEntry *> * {
              NSMutableArray      *entries  = [NSMutableArray array];
              ChannelManager      *manager  = [ChannelManager sharedInstance];
              NSArray<NSString *> *channels = manager.blockedChannels;

              [entries addObject:[SettingsEntry
                                     entryWithTitle:LocalizedString(@"Add Channel")
                                           subtitle:LocalizedString(
                                                        @"Channel ID, @handle or channel URL")
                                             action:^{
                                                 PresentTextInputAlert(
                                                     weakSelf, LocalizedString(@"Add Channel"),
                                                     LocalizedString(@"Enter a channel ID (UC…), "
                                                                     @"@handle or channel URL"),
                                                     @"UC… / @handle / URL", ^(NSString *text) {
                                                         NSString *entry = [ChannelManager
                                                             normalizedEntryFromInput:text];
                                                         if (!entry)
                                                             return;
                                                         [[ChannelManager sharedInstance]
                                                             addBlockedChannel:entry];
                                                         if ([ChannelManager kindOfEntry:entry] ==
                                                             GNRChannelEntryKindName)
                                                             ShowToast(
                                                                 weakSelf,
                                                                 LocalizedString(
                                                                     @"Added as a channel name "
                                                                     @"(not an ID or handle)"));
                                                         [weakList refreshEntries];
                                                         [weakSelf.settingsManager
                                                                 settingsIntegrationReloadSection];
                                                     });
                                             }]];

              NSInteger storedMode = [[NSUserDefaults standardUserDefaults]
                  integerForKey:@"GonerinoChannelBlockMode"];
              NSInteger mode = (storedMode >= 0 && storedMode <= 2) ? storedMode : 0;
              [entries addObject:[SettingsEntry
                                     entryWithTitle:LocalizedString(@"\"Block channel\" saves")
                                           subtitle:modeTitles[(NSUInteger) mode]
                                             action:^{
                                                 [weakSelf
                                                     presentChoiceWithTitle:
                                                         LocalizedString(@"\"Block channel\" saves")
                                                                    message:
                                                                        LocalizedString(
                                                                            @"What the menu item "
                                                                            @"registers. Existing "
                                                                            @"entries are not "
                                                                            @"changed.")
                                                                    options:modeTitles
                                                              selectedIndex:mode
                                                                 completion:^(NSInteger index) {
                                                                     NSUserDefaults *defaults =
                                                                         [NSUserDefaults
                                                                             standardUserDefaults];
                                                                     [defaults
                                                                         setInteger:index
                                                                             forKey:
                                                                                 @"GonerinoChannelBlockMode"];
                                                                     [defaults synchronize];
                                                                     [weakList refreshEntries];
                                                                 }];
                                             }]];

              NSUInteger idCount     = 0;
              NSUInteger handleCount = 0;
              NSUInteger nameCount   = 0;
              for (NSString *channel in channels)
              {
                  GNRChannelEntryKind kind = [ChannelManager kindOfEntry:channel];
                  if (kind == GNRChannelEntryKindID)
                      idCount++;
                  else if (kind == GNRChannelEntryKindHandle)
                      handleCount++;
                  else
                      nameCount++;
              }
              NSArray<NSNumber *> *filterCounts =
                  @[ @(channels.count), @(idCount), @(handleCount), @(nameCount) ];
              NSMutableArray<NSString *> *filterOptions = [NSMutableArray array];
              for (NSUInteger index = 0; index < filterTitles.count; index++)
              {
                  [filterOptions
                      addObject:[NSString stringWithFormat:@"%@ (%@)", filterTitles[index],
                                                           filterCounts[index]]];
              }
              NSInteger currentFilter = (listFilter >= 0 && listFilter <= 3) ? listFilter : 0;
              [entries addObject:[SettingsEntry
                                     entryWithTitle:LocalizedString(@"Show")
                                           subtitle:filterOptions[(NSUInteger) currentFilter]
                                             action:^{
                                                 [weakSelf
                                                     presentChoiceWithTitle:LocalizedString(@"Show")
                                                                    message:nil
                                                                    options:filterOptions
                                                              selectedIndex:currentFilter
                                                                 completion:^(NSInteger index) {
                                                                     listFilter = index;
                                                                     [weakList refreshEntries];
                                                                 }];
                                             }]];

              NSUInteger shownCount = 0;
              for (NSString *channel in channels)
              {
                  GNRChannelEntryKind kind = [ChannelManager kindOfEntry:channel];
                  if (currentFilter == 1 && kind != GNRChannelEntryKindID)
                      continue;
                  if (currentFilter == 2 && kind != GNRChannelEntryKindHandle)
                      continue;
                  if (currentFilter == 3 && kind != GNRChannelEntryKindName)
                      continue;
                  NSString *label           = [manager labelForChannel:channel];
                  NSString *kindDescription = ChannelKindDescription(channel);
                  NSString *subtitle =
                      label.length > 0
                          ? [NSString stringWithFormat:@"%@ · %@", kindDescription, channel]
                          : kindDescription;
                  [entries addObject:[SettingsEntry
                                         entryWithTitle:label.length > 0 ? label : channel
                                               subtitle:subtitle
                                           deleteAction:^{
                                               [[ChannelManager sharedInstance]
                                                   removeBlockedChannel:channel];
                                               [weakSelf.settingsManager
                                                       settingsIntegrationReloadSection];
                                           }]];
                  shownCount++;
              }
              if (shownCount == 0)
              {
                  [entries addObject:[SettingsEntry entryWithTitle:LocalizedString(@"No channels")
                                                          subtitle:nil
                                                            action:nil]];
              }
              return entries;
          }];
    weakList = list;
    [self.navigationController pushViewController:list animated:YES];
}

- (void)openVideos
{
    __weak __block SettingsListViewController *weakList;
    __weak typeof(self)                        weakSelf = self;
    SettingsListViewController *list = [[SettingsListViewController alloc]
            initWithTitle:LocalizedString(@"Blocked Videos")
        searchPlaceholder:LocalizedString(@"Search videos")
          entriesProvider:^NSArray<SettingsEntry *> * {
              NSMutableArray *entries = [NSMutableArray array];
              [entries addObject:[SettingsEntry
                                     entryWithTitle:LocalizedString(@"Add Video")
                                           subtitle:LocalizedString(@"Video ID or video URL")
                                             action:^{
                                                 PresentTextInputAlert(
                                                     weakSelf, LocalizedString(@"Add Video"),
                                                     LocalizedString(
                                                         @"Enter a video ID or video URL"),
                                                     @"dQw4w9WgXcQ / URL", ^(NSString *text) {
                                                         NSString *videoID =
                                                             [Util videoIDFromString:text];
                                                         if (videoID.length == 0)
                                                         {
                                                             ShowToast(
                                                                 weakSelf,
                                                                 LocalizedString(
                                                                     @"Not a valid video ID or "
                                                                     @"URL"));
                                                             return;
                                                         }
                                                         [[VideoManager sharedInstance]
                                                             addBlockedVideo:videoID
                                                                       title:@""
                                                                     channel:@""];
                                                         [weakList refreshEntries];
                                                         [weakSelf.settingsManager
                                                                 settingsIntegrationReloadSection];
                                                     });
                                             }]];
              NSArray *videos = [VideoManager sharedInstance].blockedVideos;
              if (videos.count == 0)
              {
                  [entries
                      addObject:[SettingsEntry entryWithTitle:LocalizedString(@"No blocked videos")
                                                     subtitle:nil
                                                       action:nil]];
                  return entries;
              }
              for (NSDictionary *video in videos)
              {
                  NSString *videoId = video[@"id"];
                  NSString *title   = [video[@"title"] length] > 0 ? video[@"title"] : videoId;
                  NSString *channel = [video[@"channel"] length] > 0
                                          ? video[@"channel"]
                                          : LocalizedString(@"Unknown Channel");
                  [entries addObject:[SettingsEntry entryWithTitle:title
                                                          subtitle:channel
                                                      deleteAction:^{
                                                          [[VideoManager sharedInstance]
                                                              removeBlockedVideo:videoId];
                                                          [weakSelf.settingsManager
                                                                  settingsIntegrationReloadSection];
                                                      }]];
              }
              return entries;
          }];
    weakList = list;
    [self.navigationController pushViewController:list animated:YES];
}

- (void)openWords
{
    __weak __block SettingsListViewController *weakList;
    __weak typeof(self)                        weakSelf = self;
    SettingsListViewController *list = [[SettingsListViewController alloc]
            initWithTitle:LocalizedString(@"Blocked Words")
        searchPlaceholder:LocalizedString(@"Search words")
          entriesProvider:^NSArray<SettingsEntry *> * {
              NSMutableArray *entries = [NSMutableArray array];
              [entries addObject:[SettingsEntry
                                     entryWithTitle:LocalizedString(@"Add Word")
                                           subtitle:LocalizedString(
                                                        @"Word, /regex/i, or !exception")
                                             action:^{
                                                 PresentTextInputAlert(
                                                     weakSelf, LocalizedString(@"Add Word"),
                                                     LocalizedString(
                                                         @"word = contains\n/pattern/i = regular "
                                                         @"expression\n!rule = exception\ntitle: / "
                                                         @"channel: = limit the target"),
                                                     LocalizedString(@"Word or phrase"),
                                                     ^(NSString *text) {
                                                         if (![WordManager validateRule:text
                                                                                  error:nil])
                                                         {
                                                             ShowToast(
                                                                 weakSelf,
                                                                 LocalizedString(
                                                                     @"Invalid rule or regular "
                                                                     @"expression"));
                                                             return;
                                                         }
                                                         [[WordManager sharedInstance]
                                                             addBlockedWord:text];
                                                         [weakList refreshEntries];
                                                         [weakSelf.settingsManager
                                                                 settingsIntegrationReloadSection];
                                                     });
                                             }]];
              for (NSString *word in [WordManager sharedInstance].blockedWords)
              {
                  [entries addObject:[SettingsEntry
                                         entryWithTitle:word
                                               subtitle:[WordManager summaryForRule:word]
                                           deleteAction:^{
                                               [[WordManager sharedInstance]
                                                   removeBlockedWord:word];
                                               [weakSelf.settingsManager
                                                       settingsIntegrationReloadSection];
                                           }]];
              }
              return entries;
          }];
    weakList = list;
    [self.navigationController pushViewController:list animated:YES];
}

- (NSDictionary *)settingsDictionary
{
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    return @{
        @"blockedChannels" : [ChannelManager sharedInstance].blockedChannels,   
        @"channelLabels" : [ChannelManager sharedInstance].channelLabels,   // ← 追加
        @"blockedVideos" : [VideoManager sharedInstance].blockedVideos,
        @"blockedWords" : [WordManager sharedInstance].blockedWords,
        @"gonerinoEnabled" : @([defaults objectForKey:@"GonerinoEnabled"] == nil
                                   ? YES
                                   : [defaults boolForKey:@"GonerinoEnabled"]),
        @"showButton" : @([defaults objectForKey:@"GonerinoShowButton"] == nil
                              ? YES
                              : [defaults boolForKey:@"GonerinoShowButton"]),
        @"blockPeopleWatched" : @([defaults boolForKey:@"GonerinoPeopleWatched"]),
        @"blockMightLike" : @([defaults boolForKey:@"GonerinoMightLike"]),
        @"checkForUpdates" : @([defaults objectForKey:@"GonerinoCheckForUpdates"] == nil
                                    ? YES
                                    : [defaults boolForKey:@"GonerinoCheckForUpdates"])
    };
}

- (void)exportSettings
{
    NSURL *fileURL =
        [NSURL fileURLWithPath:[NSTemporaryDirectory()
                                   stringByAppendingPathComponent:@"gonerino_settings.plist"]];
    if (![self.settingsDictionary writeToURL:fileURL atomically:YES])
    {
        ShowToast(self, LocalizedString(@"Could not create settings file"));
        return;
    }

    self.exportFileURL     = fileURL;
    self.importingSettings = NO;
    UIActivityViewController *activityController =
        [[UIActivityViewController alloc] initWithActivityItems:@[ fileURL ]
                                          applicationActivities:nil];
    __weak typeof(self) weakSelf = self;
    activityController.completionWithItemsHandler =
        ^(__unused UIActivityType activityType, BOOL completed, __unused NSArray *returnedItems,
          NSError *error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                __strong typeof(weakSelf) strongSelf = weakSelf;
                if (!strongSelf)
                    return;
                if (completed)
                    ShowToast(strongSelf, LocalizedString(@"Settings exported successfully"));
                else if (error)
                    ShowToast(strongSelf, LocalizedString(@"Settings export failed"));
                else
                    ShowToast(strongSelf, LocalizedString(@"Export cancelled"));
                strongSelf.exportFileURL = nil;
            });
        };
    if (activityController.popoverPresentationController)
    {
        activityController.popoverPresentationController.sourceView = self.view;
        activityController.popoverPresentationController.sourceRect = self.view.bounds;
    }
    [self presentViewController:activityController animated:YES completion:nil];
}

- (void)importSettings
{
    self.importingSettings                 = YES;
    UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc]
        initForOpeningContentTypes:@[ [UTType typeWithIdentifier:@"com.apple.property-list"] ]];
    picker.delegate                        = self;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)applyImportedSettings:(NSDictionary *)settings
{
    if ([settings[@"blockedChannels"] isKindOfClass:[NSArray class]])
        [[ChannelManager sharedInstance] setBlockedChannels:settings[@"blockedChannels"]];
    if ([settings[@"channelLabels"] isKindOfClass:[NSDictionary class]])
        [[ChannelManager sharedInstance] setChannelLabels:settings[@"channelLabels"]];
    if ([settings[@"blockedWords"] isKindOfClass:[NSArray class]])
        [[WordManager sharedInstance] setBlockedWords:settings[@"blockedWords"]];
    if ([settings[@"blockedVideos"] isKindOfClass:[NSArray class]])
        [[VideoManager sharedInstance] setBlockedVideos:settings[@"blockedVideos"]];

    NSUserDefaults *defaults    = [NSUserDefaults standardUserDefaults];
    NSDictionary   *defaultKeys = @{
        @"gonerinoEnabled" : @"GonerinoEnabled",
        @"showButton" : @"GonerinoShowButton",
        @"blockPeopleWatched" : @"GonerinoPeopleWatched",
        @"blockMightLike" : @"GonerinoMightLike",
        @"checkForUpdates" : @"GonerinoCheckForUpdates"
    };
    for (NSString *settingsKey in defaultKeys)
    {
        if ([settings[settingsKey] isKindOfClass:[NSNumber class]])
            [defaults setBool:[settings[settingsKey] boolValue] forKey:defaultKeys[settingsKey]];
    }
    [defaults synchronize];
    [Util refreshPreferenceSnapshot];
    [[NSNotificationCenter defaultCenter] postNotificationName:FeedFilterStateDidChangeNotification
                                                        object:nil];
    [self.tableView reloadData];
    [self.settingsManager settingsIntegrationReloadSection];
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller
    didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls
{
    if (!self.importingSettings)
        return;

    self.importingSettings = NO;
    NSURL *url             = urls.firstObject;
    if (!url)
        return;
    [url startAccessingSecurityScopedResource];
    NSData *data = [NSData dataWithContentsOfURL:url options:0 error:nil];
    [url stopAccessingSecurityScopedResource];
    NSDictionary *settings =
        data ? [NSPropertyListSerialization propertyListWithData:data
                                                         options:NSPropertyListImmutable
                                                          format:NULL
                                                           error:nil]
             : nil;
    if (![settings isKindOfClass:[NSDictionary class]])
    {
        ShowToast(self, LocalizedString(@"Invalid settings file format"));
        return;
    }
    [self applyImportedSettings:settings];
    ShowToast(self, LocalizedString(@"Settings imported successfully"));
}

- (void)documentPickerWasCancelled:(UIDocumentPickerViewController *)controller
{
    BOOL wasImporting      = self.importingSettings;
    self.importingSettings = NO;
    if (wasImporting)
        ShowToast(self, LocalizedString(@"Import cancelled"));
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section == 0)
    {
        [[UIApplication sharedApplication]
                      openURL:[NSURL URLWithString:@"https://ko-fi.com/castdrian"]
                      options:@{}
            completionHandler:nil];
        return;
    }
    if (indexPath.section == 2)
    {
        if (indexPath.row == 0)
            [self openChannels];
        else if (indexPath.row == 1)
            [self openVideos];
        else
            [self openWords];
        return;
    }
    if (indexPath.section == 3)
    {
        if (indexPath.row == 0)
            [self exportSettings];
        else
            [self importSettings];
        return;
    }
    if (indexPath.section == 4)
    {
        if (indexPath.row == 0)
        {
            [self.updateSwitch setOn:!self.updateSwitch.isOn animated:YES];
            [self updateCheckChanged:self.updateSwitch];
        }
        else if (indexPath.row == 1)
            [[UIApplication sharedApplication]
                          openURL:[NSURL URLWithString:@"https://discord.gg/NdaBaxFKnn"]
                          options:@{}
                completionHandler:nil];
        else
            [self openChangelog];
    }
}

@end

UIViewController *CreateCustomSettingsViewController(YTSettingsSectionItemManager *manager)
{
    if (!manager)
        return nil;
    return [[SettingsPageViewController alloc] initWithSettingsManager:manager];
}
