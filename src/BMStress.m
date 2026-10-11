#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <mach/mach.h>
#import <dlfcn.h>
#import <math.h>
#import "MeshL10n.h"

// ---- IOKit-Helfer (für diese Datei) ----
typedef mach_port_t io_object_t; typedef io_object_t io_service_t; typedef io_object_t io_registry_entry_t;
static NSDictionary* sProps(void){
    static void* h=NULL; static dispatch_once_t once; dispatch_once(&once, ^{ h=dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY); });
    if(!h) return nil;
    CFMutableDictionaryRef (*fMatch)(const char*)=dlsym(h,"IOServiceMatching");
    io_service_t (*fGet)(mach_port_t,CFDictionaryRef)=dlsym(h,"IOServiceGetMatchingService");
    kern_return_t (*fProps)(io_registry_entry_t,CFMutableDictionaryRef*,CFAllocatorRef,uint32_t)=dlsym(h,"IORegistryEntryCreateCFProperties");
    kern_return_t (*fRel)(io_object_t)=dlsym(h,"IOObjectRelease");
    if(!fMatch||!fGet||!fProps) return nil;
    io_service_t svc=fGet(0, fMatch("IOPMPowerSource")); if(!svc) return nil;
    CFMutableDictionaryRef p=NULL; kern_return_t r=fProps(svc,&p,kCFAllocatorDefault,0); if(fRel)fRel(svc);
    if(r!=0||!p) return nil; return (__bridge_transfer NSDictionary*)p;
}
static double sNum(NSDictionary*d,NSString*k){ id v=d[k]; return [v respondsToSelector:@selector(doubleValue)]?[v doubleValue]:NAN; }

// ---- CPU-Volllast ----
static volatile int gRun=0;
static void startLoad(void){
    gRun=1;
    for(int i=0;i<2;i++) dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH,0), ^{
        volatile double x=1.123456;
        while(gRun){ for(int k=0;k<400000;k++){ x=sqrt(fabs(x*1.0001)+1.0)+sin(x)+cos(x*0.5); } }
    });
}
static void stopLoad(void){ gRun=0; }

static UIColor* SC(int r,int g,int b){ return [UIColor colorWithRed:r/255.0 green:g/255.0 blue:b/255.0 alpha:1]; }
// Hell & klar (wie BMApp)
#define SBG  SC(242,242,247)
#define SINK SC(0,0,0)
#define SMUT SC(142,142,147)
#define SGRN SC(52,199,89)
#define SYEL SC(255,149,0)
#define SRED SC(255,59,48)
#define LOGPATH @"/var/mobile/.batttest"
#define RESPATH @"/var/mobile/.batttest-result"

// ---- geteilt mit BMApp.m: Note aus dem Belastungstest ----
// Primär: entnommene Kapazität (mAh) / Design-Kapazität -> Gesundheit %.
// Fallback: Laufzeit unter Volllast, wenn kein brauchbarer Stromwert vorlag.
// Rückgabe: @[gradeText, noteText, @(colorcode 0=mut 1=grn 2=yel 3=red)]
NSArray* bmRunGrade(double minutes, double minVolt, double mah, double design, BOOL complete){
    double health = (mah>0 && design>100) ? (mah/design*100.0) : NAN;
    NSString*g; int c; NSMutableString*n=[NSMutableString string];
    if(!isnan(health)){
        if(health>=80){ g=L(@"Top"); c=1; }
        else if(health>=65){ g=L(@"Good"); c=1; }
        else if(health>=50){ g=L(@"Okay"); c=2; }
        else if(health>=35){ g=L(@"Weak"); c=3; }
        else { g=L(@"Poor"); c=3; }
        [n appendFormat:L(@"%.0f%% health · %.0f/%.0f mAh · %.0f min"), health, mah, design, minutes];
    } else {
        if(minutes>=150){ g=L(@"Very good"); c=1; }
        else if(minutes>=110){ g=L(@"Good"); c=1; }
        else if(minutes>=75){ g=L(@"Okay"); c=2; }
        else { g=L(@"Weak"); c=3; }
        [n appendFormat:L(@"%.0f min under full load"), minutes];
    }
    if(!isnan(minVolt)&&minVolt>0){
        if(minVolt<3.3 && c<3)c++; if(minVolt<3.1)c=3;   // Spannungseinbruch verschärft
        [n appendFormat:@" · min %.2f V", minVolt];
    }
    if(!complete) [n appendString:L(@" · incomplete")];
    return @[g, n, @(c)];
}

