#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <mach/mach.h>
#import <dlfcn.h>
#import "MeshL10n.h"

// ---- IOKit (privat; zur Laufzeit per dlopen laden, kein Link-Stub nötig) ----
typedef mach_port_t io_object_t;
typedef io_object_t io_service_t;
typedef io_object_t io_registry_entry_t;

static NSDictionary* batteryProps(void){
    static void* h=NULL; static dispatch_once_t once; dispatch_once(&once, ^{ h=dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY); });
    if(!h) return nil;
    CFMutableDictionaryRef (*fMatch)(const char*)=dlsym(h,"IOServiceMatching");
    io_service_t (*fGet)(mach_port_t,CFDictionaryRef)=dlsym(h,"IOServiceGetMatchingService");
    kern_return_t (*fProps)(io_registry_entry_t,CFMutableDictionaryRef*,CFAllocatorRef,uint32_t)=dlsym(h,"IORegistryEntryCreateCFProperties");
    kern_return_t (*fRel)(io_object_t)=dlsym(h,"IOObjectRelease");
    if(!fMatch||!fGet||!fProps) return nil;
    io_service_t svc=fGet(0, fMatch("IOPMPowerSource"));   // kIOMasterPortDefault == 0
    if(!svc) return nil;
    CFMutableDictionaryRef props=NULL;
    kern_return_t r=fProps(svc,&props,kCFAllocatorDefault,0);
    if(fRel) fRel(svc);
    if(r!=0 || !props) return nil;
    return (__bridge_transfer NSDictionary*)props;
}

// ---- kleines Theme ----
static UIColor* C(int r,int g,int b){ return [UIColor colorWithRed:r/255.0 green:g/255.0 blue:b/255.0 alpha:1]; }
// Hell & klar (iOS-nativ)
#define BG    C(242,242,247)
#define CARD  [UIColor whiteColor]
#define TRACK C(229,229,234)
#define LINE  C(209,209,214)
#define INK   C(0,0,0)
#define MUT   C(142,142,147)
#define GRN   C(52,199,89)
#define YEL   C(255,149,0)
#define RED   C(255,59,48)

@interface BMStressController : UIViewController @end
// aus BMStress.m
extern NSArray* bmRunGrade(double minutes, double minVolt, double mah, double design, BOOL complete);
extern NSDictionary* bmReadResult(void);

@interface BMViewController : UIViewController @end
@implementation BMViewController {
    UILabel *_pct, *_state;
    UIView *_barFill;
    UIView *_verdictCard;
    UILabel *_verdictGrade, *_verdictNote;
    UIScrollView *_rows;
    NSTimer *_timer;
    CGFloat _barX, _barW;
}

