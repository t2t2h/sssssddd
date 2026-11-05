// UI.m - Blue/Black "programmer" animated menu - AFLATOON (أفلاطون)
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#include "Shared.h"

#define AP_BLUE   [UIColor colorWithRed:0.00 green:0.67 blue:1.00 alpha:1.0]
#define AP_BLUE2  [UIColor colorWithRed:0.12 green:0.33 blue:0.95 alpha:1.0]
#define AP_CYAN   [UIColor colorWithRed:0.45 green:0.88 blue:1.00 alpha:1.0]
#define AP_DIM    [UIColor colorWithRed:0.33 green:0.47 blue:0.68 alpha:1.0]
#define AP_BLACK  [UIColor colorWithRed:0.02 green:0.03 blue:0.07 alpha:1.0]

// 6 well-known public resolvers - short chip label, full name (for the status line), IP
static const char *kDNSIP[6]     = { "1.1.1.1", "8.8.8.8", "9.9.9.9", "208.67.222.222", "94.140.14.14", "185.228.168.9" };
static NSString   *kDNSChip[6]   = { @"CF", @"GG", @"Q9", @"ODNS", @"AG", @"CB" };
static NSString   *kDNSName[6]   = { @"Cloudflare", @"Google", @"Quad9", @"OpenDNS", @"AdGuard", @"CleanBrowsing" };

#define TAG_TAB    200
#define TAG_DNS    10
#define TAG_HUD    11
#define TAG_PITCHON 12
#define TAG_EQON   13
#define TAG_SEG    20
#define TAG_NETBOOST 16
#define TAG_RESET_VOICE 30
#define TAG_RESET_EQ    31
#define TAG_PITCH  1
#define TAG_BASS   2
#define TAG_MID    3
#define TAG_TREBLE 4
#define TAG_ROOMON  14
#define TAG_ROOM    5
#define TAG_RESET_ROOM 32

static UIFont *APFont(CGFloat size, BOOL bold) {
    UIFont *f = [UIFont fontWithName:(bold ? @"Menlo-Bold" : @"Menlo-Regular") size:size];
    if (f) return f;
    return [UIFont monospacedSystemFontOfSize:size weight:(bold ? UIFontWeightBold : UIFontWeightRegular)];
}

static UILabel *APLabel(NSString *text, CGRect frame, CGFloat size, UIColor *color, BOOL bold) {
    UILabel *l = [[UILabel alloc] initWithFrame:frame];
    l.text = text;
    l.textColor = color;
    l.font = APFont(size, bold);
    return l;
}

#pragma mark - pass-through window

@interface APWindow : UIWindow
@end
@implementation APWindow
- (UIView *)hitTest:(CGPoint)p withEvent:(UIEvent *)e {
    UIView *v = [super hitTest:p withEvent:e];
    return (v == self || v == self.rootViewController.view) ? nil : v;
}
@end

#pragma mark - panel

@interface APPanel : UIView
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *cursor;
@property (nonatomic, strong) UILabel *status;
@property (nonatomic, strong) UILabel *footer;
@property (nonatomic, strong) NSArray<UIButton *> *tabs;
@property (nonatomic, strong) NSArray<UIView *> *pages;
@property (nonatomic, strong) UIView *underline;
@property (nonatomic, strong) UIView *scan;
@property (nonatomic, strong) NSArray<UIButton *> *dnsChips;
@property (nonatomic, assign) NSInteger cur;
@property (nonatomic, strong) NSTimer *typeTimer;
@property (nonatomic, copy) void (^onHUD)(BOOL on);
- (void)playIntro;
- (void)closeAnimated;
@end

@implementation APPanel