// Ergebnisdatei lesen (für Hauptschirm + Verlauf). nil wenn keiner.
NSDictionary* bmReadResult(void){
    NSString*s=[NSString stringWithContentsOfFile:RESPATH encoding:NSUTF8StringEncoding error:NULL];
    if(!s.length) return nil;
    NSMutableDictionary*d=[NSMutableDictionary dictionary];
    for(NSString*line in [s componentsSeparatedByString:@"\n"]){
        NSRange r=[line rangeOfString:@"="]; if(r.location==NSNotFound) continue;
        d[[line substringToIndex:r.location]]=[line substringFromIndex:r.location+1];
    }
    return d.count?d:nil;
}

@interface BMStressController : UIViewController @end
@implementation BMStressController {
    int _phase;                 // 0 idle, 1 armed, 2 running, 3 done
    NSTimeInterval _start;
    double _minVolt, _maxTemp; int _startPct;
    double _mahSum, _design, _lastEl;   // integrierte Kapazität (mAh), Design-Kapazität
    UILabel *_status, *_time, *_info, *_prev;
    UIButton *_btn, *_back;
    NSTimer *_t;
    NSMutableString *_log;
    NSFileHandle *_fh;
}

// schreibt JEDE Sekunde ein in sich geschlossenes Ergebnis weg — übersteht
// das harte Abschalten am Testende (finish: läuft dann evtl. nie)
- (void)saveResult:(NSString *)state elapsed:(double)el pct:(int)pct ended:(NSString *)ended {
    NSString*s=[NSString stringWithFormat:
        @"state=%@\nstart=%.0f\nstartpct=%d\nelapsed=%.0f\ncurpct=%d\nminv=%.3f\nmaxt=%.2f\nmah=%.1f\ndesign=%.0f\ndate=%@\nended=%@\n",
        state, _start, _startPct, el, pct, _minVolt, _maxTemp, _mahSum, _design, [NSDateFormatter localizedStringFromDate:[NSDate date] dateStyle:NSDateFormatterShortStyle timeStyle:NSDateFormatterShortStyle], ended?:@""];
    [s writeToFile:RESPATH atomically:YES encoding:NSUTF8StringEncoding error:NULL];
}