- (void)loadView {
    self.view=[[UIView alloc] initWithFrame:[UIScreen mainScreen].bounds];
    self.view.backgroundColor=BG;
    CGFloat W=self.view.bounds.size.width;

    UILabel*title=[[UILabel alloc] initWithFrame:CGRectMake(0,8,W,22)];
    title.text=L(@"Battery"); title.font=[UIFont boldSystemFontOfSize:15]; title.textColor=MUT; title.textAlignment=NSTextAlignmentCenter; title.backgroundColor=[UIColor clearColor]; [self.view addSubview:title];

    UIButton*testBtn=[UIButton buttonWithType:UIButtonTypeCustom]; testBtn.frame=CGRectMake(W-92,6,86,26);
    [testBtn setTitle:L(@"Test ▸") forState:UIControlStateNormal]; [testBtn setTitleColor:GRN forState:UIControlStateNormal]; testBtn.titleLabel.font=[UIFont boldSystemFontOfSize:13];
    [testBtn addTarget:self action:@selector(openStress) forControlEvents:UIControlEventTouchUpInside]; [self.view addSubview:testBtn];

    _pct=[[UILabel alloc] initWithFrame:CGRectMake(0,30,W,46)];
    _pct.font=[UIFont boldSystemFontOfSize:40]; _pct.textColor=INK; _pct.textAlignment=NSTextAlignmentCenter; _pct.backgroundColor=[UIColor clearColor]; [self.view addSubview:_pct];

    _state=[[UILabel alloc] initWithFrame:CGRectMake(0,76,W,16)];
    _state.font=[UIFont systemFontOfSize:13]; _state.textColor=MUT; _state.textAlignment=NSTextAlignmentCenter; _state.backgroundColor=[UIColor clearColor]; [self.view addSubview:_state];

    // Balken
    _barX=30; _barW=W-60;
    UIView*barBg=[[UIView alloc] initWithFrame:CGRectMake(_barX,98,_barW,10)]; barBg.backgroundColor=TRACK; barBg.layer.cornerRadius=5; [self.view addSubview:barBg];
    _barFill=[[UIView alloc] initWithFrame:CGRectMake(_barX,98,0,10)]; _barFill.backgroundColor=GRN; _barFill.layer.cornerRadius=5; [self.view addSubview:_barFill];

    // Zustands-Note
    _verdictCard=[[UIView alloc] initWithFrame:CGRectMake(16,120,W-32,46)]; _verdictCard.backgroundColor=CARD; _verdictCard.layer.cornerRadius=10; _verdictCard.layer.borderWidth=0.5; _verdictCard.layer.borderColor=LINE.CGColor; [self.view addSubview:_verdictCard];
    _verdictGrade=[[UILabel alloc] initWithFrame:CGRectMake(14,6,W-60,20)]; _verdictGrade.font=[UIFont boldSystemFontOfSize:16]; _verdictGrade.textColor=INK; _verdictGrade.backgroundColor=[UIColor clearColor]; [_verdictCard addSubview:_verdictGrade];
    _verdictNote=[[UILabel alloc] initWithFrame:CGRectMake(14,26,W-60,16)]; _verdictNote.font=[UIFont systemFontOfSize:11]; _verdictNote.textColor=MUT; _verdictNote.backgroundColor=[UIColor clearColor]; [_verdictCard addSubview:_verdictNote];

    // Werte-Bereich (scrollbar)
    _rows=[[UIScrollView alloc] initWithFrame:CGRectMake(16,176,W-32,self.view.bounds.size.height-186)];
    _rows.showsVerticalScrollIndicator=YES; _rows.alwaysBounceVertical=YES;
    _rows.backgroundColor=CARD; _rows.layer.cornerRadius=12; _rows.clipsToBounds=YES;
    _rows.layer.borderWidth=0.5; _rows.layer.borderColor=LINE.CGColor; [self.view addSubview:_rows];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [UIDevice currentDevice].batteryMonitoringEnabled=YES;
    // einmaliger Komplett-Dump aller IOKit-Akkufelder (zur Analyse)
    NSDictionary*b0=batteryProps();
    if(b0){ NSMutableString*s=[NSMutableString string];
        for(NSString*k in [[b0 allKeys] sortedArrayUsingSelector:@selector(compare:)]) [s appendFormat:@"%@ = %@\n",k,b0[k]];
        [s writeToFile:@"/var/mobile/.battdump.txt" atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    }
    [self refresh];
    _timer=[NSTimer scheduledTimerWithTimeInterval:2.0 target:self selector:@selector(refresh) userInfo:nil repeats:YES];
}
- (void)viewWillDisappear:(BOOL)animated { [super viewWillDisappear:animated]; [_timer invalidate]; _timer=nil; }

- (void)openStress {
    BMStressController*s=[[BMStressController alloc] init];
    s.modalTransitionStyle=UIModalTransitionStyleCoverVertical;
    [self presentViewController:s animated:YES completion:nil];
}

static double num(NSDictionary*d,NSString*k){ id v=d[k]; return [v respondsToSelector:@selector(doubleValue)]?[v doubleValue]:NAN; }

- (void)refresh {
    UIDevice*dev=[UIDevice currentDevice];
    NSDictionary*b=batteryProps();

    // Prozent: bevorzugt IOKit CurrentCapacity, sonst UIDevice
    double pct=num(b,@"CurrentCapacity");
    double maxc=num(b,@"MaxCapacity");
    if(!isnan(pct) && !isnan(maxc) && maxc>100) pct=pct/maxc*100.0;   // mAh -> %
    if(isnan(pct)){ float lvl=dev.batteryLevel; pct=(lvl<0)?NAN:lvl*100.0; }
    int ip=isnan(pct)?-1:(int)(pct+0.5);
    _pct.text = ip<0?@"—":[NSString stringWithFormat:@"%d%%",ip];

    BOOL charging = [b[@"IsCharging"] boolValue] || dev.batteryState==UIDeviceBatteryStateCharging;
    BOOL ext = [b[@"ExternalConnected"] boolValue] || dev.batteryState==UIDeviceBatteryStateCharging || dev.batteryState==UIDeviceBatteryStateFull;
    BOOL full = [b[@"FullyCharged"] boolValue] || dev.batteryState==UIDeviceBatteryStateFull;
    _state.text = full?L(@"Fully charged"):(charging?L(@"Charging…"):(ext?L(@"Plugged in"):L(@"On battery")));

    UIColor*col = ip<0?MUT:(ip<=15?RED:(ip<=30?YEL:GRN));
    _pct.textColor = col; _barFill.backgroundColor = col;
    CGFloat frac = ip<0?0:(ip/100.0); if(frac>1)frac=1;
    _barFill.frame = CGRectMake(_barX,98,_barW*frac,10);

    // Detailwerte
    double volt=num(b,@"Voltage");
    double amp=num(b,@"Amperage"); if(isnan(amp)) amp=num(b,@"InstantAmperage");
    double temp=num(b,@"Temperature");
    double curmAh=num(b,@"CurrentCapacity");    // mAh aktuell
    double maxmAh=num(b,@"MaxCapacity");         // mAh voll
    double design=num(b,@"DesignCapacity");      // mAh ab Werk
    double cycles=num(b,@"CycleCount");
    double health = (!isnan(maxmAh)&&!isnan(design)&&design>0)?(maxmAh/design*100.0):NAN;

    // ---- geschätzte Restlaufzeit (Minuten) ----
    double estMin=NAN;        // Entladen: Zeit bis leer
    double fullMin=NAN;       // Laden: Zeit bis voll
    double ttE=num(b,@"AvgTimeToEmpty"); if(isnan(ttE))ttE=num(b,@"TimeRemaining");
    double ttF=num(b,@"AvgTimeToFull");
    if(!charging){
        if(!isnan(ttE)&&ttE>0&&ttE<65000) estMin=ttE;            // IOKit liefert fertigen Wert
        else if(!isnan(amp)&&amp<0){                             // selbst rechnen: mAh / mA * 60
            double remMah=curmAh;
            if(!isnan(remMah)&&remMah<=100&&!isnan(design)&&design>100) remMah=remMah/100.0*design; // % -> mAh
            else if(isnan(remMah)&&!isnan(maxmAh)&&maxmAh>100) remMah=ip/100.0*maxmAh;
            if(!isnan(remMah)&&remMah>0) estMin=remMah/fabs(amp)*60.0;
        }
    } else {
        if(!isnan(ttF)&&ttF>0&&ttF<65000) fullMin=ttF;
    }
    NSString*estStr;
    if(full) estStr=L(@"full");
    else if(!isnan(fullMin)) estStr=LF(@"full in ~%d:%02d",(int)fullMin/60,(int)fullMin%60);
    else if(!isnan(estMin)) estStr=[NSString stringWithFormat:@"~%d:%02d h",(int)estMin/60,(int)estMin%60];
    else if(charging) estStr=L(@"charging…");
    else estStr=@"—";

    NSMutableArray*items=[NSMutableArray array];
    [items addObject:@[L(@"Time left ≈"),   estStr]];
    [items addObject:@[L(@"Charge level"),  (ip<0 ? @"—" : [NSString stringWithFormat:@"%d %%",ip])]];
    [items addObject:@[L(@"Health"),        (isnan(health)? @"—" : [NSString stringWithFormat:@"%.0f %%",health])]];
    [items addObject:@[L(@"Capacity now"),  (isnan(curmAh)? @"—" : [NSString stringWithFormat:@"%.0f mAh",curmAh])]];
    [items addObject:@[L(@"Full capacity"), (isnan(maxmAh)? @"—" : [NSString stringWithFormat:@"%.0f mAh",maxmAh])]];
    [items addObject:@[L(@"Design capacity"),(isnan(design)? @"—" : [NSString stringWithFormat:@"%.0f mAh",design])]];
    [items addObject:@[L(@"Charge cycles"), (isnan(cycles)? @"—" : [NSString stringWithFormat:@"%.0f",cycles])]];
    [items addObject:@[L(@"Voltage"),       (isnan(volt)  ? @"—" : [NSString stringWithFormat:@"%.2f V",volt/1000.0])]];
    [items addObject:@[L(@"Current"),       (isnan(amp)||amp==0 ? L(@"0 mA (idle)") : [NSString stringWithFormat:@"%+.0f mA",amp])]];
    [items addObject:@[L(@"Temperature"),   (isnan(temp)  ? @"—" : [NSString stringWithFormat:@"%.1f °C",temp/100.0])]];
    NSString*serial=b[@"Serial"]; if([serial isKindOfClass:[NSString class]]&&serial.length) [items addObject:@[L(@"Serial no."),serial]];

    // ---- Zustands-Note ----
    NSString*grade; UIColor*gcol; NSString*note;
    if(isnan(health)){
        grade=L(@"Condition: unknown"); gcol=MUT;
        note=(ip<0)?L(@"No battery data available."):L(@"No health data available.");
    } else {
        if(health>=90){ grade=L(@"Condition: Top"); gcol=GRN; }
        else if(health>=80){ grade=L(@"Condition: Very good"); gcol=GRN; }
        else if(health>=65){ grade=L(@"Condition: Good"); gcol=GRN; }
        else if(health>=50){ grade=L(@"Condition: Okay"); gcol=YEL; }
        else { grade=L(@"Condition: Weak"); gcol=RED; }
        grade=[grade stringByAppendingFormat:@"  (%.0f%%)",health];
        NSMutableArray*n=[NSMutableArray array];
        if(!isnan(cycles)) [n addObject:LF(@"%.0f cycles",cycles)];
        if(health<60) [n addObject:L(@"Replacement advisable")];
        if(!isnan(temp)){ double tc=temp/100.0; if(tc>40)[n addObject:L(@"⚠ hot")]; else if(tc<5)[n addObject:L(@"⚠ cold")]; }
        note=n.count?[n componentsJoinedByString:@"  ·  "]:L(@"All in the green.");
    }
    // ---- gemessene Note aus dem Belastungstest hat Vorrang (echter Wert) ----
    NSDictionary*res=bmReadResult();
    if(res){
        double el=[res[@"elapsed"] doubleValue], minv=[res[@"minv"] doubleValue];
        double mah=[res[@"mah"] doubleValue], design=[res[@"design"] doubleValue];
        BOOL died=[res[@"state"] isEqualToString:@"running"];   // hart aus = vollständige Entladung
        NSArray*g=bmRunGrade(el/60.0, minv, mah, design, died);
        UIColor*cc=@[MUT,GRN,YEL,RED][[g[2] intValue]];
        grade=LF(@"Measured: %@", g[0]); gcol=cc;
        note=[NSString stringWithFormat:@"%@%@", g[1], died?@"":L(@" · Test incomplete")];
    } else {
        // vor einem echten Test KEINE Note (Schätzwerte sind irreführend)
        grade=L(@"Not measured yet"); gcol=MUT;
        note=L(@"Tap “Test ▸” for the real value");
    }
    _verdictGrade.text=grade; _verdictGrade.textColor=gcol; _verdictNote.text=note;

    [self drawRows:items];
}

- (void)drawRows:(NSArray *)items {
    for(UIView*v in [_rows.subviews copy]) [v removeFromSuperview];
    CGFloat W=_rows.bounds.size.width, y=0, rh=42;
    for(int i=0;i<(int)items.count;i++){
        NSArray*it=items[i];
        UIView*row=[[UIView alloc] initWithFrame:CGRectMake(0,y,W,rh)];
        row.backgroundColor=[UIColor clearColor];
        UILabel*k=[[UILabel alloc] initWithFrame:CGRectMake(14,0,W*0.55,rh)]; k.text=it[0]; k.font=[UIFont systemFontOfSize:15]; k.textColor=MUT; k.backgroundColor=[UIColor clearColor]; [row addSubview:k];
        UILabel*v=[[UILabel alloc] initWithFrame:CGRectMake(W*0.45-14,0,W*0.55,rh)]; v.text=it[1]; v.font=[UIFont boldSystemFontOfSize:15]; v.textColor=INK; v.textAlignment=NSTextAlignmentRight; v.backgroundColor=[UIColor clearColor]; [row addSubview:v];
        if(i<(int)items.count-1){ UIView*sep=[[UIView alloc] initWithFrame:CGRectMake(14,rh-0.5,W-14,0.5)]; sep.backgroundColor=TRACK; [row addSubview:sep]; }
        [_rows addSubview:row]; y+=rh;
    }
    _rows.contentSize=CGSizeMake(_rows.bounds.size.width, y+8);
}
@end

@interface BMAppDelegate : UIResponder <UIApplicationDelegate>
@property (nonatomic, strong) UIWindow *window;
@end
@implementation BMAppDelegate
- (BOOL)application:(UIApplication *)a didFinishLaunchingWithOptions:(NSDictionary *)o {
    [a setStatusBarHidden:YES withAnimation:UIStatusBarAnimationNone];
    self.window=[[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    self.window.rootViewController=[[BMViewController alloc] init];
    [self.window makeKeyAndVisible];
    return YES;
}
@end