- (instancetype)init {
    self = [super initWithFrame:CGRectMake(0, 0, 310, 382)];
    if (!self) return nil;

    self.backgroundColor = [UIColor colorWithRed:0.02 green:0.03 blue:0.07 alpha:0.97];
    self.layer.cornerRadius = 12;
    self.layer.borderWidth = 1.2;
    self.layer.borderColor = AP_BLUE2.CGColor;
    self.layer.shadowColor = AP_BLUE.CGColor;
    self.layer.shadowRadius = 18;
    self.layer.shadowOpacity = 0.55;
    self.layer.shadowOffset = CGSizeZero;

    // pulsing border
    CABasicAnimation *bp = [CABasicAnimation animationWithKeyPath:@"borderColor"];
    bp.fromValue = (id)AP_BLUE2.CGColor;
    bp.toValue = (id)AP_BLUE.CGColor;
    bp.duration = 1.6;
    bp.autoreverses = YES;
    bp.repeatCount = HUGE_VALF;
    [self.layer addAnimation:bp forKey:@"borderPulse"];

    // window-style dots
    NSArray *dotColors = @[AP_BLUE2, AP_BLUE, AP_CYAN];
    for (int i = 0; i < 3; i++) {
        UIView *d = [[UIView alloc] initWithFrame:CGRectMake(12 + i * 14, 13, 8, 8)];
        d.backgroundColor = dotColors[i];
        d.layer.cornerRadius = 4;
        [self addSubview:d];
    }

    self.titleLabel = APLabel(@"", CGRectMake(58, 8, 210, 18), 11, AP_CYAN, YES);
    [self addSubview:self.titleLabel];
    self.cursor = APLabel(@"█", CGRectMake(58, 8, 10, 18), 11, AP_BLUE, NO);
    CABasicAnimation *blink = [CABasicAnimation animationWithKeyPath:@"opacity"];
    blink.fromValue = @1.0; blink.toValue = @0.0; blink.duration = 0.5;
    blink.autoreverses = YES; blink.repeatCount = HUGE_VALF;
    [self.cursor.layer addAnimation:blink forKey:@"blink"];
    [self addSubview:self.cursor];

    UIButton *x = [UIButton buttonWithType:UIButtonTypeCustom];
    x.frame = CGRectMake(272, 4, 32, 26);
    [x setTitle:@"[x]" forState:UIControlStateNormal];
    [x setTitleColor:AP_BLUE forState:UIControlStateNormal];
    x.titleLabel.font = APFont(12, YES);
    [x addTarget:self action:@selector(closeAnimated) forControlEvents:UIControlEventTouchUpInside];
    [self addSubview:x];

    UIView *sep = [[UIView alloc] initWithFrame:CGRectMake(0, 34, 310, 1)];
    sep.backgroundColor = [AP_BLUE2 colorWithAlphaComponent:0.5];
    [self addSubview:sep];

    // tabs
    NSArray *names = @[@"net.c", @"voice.m", @"room.m", @"eq.c", @"info.md"];
    NSMutableArray *tb = [NSMutableArray array];
    for (int i = 0; i < 5; i++) {
        UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
        b.frame = CGRectMake(i * 62.0, 38, 62.0, 28);
        [b setTitle:names[i] forState:UIControlStateNormal];
        b.titleLabel.font = APFont(11, YES);
        [b setTitleColor:(i == 0 ? AP_CYAN : AP_DIM) forState:UIControlStateNormal];
        b.tag = TAG_TAB + i;
        [b addTarget:self action:@selector(tabTapped:) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:b];
        [tb addObject:b];
    }
    self.tabs = tb;
    self.underline = [[UIView alloc] initWithFrame:CGRectMake(10, 65, 42.0, 2)];
    self.underline.backgroundColor = AP_BLUE;
    self.underline.layer.shadowColor = AP_BLUE.CGColor;
    self.underline.layer.shadowRadius = 4;
    self.underline.layer.shadowOpacity = 1;
    self.underline.layer.shadowOffset = CGSizeZero;
    [self addSubview:self.underline];

    // pages
    self.pages = @[[self buildNet], [self buildVoice], [self buildRoom], [self buildEQ], [self buildInfo]];
    for (NSUInteger i = 0; i < self.pages.count; i++) {
        UIView *p = self.pages[i];
        p.frame = CGRectMake(0, 72, 310, 264);
        p.hidden = (i != 0);
        [self addSubview:p];
    }
    self.cur = 0;

    // footer / credits
    UIView *sep2 = [[UIView alloc] initWithFrame:CGRectMake(0, 340, 310, 1)];
    sep2.backgroundColor = [AP_BLUE2 colorWithAlphaComponent:0.5];
    [self addSubview:sep2];
    NSString *credit = [NSString stringWithFormat:@"© %s  |  %s", AP_CREDIT_EN, AP_CREDIT_AR];
    self.footer = APLabel(credit, CGRectMake(0, 348, 310, 26), 12, AP_CYAN, YES);
    self.footer.textAlignment = NSTextAlignmentCenter;
    CABasicAnimation *fp = [CABasicAnimation animationWithKeyPath:@"opacity"];
    fp.fromValue = @0.55; fp.toValue = @1.0; fp.duration = 1.4;
    fp.autoreverses = YES; fp.repeatCount = HUGE_VALF;
    [self.footer.layer addAnimation:fp forKey:@"pulse"];
    [self addSubview:self.footer];

    // scanning line
    self.scan = [[UIView alloc] initWithFrame:CGRectMake(1, 36, 308, 2)];
    self.scan.backgroundColor = [AP_BLUE colorWithAlphaComponent:0.28];
    self.scan.layer.shadowColor = AP_BLUE.CGColor;
    self.scan.layer.shadowRadius = 5;
    self.scan.layer.shadowOpacity = 1;
    self.scan.layer.shadowOffset = CGSizeZero;
    self.scan.userInteractionEnabled = NO;
    [self addSubview:self.scan];
    CABasicAnimation *sc = [CABasicAnimation animationWithKeyPath:@"position.y"];
    sc.fromValue = @40; sc.toValue = @336; sc.duration = 3.4;
    sc.repeatCount = HUGE_VALF;
    [self.scan.layer addAnimation:sc forKey:@"scan"];

    [self refreshStatus];
    return self;
}