- (void)loadView {
    self.view=[[UIView alloc] initWithFrame:[UIScreen mainScreen].bounds];
    self.view.backgroundColor=SBG;
    CGFloat W=self.view.bounds.size.width, H=self.view.bounds.size.height;

    _back=[UIButton buttonWithType:UIButtonTypeCustom]; _back.frame=CGRectMake(6,8,70,34);
    [_back setTitle:L(@"‹ Back") forState:UIControlStateNormal]; [_back setTitleColor:SINK forState:UIControlStateNormal];
    _back.titleLabel.font=[UIFont systemFontOfSize:14]; _back.contentHorizontalAlignment=UIControlContentHorizontalAlignmentLeft;
    [_back addTarget:self action:@selector(goBack) forControlEvents:UIControlEventTouchUpInside]; [self.view addSubview:_back];

    UILabel*title=[[UILabel alloc] initWithFrame:CGRectMake(70,8,W-140,34)];
    title.text=L(@"Stress test"); title.font=[UIFont boldSystemFontOfSize:16]; title.textColor=SINK; title.textAlignment=NSTextAlignmentCenter; title.backgroundColor=[UIColor clearColor]; [self.view addSubview:title];

    _status=[[UILabel alloc] initWithFrame:CGRectMake(20,70,W-40,60)]; _status.numberOfLines=0; _status.font=[UIFont systemFontOfSize:15]; _status.textColor=SMUT; _status.textAlignment=NSTextAlignmentCenter; _status.backgroundColor=[UIColor clearColor]; [self.view addSubview:_status];

    _time=[[UILabel alloc] initWithFrame:CGRectMake(0,140,W,56)]; _time.font=[UIFont boldSystemFontOfSize:46]; _time.textColor=SINK; _time.textAlignment=NSTextAlignmentCenter; _time.backgroundColor=[UIColor clearColor]; [self.view addSubview:_time];

    _info=[[UILabel alloc] initWithFrame:CGRectMake(20,206,W-40,80)]; _info.numberOfLines=0; _info.font=[UIFont systemFontOfSize:14]; _info.textColor=SMUT; _info.textAlignment=NSTextAlignmentCenter; _info.backgroundColor=[UIColor clearColor]; [self.view addSubview:_info];

    _btn=[UIButton buttonWithType:UIButtonTypeCustom]; _btn.frame=CGRectMake(40,H-150,W-80,52); _btn.backgroundColor=SGRN; _btn.layer.cornerRadius=26;
    _btn.titleLabel.font=[UIFont boldSystemFontOfSize:17]; [_btn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [_btn addTarget:self action:@selector(tapBtn) forControlEvents:UIControlEventTouchUpInside]; [self.view addSubview:_btn];

    _prev=[[UILabel alloc] initWithFrame:CGRectMake(20,H-84,W-40,60)]; _prev.numberOfLines=0; _prev.font=[UIFont systemFontOfSize:12]; _prev.textColor=SMUT; _prev.textAlignment=NSTextAlignmentCenter; _prev.backgroundColor=[UIColor clearColor]; [self.view addSubview:_prev];
    _prev.text=[self lastResult];
}

- (NSString *)lastResult {
    NSDictionary*d=bmReadResult(); if(!d) return @"";
    double el=[d[@"elapsed"] doubleValue], minv=[d[@"minv"] doubleValue], maxt=[d[@"maxt"] doubleValue];
    double mah=[d[@"mah"] doubleValue], design=[d[@"design"] doubleValue];
    BOOL died=[d[@"state"] isEqualToString:@"running"];   // war „running" -> Gerät ging hart aus = vollständig
    NSArray*g=bmRunGrade(el/60.0, minv, mah, design, died);
    return [NSString stringWithFormat:L(@"Last test (%@): grade %@\nRan %@%@  ·  min %.2f V  ·  max %.1f°C"),
            d[@"date"]?:@"?", g[0], fmtT(el), died?L(@" until shutdown"):@"", minv, maxt];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    _phase=0; _time.text=@"";
    _t=[NSTimer scheduledTimerWithTimeInterval:1.0 target:self selector:@selector(tick) userInfo:nil repeats:YES];
    [UIApplication sharedApplication].idleTimerDisabled=YES;   // Screen bleibt an, solange Test-Screen offen
    // Test MUSS abbrechen, wenn die App in den Hintergrund geht oder der Screen gesperrt wird
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(appLeft) name:UIApplicationWillResignActiveNotification object:nil];
    [self tick];
}
- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated]; [_t invalidate]; _t=nil;
    [UIApplication sharedApplication].idleTimerDisabled=NO;
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}
- (void)appLeft { if(_phase==2){ [self finish:@"Abgebrochen: App verlassen / gesperrt"]; } }

static NSString* fmtT(double s){ int t=(int)s; return [NSString stringWithFormat:@"%d:%02d:%02d",t/3600,(t/60)%60,t%60]; }

