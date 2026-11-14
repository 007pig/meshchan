#import <Foundation/Foundation.h>
#import <ApplicationServices/ApplicationServices.h>
#import <sys/sysctl.h>
static void key(CGKeyCode code, CGEventFlags flags) {
    CGEventSourceRef source=CGEventSourceCreate(kCGEventSourceStatePrivate);
    for(int down=1;down>=0;down--) {
        CGEventRef e=CGEventCreateKeyboardEvent(source,code,down);
        CGEventSetFlags(e,down?flags:0);
        CGEventPost(kCGSessionEventTap,e);
        CFRelease(e); usleep(20000);
    }
    CFRelease(source);
}
int main(int argc,const char **argv) {
    @autoreleasepool {
        char model[128]={0}; size_t n=sizeof(model);
        if(argc<2||sysctlbyname("hw.model",model,&n,NULL,0)||strncmp(model,"VirtualMac",10)) return 65;
        if(!AXIsProcessTrusted()) return 77;
        printf("key flags before=0x%llx\n",(unsigned long long)CGEventSourceFlagsState(kCGEventSourceStateCombinedSessionState));
        NSString *op=@(argv[1]);
        if([op isEqual:@"end"]) { key(125,kCGEventFlagMaskCommand); return 0; }
        if([op isEqual:@"save"]) { key(1,kCGEventFlagMaskCommand); return 0; }
        if([op isEqual:@"return"]) { key(36,0); return 0; }
        if([op isEqual:@"space"]) { key(49,0); return 0; }
        if([op isEqual:@"switch"]) { key(49,kCGEventFlagMaskControl); return 0; }
        if([op isEqual:@"next-source"]) { key(49,kCGEventFlagMaskControl|kCGEventFlagMaskAlternate); return 0; }
        if([op isEqual:@"escape"]) { key(53,0); return 0; }
        if([op isEqual:@"reset"]) {
            for(NSNumber *code in @[@55,@54,@56,@60,@58,@61,@59,@62]) {
                CGEventRef e=CGEventCreateKeyboardEvent(NULL,code.unsignedShortValue,false);
                CGEventSetFlags(e,0); CGEventPost(kCGSessionEventTap,e); CFRelease(e);
            }
            CGEventRef current=CGEventCreate(NULL);
            CGPoint location=CGEventGetLocation(current); CFRelease(current);
            const CGEventType ups[]={kCGEventLeftMouseUp,kCGEventRightMouseUp,kCGEventOtherMouseUp};
            const CGMouseButton buttons[]={kCGMouseButtonLeft,kCGMouseButtonRight,kCGMouseButtonCenter};
            for(int i=0;i<3;i++) {
                CGEventRef e=CGEventCreateMouseEvent(NULL,ups[i],location,buttons[i]);
                CGEventSetFlags(e,0); CGEventPost(kCGSessionEventTap,e); CFRelease(e);
            }
            return 0;
        }
        if(argc!=3||![op isEqual:@"type"]) return 64;
        NSString *text=@(argv[2]);
        NSString *letters=@"abcdefghijklmnopqrstuvwxyz0123456789-";
        const CGKeyCode codes[]={0,11,8,2,14,3,5,4,34,38,40,37,46,45,31,35,12,15,1,17,32,9,13,7,16,6,29,18,19,20,21,23,22,26,28,25,27};
        for(NSUInteger i=0;i<text.length;i++) {
            NSString *c=[text substringWithRange:NSMakeRange(i,1)];
            NSRange r=[letters rangeOfString:c.lowercaseString];
            if(r.location==NSNotFound) return 64;
            BOOL upper=![c isEqualToString:c.lowercaseString];
            key(codes[r.location],upper?kCGEventFlagMaskShift:0);
        }
        return 0;
    }
}