#pragma mark builders

- (UISwitch *)addSwitchTo:(UIView *)page y:(CGFloat)y title:(NSString *)t tag:(NSInteger)tag on:(BOOL)on {
    [page addSubview:APLabel(t, CGRectMake(14, y + 5, 220, 20), 12, AP_BLUE, YES)];
    UISwitch *s = [[UISwitch alloc] initWithFrame:CGRectMake(246, y, 51, 31)];
    s.onTintColor = AP_BLUE2;
    s.tag = tag;
    s.on = on;
    [s addTarget:self action:@selector(switchChanged:) forControlEvents:UIControlEventValueChanged];
    [page addSubview:s];
    return s;
}

- (void)addSliderTo:(UIView *)page y:(CGFloat)y title:(NSString *)t min:(float)mn max:(float)mx val:(float)v tag:(NSInteger)tag {
    [page addSubview:APLabel(t, CGRectMake(14, y, 150, 16), 11, AP_DIM, NO)];
    UILabel *val = APLabel(@"", CGRectMake(180, y, 116, 16), 11, AP_CYAN, YES);
    val.textAlignment = NSTextAlignmentRight;
    val.tag = tag + 100;
    [page addSubview:val];
    UISlider *s = [[UISlider alloc] initWithFrame:CGRectMake(14, y + 18, 282, 28)];
    s.minimumValue = mn; s.maximumValue = mx; s.value = v; s.tag = tag;
    s.minimumTrackTintColor = AP_BLUE;
    s.maximumTrackTintColor = [UIColor colorWithWhite:0.18 alpha:1.0];
    s.thumbTintColor = AP_CYAN;
    [s addTarget:self action:@selector(sliderChanged:) forControlEvents:UIControlEventValueChanged];
    [page addSubview:s];
    [self setValueLabel:val forTag:tag value:v];
}

- (void)setValueLabel:(UILabel *)l forTag:(NSInteger)tag value:(float)v {
    if (tag == TAG_PITCH || tag == TAG_ROOM) l.text = [NSString stringWithFormat:@"%.2fx", v];
    else l.text = [NSString stringWithFormat:@"%+.1f dB", v];
}

- (UIButton *)addButtonTo:(UIView *)page frame:(CGRect)f title:(NSString *)t tag:(NSInteger)tag {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
    b.frame = f;
    [b setTitle:t forState:UIControlStateNormal];
    [b setTitleColor:AP_CYAN forState:UIControlStateNormal];
    b.titleLabel.font = APFont(11, YES);
    b.layer.borderWidth = 1;
    b.layer.borderColor = AP_BLUE2.CGColor;
    b.layer.cornerRadius = 5;
    b.tag = tag;
    [b addTarget:self action:@selector(resetTapped:) forControlEvents:UIControlEventTouchUpInside];
    [page addSubview:b];
    return b;
}

