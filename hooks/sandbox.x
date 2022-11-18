#import "hooks.h"

#import <mach/mach_traps.h>
#import <mach/host_special_ports.h>

#import <sandbox.h>

void* (SecTaskCopyValueForEntitlement)(void* task, CFStringRef entitlement, CFErrorRef  _Nullable *error);
void* (SecTaskCreateFromSelf)(CFAllocatorRef allocator);

%group shadowhook_sandbox
%hookf(kern_return_t, task_for_pid, task_port_t task, pid_t pid, task_port_t *target) {
    // Check if the app has this entitlement (likely not).
    CFErrorRef err = nil;
    NSArray* ent = (__bridge NSArray *)SecTaskCopyValueForEntitlement(SecTaskCreateFromSelf(NULL), CFSTR("get-task-allow"), &err);

    if(!ent || true) {
        HBLogDebug(@"%@: %@", @"deny task_for_pid", @(pid));
        return KERN_FAILURE;
    }

    return %orig;
}

%hookf(int, raise, int sig) {
    HBLogDebug(@"%@: %d", @"raise", sig);
    return %orig;
}

%hookf(int, kill, pid_t pid, int sig) {
    HBLogDebug(@"%@: %d", @"kill", sig);
    return %orig;
}

%hookf(sig_t, signal, int sig, sig_t func) {
    HBLogDebug(@"%@: %d", @"signal", sig);
    return %orig;
}

%hookf(int, sigaction, int sig, const struct sigaction *restrict act, struct sigaction *restrict oact) {
    HBLogDebug(@"%@: %d", @"sigaction", sig);
    return %orig;
}

%hookf(kern_return_t, host_get_special_port, host_priv_t host_priv, int node, int which, mach_port_t *port) {
    // interesting ports: 4, HOST_SEATBELT_PORT, HOST_PRIV_PORT
    HBLogDebug(@"%@: %d", @"host_get_special_port", which);

    if(node == HOST_LOCAL_NODE) {
        if(which == HOST_PRIV_PORT) {
            if(port) {
                *port = MACH_PORT_NULL;
            }

            return KERN_SUCCESS;
        }

        if(which == 4 /* kernel (hgsp4) */) {
            return KERN_FAILURE;
        }

        if(which == HOST_SEATBELT_PORT) {
            return KERN_FAILURE;
        }
    }

    return %orig;
}
%end

static int (*original_sandbox_check)(pid_t pid, const char *operation, enum sandbox_filter_type type, ...);
static int replaced_sandbox_check(pid_t pid, const char *operation, enum sandbox_filter_type type, ...) {
    void* data;
    va_list args;
    va_start(args, type);
    data = va_arg(args, void*);
    va_end(args);

    if(operation) {
        NSString* op = @(operation);

        if(data) {
            HBLogDebug(@"%@: %@: %s", @"sandbox_check", op, (const char *)data);
        } else {
            HBLogDebug(@"%@: %@", @"sandbox_check", op);
        }
    }

    return original_sandbox_check(pid, operation, type, data);
}

void shadowhook_sandbox(void) {
    %init(shadowhook_sandbox);

    MSHookFunction(sandbox_check, replaced_sandbox_check, (void **) &original_sandbox_check);
}
