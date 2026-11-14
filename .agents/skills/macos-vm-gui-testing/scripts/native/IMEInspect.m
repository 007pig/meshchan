#import <Cocoa/Cocoa.h>
#import <Carbon/Carbon.h>
#import <ApplicationServices/ApplicationServices.h>
#import <sys/sysctl.h>
static id attr(AXUIElementRef e,CFStringRef name) {
    CFTypeRef value=NULL;
    AXError error=AXUIElementCopyAttributeValue(e,name,&value);
    return error==kAXErrorSuccess?CFBridgingRelease(value):nil;
}
int main(int argc,const char **argv) {
    @autoreleasepool {
        char model[128]={0}; size_t n=sizeof(model);
        if(sysctlbyname("hw.model",model,&n,NULL,0)||strncmp(model,"VirtualMac",10)) return 65;
        TISInputSourceRef source=TISCopyCurrentKeyboardInputSource();
        NSString *sourceID=(__bridge NSString *)TISGetInputSourceProperty(source,kTISPropertyInputSourceID);
        NSString *name=(__bridge NSString *)TISGetInputSourceProperty(source,kTISPropertyLocalizedName);
        NSMutableDictionary *out=[@{@"sourceID":sourceID?:@"",@"sourceName":name?:@""} mutableCopy];
        CFRelease(source);
        if(argc==1) {
            NSData *json=[NSJSONSerialization dataWithJSONObject:out options:NSJSONWritingPrettyPrinted error:nil];
            puts([[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding].UTF8String); return 0;
        }
        NSString *expected=@(argv[1]);
        NSRunningApplication *front=[[NSWorkspace sharedWorkspace] frontmostApplication];
        out[@"foregroundPID"]=@(front.processIdentifier); out[@"foregroundBundle"]=front.bundleIdentifier?:@"";
        BOOL pass=NO;
        for(NSRunningApplication *app in [[NSWorkspace sharedWorkspace] runningApplications]) {
            if(![app.bundleIdentifier isEqualToString:@"com.apple.TextEdit"]) continue;
            AXUIElementRef ax=AXUIElementCreateApplication(app.processIdentifier);
            AXUIElementRef window=(__bridge AXUIElementRef)attr(ax,kAXFocusedWindowAttribute);
            AXUIElementRef field=(__bridge AXUIElementRef)attr(ax,kAXFocusedUIElementAttribute);
            // Hold strong references for both AX objects across attribute queries.
            if(window) CFRetain(window); if(field) CFRetain(field);
            NSString *document=window?attr(window,kAXDocumentAttribute):nil;
            NSString *title=window?attr(window,kAXTitleAttribute):nil;
            NSString *role=field?attr(field,kAXRoleAttribute):nil;
            NSString *value=field?attr(field,kAXValueAttribute):nil;
            pid_t owner=0; if(field) AXUIElementGetPid(field,&owner);
            out[@"textEditPID"]=@(app.processIdentifier); out[@"focusOwnerPID"]=@(owner);
            out[@"windowTitle"]=title?:@""; out[@"documentURL"]=document?:@"";
            out[@"fieldRole"]=role?:@"";
            BOOL target=[[[NSURL URLWithString:document] path] isEqualToString:expected] || [title isEqualToString:expected.lastPathComponent];
            pass=front.processIdentifier==app.processIdentifier && owner==app.processIdentifier && target && [role isEqualToString:@"AXTextArea"];
            if(target && value) out[@"text"]=value;
            if(window) CFRelease(window); if(field) CFRelease(field); CFRelease(ax);
        }
        out[@"focusVerified"]=@(pass);
        NSData *json=[NSJSONSerialization dataWithJSONObject:out options:NSJSONWritingPrettyPrinted error:nil];
        puts([[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding].UTF8String);
        return pass?0:66;
    }
}