- (UIButton *)dnsChip:(NSInteger)i frame:(CGRect)f {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
    b.frame = f;
    [b setTitle:kDNSChip[i] forState:UIControlStateNormal];
    b.titleLabel.font = APFont(11, YES);
    b.layer.borderWidth = 1;
    b.layer.cornerRadius = 5;
    b.tag = 300 + i;
    [b addTarget:self action:@selector(dnsChipTapped:) forControlEvents:UIControlEventTouchUpInside];
    return b;
}

- (UIView *)buildNet {
    UIView *p = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 310, 264)];
    [p addSubview:APLabel(@"// dns.override  (this app only, 6 resolvers)", CGRectMake(14, 4, 290, 16), 10, AP_DIM, NO)];
    [self addSwitchTo:p y:20 title:@"if (dns.on)" tag:TAG_DNS on:ap_dnsOn != 0];

    CGFloat cw = (282 - 2 * 6) / 3.0;
    NSMutableArray *chips = [NSMutableArray array];
    for (int i = 0; i < 6; i++) {
        CGFloat x = 14 + (i % 3) * (cw + 6);
        CGFloat y = 54 + (i / 3) * 29;
        UIButton *b = [self dnsChip:i frame:CGRectMake(x, y, cw, 24)];
        [p addSubview:b];
        [chips addObject:b];
    }
    self.dnsChips = chips;

    self.status = APLabel(@"", CGRectMake(14, 116, 282, 46), 11, AP_CYAN, NO);
    self.status.numberOfLines = 3;
    [p addSubview:self.status];

    [p addSubview:APLabel(@"// hud.ping  (real latency)", CGRectMake(14, 167, 290, 14), 10, AP_DIM, NO)];
    [self addSwitchTo:p y:183 title:@"if (hud.show)" tag:TAG_HUD on:NO];

    [p addSubview:APLabel(@"// net.boost  (QoS tuning - NOT a VPN)", CGRectMake(14, 218, 290, 14), 10, AP_DIM, NO)];
    [self addSwitchTo:p y:234 title:@"if (net.boost)" tag:TAG_NETBOOST on:ap_netBoostOn != 0];

    [self refreshDNSChips];
    return p;
}

- (UIView *)buildVoice {
    UIView *p = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 310, 264)];
    [p addSubview:APLabel(@"// voice.pitch  (mic input)", CGRectMake(14, 4, 290, 16), 10, AP_DIM, NO)];
    [self addSwitchTo:p y:22 title:@"if (voice.on)" tag:TAG_PITCHON on:ap_pitchOn != 0];
    [self addSliderTo:p y:68 title:@"voice.pitch" min:0.5f max:3.0f val:ap_pitch tag:TAG_PITCH];
    [self addButtonTo:p frame:CGRectMake(210, 126, 86, 26) title:@"[ reset ]" tag:TAG_RESET_VOICE];
    UILabel *n = APLabel(@"// works where the app captures\n// the mic through AudioUnit", CGRectMake(14, 168, 290, 40), 10, AP_DIM, NO);
    n.numberOfLines = 2;
    [p addSubview:n];
    return p;
}

- (UIView *)buildRoom {
    UIView *p = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 310, 264)];
    [p addSubview:APLabel(@"// room.speed  (everyone else, playback)", CGRectMake(14, 4, 290, 16), 10, AP_DIM, NO)];
    [self addSwitchTo:p y:22 title:@"if (room.on)" tag:TAG_ROOMON on:ap_roomOn != 0];
    [self addSliderTo:p y:68 title:@"room.speed" min:0.5f max:4.0f val:ap_roomSpeed tag:TAG_ROOM];
    [self addButtonTo:p frame:CGRectMake(210, 126, 86, 26) title:@"[ reset ]" tag:TAG_RESET_ROOM];
    UILabel *n = APLabel(@"// speeds up the voices you hear\n// from the room, locally, on this\n// device only - nothing sent out\n// is changed for other players", CGRectMake(14, 168, 290, 80), 10, AP_DIM, NO);
    n.numberOfLines = 4;
    [p addSubview:n];
    return p;
}

