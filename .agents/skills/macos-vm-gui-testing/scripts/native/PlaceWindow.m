#import <Cocoa/Cocoa.h>
#import <ApplicationServices/ApplicationServices.h>
#import <sys/sysctl.h>
int main(int argc, const char **argv) {
    @autoreleasepool {
        char model[128]={0}; size_t n=sizeof(model);
        if (argc!=2 || sysctlbyname("hw.model",model,&n,NULL,0) || strncmp(model,"VirtualMac",10)) return 65;
        NSString *path=@(argv[1]);
        for(int attempt=0;attempt<40;attempt++) {
            for(NSRunningApplication *app in [[NSWorkspace sharedWorkspace] runningApplications]) {
                if(![app.bundleIdentifier isEqualToString:@"com.apple.TextEdit"]) continue;
                AXUIElementRef ax=AXUIElementCreateApplication(app.processIdentifier);
                CFArrayRef windows=NULL;
                AXUIElementCopyAttributeValue(ax,kAXWindowsAttribute,(CFTypeRef *)&windows);
                for(id obj in (__bridge NSArray *)windows) {
                    AXUIElementRef window=(__bridge AXUIElementRef)obj;
                    CFStringRef document=NULL, title=NULL;
                    AXUIElementCopyAttributeValue(window,kAXDocumentAttribute,(CFTypeRef *)&document);
                    AXUIElementCopyAttributeValue(window,kAXTitleAttribute,(CFTypeRef *)&title);
                    NSString *documentPath=[[NSURL URLWithString:(__bridge NSString *)document] path];
                    BOOL match=[documentPath isEqualToString:path] || [(__bridge NSString *)title isEqualToString:path.lastPathComponent];
                    if(document) CFRelease(document); if(title) CFRelease(title);
                    if(!match) continue;
                    CGPoint p=CGPointMake(80,80); CGSize s=CGSizeMake(770,670);
                    AXValueRef pv=AXValueCreate(kAXValueCGPointType,&p), sv=AXValueCreate(kAXValueCGSizeType,&s);
                    AXError e1=AXUIElementSetAttributeValue(window,kAXPositionAttribute,pv);
                    AXError e2=AXUIElementSetAttributeValue(window,kAXSizeAttribute,sv);
                    [app activateWithOptions:0];
                    AXError mainError=AXUIElementSetAttributeValue(window,kAXMainAttribute,kCFBooleanTrue);
                    AXError e3=AXUIElementPerformAction(window,kAXRaiseAction);
                    CFRelease(pv); CFRelease(sv); if(windows) CFRelease(windows); CFRelease(ax);
                    printf("target=%s placement=%d,%d main=%d raise=%d\n",path.lastPathComponent.UTF8String,e1,e2,mainError,e3);
                    return (e1||e2||mainError||e3)?1:0;
                }
                if(windows) CFRelease(windows); CFRelease(ax);
            }
            [NSThread sleepForTimeInterval:0.25];
        }
        fprintf(stderr,"Dedicated TextEdit window not found\n"); return 1;
    }
}
