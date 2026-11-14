#import <Cocoa/Cocoa.h>
#import <ApplicationServices/ApplicationServices.h>
#import <sys/sysctl.h>

int main(int argc, const char **argv) {
    @autoreleasepool {
        char model[128] = {0}; size_t size = sizeof(model);
        if (sysctlbyname("hw.model", model, &size, NULL, 0) || strncmp(model, "VirtualMac", 10)) return 65;
        NSString *base = argc > 3 ? @(argv[3]) : [NSHomeDirectory() stringByAppendingPathComponent:@"utm-ui-isolation"];
        freopen([[base stringByAppendingPathComponent:@"executor.log"] fileSystemRepresentation], "a", stdout);
        freopen([[base stringByAppendingPathComponent:@"executor.log"] fileSystemRepresentation], "a", stderr);
        setbuf(stdout, NULL);
        [NSApplication sharedApplication];
        [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
        [NSApp finishLaunching];
        BOOL ax = AXIsProcessTrustedWithOptions((__bridge CFDictionaryRef)@{(__bridge NSString *)kAXTrustedCheckOptionPrompt:@YES});
        BOOL screen = CGPreflightScreenCaptureAccess();
        if (!screen) screen = CGRequestScreenCaptureAccess();
        uint32_t displayCount = 0;
        CGGetActiveDisplayList(0, NULL, &displayCount);
        printf("accessibility=%d screen=%d displays=%u\n", ax, screen, displayCount);
        if (argc < 3 || !ax || !screen) return 77;
        NSTask *task = [[NSTask alloc] init];
        task.executableURL = [NSURL fileURLWithPath:@"/bin/bash"];
        task.arguments = @[[base stringByAppendingPathComponent:@"guest.sh"], @(argv[1]), @(argv[2]), base];
        NSError *error = nil;
        if (![task launchAndReturnError:&error]) { NSLog(@"%@", error); return 70; }
        while (task.running) [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
        return task.terminationStatus;
    }
}