- (UIView *)buildEQ {
    UIView *p = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 310, 264)];
    [p addSubview:APLabel(@"// eq.biquad  (mic input)", CGRectMake(14, 4, 290, 16), 10, AP_DIM, NO)];
    [self addSwitchTo:p y:22 title:@"if (eq.on)" tag:TAG_EQON on:ap_eqOn != 0];
    [self addSliderTo:p y:62 title:@"eq.bass   120Hz" min:-12 max:12 val:ap_eqBass tag:TAG_BASS];
    [self addSliderTo:p y:110 title:@"eq.mid    1kHz" min:-12 max:12 val:ap_eqMid tag:TAG_MID];
    [self addSliderTo:p y:158 title:@"eq.treble 6kHz" min:-12 max:12 val:ap_eqTreble tag:TAG_TREBLE];
    [self addButtonTo:p frame:CGRectMake(210, 212, 86, 26) title:@"[ reset ]" tag:TAG_RESET_EQ];
    return p;
}

- (UIView *)buildInfo {
    UIView *p = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 310, 264)];
    NSString *txt = [NSString stringWithFormat:
        @"# about\n\n"
        @"author : %s / %s\n"
        @"build  : standalone dylib\n"
        @"hooks  : getaddrinfo, socket,\n"
        @"         AudioUnitRender\n"
        @"engine : 3-grain overlap-add\n"
        @"mode   : no jailbreak\n"
        @"         (sideload / ESign)\n\n"
        @"// dns scope   : this app only\n"
        @"// voice/eq    : mic path only\n"
        @"// room.speed  : local playback\n"
        @"//   bus only - not guaranteed\n"
        @"//   on every app/SDK version\n"
        @"// net.boost   : TCP/QoS tuning\n"
        @"//   NOT a VPN - no IP change,\n"
        @"//   no tunnel, no encryption",
        AP_CREDIT_EN, AP_CREDIT_AR];
    UILabel *l = APLabel(txt, CGRectMake(14, 6, 286, 240), 11, AP_BLUE, NO);
    l.numberOfLines = 0;
    [p addSubview:l];
    return p;
}

#pragma mark actions

- (NSInteger)currentDNSIndex {
    for (int i = 0; i < 6; i++) if (strcmp(ap_dnsServer, kDNSIP[i]) == 0) return i;
    return 0;
}

- (void)refreshDNSChips {
    NSInteger cur = [self currentDNSIndex];
    for (UIButton *b in self.dnsChips) {
        BOOL on = (b.tag - 300) == cur;
        b.backgroundColor = on ? AP_BLUE2 : [UIColor colorWithRed:0.05 green:0.08 blue:0.15 alpha:1.0];
        b.layer.borderColor = (on ? AP_CYAN : AP_DIM).CGColor;
        [b setTitleColor:(on ? UIColor.whiteColor : AP_DIM) forState:UIControlStateNormal];
    }
}

- (void)refreshStatus {
    NSInteger cur = [self currentDNSIndex];
    self.status.text = [NSString stringWithFormat:
        @"> resolver : %@ (%s)\n> dns      : %@\n> net.boost: %@",
        kDNSName[cur], ap_dnsServer, ap_dnsOn ? @"ACTIVE" : @"IDLE",
        ap_netBoostOn ? @"ACTIVE" : @"IDLE"];
}

- (void)switchChanged:(UISwitch *)s {
    switch (s.tag) {
        case TAG_DNS: ap_dnsOn = s.on ? 1 : 0; ap_dns_clear_cache(); [self refreshStatus]; break;
        case TAG_HUD: if (self.onHUD) self.onHUD(s.on); break;
        case TAG_PITCHON: ap_pitchOn = s.on ? 1 : 0; break;
        case TAG_EQON: ap_eqOn = s.on ? 1 : 0; break;
        case TAG_ROOMON: ap_roomOn = s.on ? 1 : 0; break;
        case TAG_NETBOOST: ap_netBoostOn = s.on ? 1 : 0; [self refreshStatus]; break;
        default: break;
    }
}

- (void)dnsChipTapped:(UIButton *)b {
    NSInteger i = b.tag - 300;
    if (i < 0 || i >= 6) return;
    ap_dnsServer = kDNSIP[i];
    ap_dns_clear_cache();
    [self refreshDNSChips];
    [self refreshStatus];
}