- (void)tick {
    NSDictionary*b=sProps();
    double cur=sNum(b,@"CurrentCapacity"), mx=sNum(b,@"MaxCapacity");
    int pct = (!isnan(cur)&&!isnan(mx)&&mx>0)?(int)(cur/mx*100.0+0.5):-1;
    BOOL charging=[b[@"IsCharging"] boolValue], ext=[b[@"ExternalConnected"] boolValue];
    double volt=sNum(b,@"Voltage")/1000.0, temp=sNum(b,@"Temperature")/100.0;
    double amp=sNum(b,@"Amperage"); if(isnan(amp))amp=sNum(b,@"InstantAmperage");
    double design=sNum(b,@"DesignCapacity");

    if(_phase==0){
        BOOL ready = (pct>=99) && (charging||ext);
        _btn.enabled=ready; _btn.alpha=ready?1.0:0.4; _btn.backgroundColor=SGRN;
        [_btn setTitle:L(@"Start test") forState:UIControlStateNormal];
        _status.text = ready ? L(@"Ready. After “Start test”, unplug the cable — then the test begins.")
                             : [NSString stringWithFormat:L(@"Charge to 100%% and keep the cable plugged in.\n(currently %@%@)"), pct<0?@"—":[NSString stringWithFormat:@"%d%%",pct], (charging||ext)?L(@", charging"):L(@", NOT plugged in")];
        _info.text=@"";
    }
    else if(_phase==1){
        _status.text=L(@"⚡ Unplug the cable NOW — the test starts automatically.");
        _btn.backgroundColor=SRED; [_btn setTitle:L(@"Cancel") forState:UIControlStateNormal];
        if(!charging && !ext){ // abgezogen -> los
            _phase=2; _start=[NSDate timeIntervalSinceReferenceDate]; _startPct=pct;
            _minVolt=(!isnan(volt)&&volt>0)?volt:99; _maxTemp=isnan(temp)?0:temp;
            _mahSum=0; _lastEl=0; _design=(!isnan(design)&&design>100)?design:930; // iPod touch 4 ≈ 930 mAh
            NSString*hdr=[NSString stringWithFormat:@"Belastungstest %@ — Start %d%%, %.2fV\n",[NSDate date],pct,volt];
            [hdr writeToFile:LOGPATH atomically:YES encoding:NSUTF8StringEncoding error:NULL];
            _fh=[NSFileHandle fileHandleForWritingAtPath:LOGPATH]; [_fh seekToEndOfFile];
            [self saveResult:@"running" elapsed:0 pct:pct ended:nil];
            [UIApplication sharedApplication].idleTimerDisabled=YES;
            startLoad();
        }
    }
    else if(_phase==2){
        double el=[NSDate timeIntervalSinceReferenceDate]-_start;
        if(!isnan(volt)&&volt>0&&volt<_minVolt)_minVolt=volt;
        if(!isnan(temp)&&temp>_maxTemp)_maxTemp=temp;
        // Kapazität integrieren: Strom(mA) × Zeit(h) = mAh
        if(!isnan(amp)&&amp!=0){ double dt=el-_lastEl; if(dt>0&&dt<10) _mahSum+=fabs(amp)*(dt/3600.0); }
        _lastEl=el; if(_design<=0&&!isnan(design))_design=design;
        double drained=_startPct-pct; double rate=(el>30)?(drained/(el/60.0)):NAN;
        _time.text=fmtT(el);
        _time.textColor = (temp>42)?SRED:(temp>38?SYEL:SINK);
        _info.text=[NSString stringWithFormat:L(@"%d%%  ·  %.2f V  ·  %.1f °C\ndrained: %.0f mAh   min V: %.2f   max T: %.1f°C"),
                    pct, volt, temp, _mahSum, _minVolt, _maxTemp];
        _status.text = (volt<3.5)?L(@"⚠ Voltage dropping — battery will die soon"):L(@"Running under full load …");
        _btn.backgroundColor=SRED; [_btn setTitle:L(@"Stop") forState:UIControlStateNormal];

        NSString*ln=[NSString stringWithFormat:@"t=%d  %d%%  %.2fV  %.1fC  rate=%@\n",(int)el,pct,volt,temp,isnan(rate)?@"-":[NSString stringWithFormat:@"%.1f",rate]];
        @try { [_fh writeData:[ln dataUsingEncoding:NSUTF8StringEncoding]]; } @catch(__unused id e) {}
        [self saveResult:@"running" elapsed:el pct:pct ended:nil];   // überlebt hartes Aus

        if(temp>44){ [self finish:@"Sicherheits-Stopp: zu heiß (>44°C)"]; }
        else if(charging||ext){ [self finish:@"Abgebrochen: wieder am Kabel"]; }
    }
}

- (void)tapBtn {
    if(_phase==0){ _phase=1; }
    else if(_phase==1){ _phase=0; }
    else if(_phase==2){ [self finish:@"Manuell gestoppt"]; }
    else if(_phase==3){ _phase=0; _time.text=@""; }
    [self tick];
}

- (void)finish:(NSString *)reason {
    stopLoad(); [UIApplication sharedApplication].idleTimerDisabled=NO;
    _phase=3;
    double el=[NSDate timeIntervalSinceReferenceDate]-_start;
    NSString*end=[NSString stringWithFormat:@"ENDE: %@ nach %@ (min V %.2f, max T %.1f)\n",reason,fmtT(el),_minVolt,_maxTemp];
    @try { [_fh writeData:[end dataUsingEncoding:NSUTF8StringEncoding]]; [_fh closeFile]; } @catch(__unused id e) {}
    _fh=nil;
    [self saveResult:@"done" elapsed:el pct:_startPct ended:reason];
    // vorzeitig gestoppt -> keine echte volle Entladung
    NSArray*g=bmRunGrade(el/60.0, _minVolt, _mahSum, _design, NO);
    _status.text=[NSString stringWithFormat:L(@"Grade: %@"),g[0]];
    _btn.backgroundColor=SGRN; [_btn setTitle:L(@"New test") forState:UIControlStateNormal]; _btn.enabled=YES; _btn.alpha=1;
    _prev.text=[NSString stringWithFormat:L(@"Ran %@ (from %d%%)  ·  %@"),fmtT(el),_startPct,g[1]];
}

- (void)goBack { stopLoad(); [UIApplication sharedApplication].idleTimerDisabled=NO; [self dismissViewControllerAnimated:YES completion:nil]; }
@end