- (void)sliderChanged:(UISlider *)s {
    switch (s.tag) {
        case TAG_PITCH:  ap_pitch = s.value; break;
        case TAG_BASS:   ap_eqBass = s.value; break;
        case TAG_MID:    ap_eqMid = s.value; break;
        case TAG_TREBLE: ap_eqTreble = s.value; break;
        case TAG_ROOM:   ap_roomSpeed = s.value; break;
        default: break;
    }
    UILabel *l = (UILabel *)[s.superview viewWithTag:s.tag + 100];
    if ([l isKindOfClass:UILabel.class]) [self setValueLabel:l forTag:s.tag value:s.value];
}

- (void)setSliderTag:(NSInteger)tag value:(float)v {
    UISlider *s = (UISlider *)[self viewWithTag:tag];
    if (![s isKindOfClass:UISlider.class]) return;
    [s setValue:v animated:YES];
    [self sliderChanged:s];
}

- (void)resetTapped:(UIButton *)b {
    if (b.tag == TAG_RESET_VOICE) {
        [self setSliderTag:TAG_PITCH value:1.0f];
    } else if (b.tag == TAG_RESET_ROOM) {
        [self setSliderTag:TAG_ROOM value:1.0f];
    } else {
        [self setSliderTag:TAG_BASS value:0];
        [self setSliderTag:TAG_MID value:0];
        [self setSliderTag:TAG_TREBLE value:0];
    }
}

- (void)tabTapped:(UIButton *)b { [self selectTab:b.tag - TAG_TAB]; }

- (void)selectTab:(NSInteger)i {
    if (i == self.cur || i < 0 || i >= (NSInteger)self.pages.count) return;
    UIView *old = self.pages[self.cur];
    UIView *nu = self.pages[i];
    CGFloat dir = (i > self.cur) ? 26 : -26;
    nu.hidden = NO;
    nu.alpha = 0;
    nu.transform = CGAffineTransformMakeTranslation(dir, 0);
    NSInteger prev = self.cur;
    self.cur = i;
    for (UIButton *t in self.tabs)
        [t setTitleColor:((t.tag - TAG_TAB) == i ? AP_CYAN : AP_DIM) forState:UIControlStateNormal];
    [UIView animateWithDuration:0.3 delay:0 usingSpringWithDamping:0.85 initialSpringVelocity:0.4 options:0 animations:^{
        nu.alpha = 1;
        nu.transform = CGAffineTransformIdentity;
        old.alpha = 0;
        self.underline.frame = CGRectMake(i * 62.0 + 10, 65, 42.0, 2);
    } completion:^(BOOL f) {
        if (self.cur != prev) { old.hidden = YES; old.alpha = 1; }
    }];
}

#pragma mark intro / outro

- (void)typeHeader {
    NSString *full = @"aflatoon@hub:~$ ./menu --run";
    [self.typeTimer invalidate];
    self.titleLabel.text = @"";
    self.cursor.frame = CGRectMake(58, 8, 10, 18);
    __block NSUInteger n = 0;
    __weak APPanel *ws = self;
    self.typeTimer = [NSTimer scheduledTimerWithTimeInterval:0.04 repeats:YES block:^(NSTimer *t) {
        APPanel *s = ws;
        if (!s) { [t invalidate]; return; }
        n++;
        if (n > full.length) { [t invalidate]; return; }
        s.titleLabel.text = [full substringToIndex:n];
        CGSize sz = [s.titleLabel.text sizeWithAttributes:@{NSFontAttributeName: s.titleLabel.font}];
        s.cursor.frame = CGRectMake(58 + sz.width + 1, 8, 10, 18);
    }];
}

- (void)playIntro {
    self.alpha = 0;
    self.transform = CGAffineTransformMakeScale(0.82, 0.82);
    [UIView animateWithDuration:0.45 delay:0 usingSpringWithDamping:0.72 initialSpringVelocity:0.9 options:0 animations:^{
        self.alpha = 1;
        self.transform = CGAffineTransformIdentity;
    } completion:nil];
    [self typeHeader];
    UIView *page = self.pages[self.cur];
    page.alpha = 0;
    page.transform = CGAffineTransformMakeTranslation(0, 14);
    [UIView animateWithDuration:0.5 delay:0.12 options:UIViewAnimationOptionCurveEaseOut animations:^{
        page.alpha = 1;
        page.transform = CGAffineTransformIdentity;
    } completion:nil];
}

- (void)closeAnimated {
    [self.typeTimer invalidate];
    [UIView animateWithDuration:0.2 animations:^{
        self.alpha = 0;
        self.transform = CGAffineTransformMakeScale(0.9, 0.9);
    } completion:^(BOOL f) {
        self.hidden = YES;
        self.transform = CGAffineTransformIdentity;
    }];
}

@end

#pragma mark - controller

@interface APController : NSObject
@property (nonatomic, strong) APWindow *win;
@property (nonatomic, strong) APPanel *panel;
@property (nonatomic, strong) UIButton *orb;
@property (nonatomic, strong) UILabel *hud;
@property (nonatomic, strong) NSURLSession *session;
@property (nonatomic, strong) NSTimer *pingTimer;
+ (instancetype)shared;
- (void)setup;
@end

@implementation APController

+ (instancetype)shared {
    static APController *c;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ c = [APController new]; });
    return c;
}

- (void)setup {
    if (self.win) return;

    UIWindowScene *scene = nil;
    for (UIScene *s in UIApplication.sharedApplication.connectedScenes) {
        if ([s isKindOfClass:UIWindowScene.class] && s.activationState == UISceneActivationStateForegroundActive) {
            scene = (UIWindowScene *)s;
            break;
        }
    }
    if (scene) self.win = [[APWindow alloc] initWithWindowScene:scene];
    else self.win = [[APWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    self.win.frame = UIScreen.mainScreen.bounds;
    self.win.windowLevel = UIWindowLevelAlert + 100;
    self.win.backgroundColor = UIColor.clearColor;
    self.win.rootViewController = [UIViewController new];
    self.win.rootViewController.view.backgroundColor = UIColor.clearColor;
    self.win.hidden = NO;
    UIView *root = self.win.rootViewController.view;

    // ping HUD
    self.hud = APLabel(@"PING --", CGRectMake(12, 56, 104, 22), 11, AP_CYAN, YES);
    self.hud.textAlignment = NSTextAlignmentCenter;
    self.hud.backgroundColor = [UIColor colorWithRed:0.02 green:0.03 blue:0.07 alpha:0.9];
    self.hud.layer.borderColor = AP_BLUE2.CGColor;
    self.hud.layer.borderWidth = 1;
    self.hud.layer.cornerRadius = 6;
    self.hud.layer.masksToBounds = YES;
    self.hud.hidden = YES;
    [root addSubview:self.hud];

    // panel
    self.panel = [APPanel new];
    self.panel.hidden = YES;
    __weak APController *ws = self;
    self.panel.onHUD = ^(BOOL on) {
        APController *s = ws;
        if (!s) return;
        s.hud.hidden = !on;
        if (on) [s ping];
    };
    [root addSubview:self.panel];

    // orb
    self.orb = [UIButton buttonWithType:UIButtonTypeCustom];
    self.orb.frame = CGRectMake(0, 0, 56, 56);
    self.orb.center = CGPointMake(36, 190);
    self.orb.backgroundColor = [UIColor colorWithRed:0.02 green:0.03 blue:0.07 alpha:0.92];
    self.orb.layer.cornerRadius = 28;
    self.orb.layer.borderWidth = 1.5;
    self.orb.layer.borderColor = AP_BLUE2.CGColor;
    self.orb.layer.shadowColor = AP_BLUE.CGColor;
    self.orb.layer.shadowRadius = 10;
    self.orb.layer.shadowOpacity = 0.9;
    self.orb.layer.shadowOffset = CGSizeZero;
    [self.orb setTitle:@"A" forState:UIControlStateNormal];
    [self.orb setTitleColor:AP_CYAN forState:UIControlStateNormal];
    self.orb.titleLabel.font = APFont(22, YES);

    CAShapeLayer *ring = [CAShapeLayer layer];
    ring.frame = self.orb.bounds;
    ring.path = [UIBezierPath bezierPathWithOvalInRect:CGRectInset(self.orb.bounds, 4, 4)].CGPath;
    ring.fillColor = UIColor.clearColor.CGColor;
    ring.strokeColor = AP_BLUE.CGColor;
    ring.lineWidth = 2;
    ring.lineDashPattern = @[@6, @4];
    [self.orb.layer addSublayer:ring];
    CABasicAnimation *spin = [CABasicAnimation animationWithKeyPath:@"transform.rotation.z"];
    spin.fromValue = @0; spin.toValue = @(2 * M_PI); spin.duration = 3.0;
    spin.repeatCount = HUGE_VALF;
    [ring addAnimation:spin forKey:@"spin"];

    CABasicAnimation *glow = [CABasicAnimation animationWithKeyPath:@"shadowOpacity"];
    glow.fromValue = @0.25; glow.toValue = @1.0; glow.duration = 1.2;
    glow.autoreverses = YES; glow.repeatCount = HUGE_VALF;
    [self.orb.layer addAnimation:glow forKey:@"glow"];

    [self.orb addTarget:self action:@selector(togglePanel) forControlEvents:UIControlEventTouchUpInside];
    [self.orb addGestureRecognizer:[[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(orbPan:)]];
    [root addSubview:self.orb];

    // entrance
    self.orb.alpha = 0;
    self.orb.transform = CGAffineTransformMakeScale(0.2, 0.2);
    [UIView animateWithDuration:0.6 delay:0 usingSpringWithDamping:0.6 initialSpringVelocity:0.8 options:0 animations:^{
        self.orb.alpha = 1;
        self.orb.transform = CGAffineTransformIdentity;
    } completion:nil];

    // ping every 2s (only measures while the HUD is visible)
    NSURLSessionConfiguration *cfg = [NSURLSessionConfiguration ephemeralSessionConfiguration];
    cfg.timeoutIntervalForRequest = 4;
    self.session = [NSURLSession sessionWithConfiguration:cfg];
    self.pingTimer = [NSTimer scheduledTimerWithTimeInterval:2.0 target:self selector:@selector(ping) userInfo:nil repeats:YES];
}

- (void)togglePanel {
    if (self.panel.hidden) {
        UIView *root = self.win.rootViewController.view;
        self.panel.center = CGPointMake(CGRectGetMidX(root.bounds), CGRectGetMidY(root.bounds));
        self.panel.hidden = NO;
        [self.panel playIntro];
    } else {
        [self.panel closeAnimated];
    }
}

- (void)orbPan:(UIPanGestureRecognizer *)g {
    UIView *v = g.view;
    UIView *sv = v.superview;
    CGPoint t = [g translationInView:sv];
    v.center = CGPointMake(v.center.x + t.x, v.center.y + t.y);
    [g setTranslation:CGPointZero inView:sv];
    if (g.state == UIGestureRecognizerStateEnded || g.state == UIGestureRecognizerStateCancelled) {
        CGFloat w = sv.bounds.size.width, h = sv.bounds.size.height;
        CGFloat x = (v.center.x < w / 2) ? 36 : (w - 36);
        CGFloat y = MIN(MAX(v.center.y, 70), h - 70);
        [UIView animateWithDuration:0.5 delay:0 usingSpringWithDamping:0.7 initialSpringVelocity:0.8 options:0 animations:^{
            v.center = CGPointMake(x, y);
        } completion:nil];
    }
}

- (void)ping {
    if (self.hud.hidden) return;
    NSURL *u = [NSURL URLWithString:@"https://www.apple.com/library/test/success.html"];
    NSMutableURLRequest *r = [NSMutableURLRequest requestWithURL:u
                                                     cachePolicy:NSURLRequestReloadIgnoringLocalAndRemoteCacheData
                                                 timeoutInterval:4];
    r.HTTPMethod = @"HEAD";
    CFAbsoluteTime t0 = CFAbsoluteTimeGetCurrent();
    __weak APController *ws = self;
    [[self.session dataTaskWithRequest:r completionHandler:^(NSData *d, NSURLResponse *resp, NSError *e) {
        double ms = (CFAbsoluteTimeGetCurrent() - t0) * 1000.0;
        dispatch_async(dispatch_get_main_queue(), ^{
            APController *s = ws;
            if (!s) return;
            if (e) {
                s.hud.text = @"PING --";
                s.hud.textColor = AP_DIM;
            } else {
                s.hud.text = [NSString stringWithFormat:@"PING %.0fms", ms];
                s.hud.textColor = (ms < 80) ? AP_CYAN : (ms < 180 ? AP_BLUE : UIColor.whiteColor);
            }
        });
    }] resume];
}

@end

void ap_ui_start(void) {
    [[APController shared] setup];
}
