// Altillo addition to mediaremote-adapter (not part of upstream).
// Copyright (c) 2026 Xus Badia. MIT License.
//
// The adapter runs inside `/usr/bin/perl`, a child of Altillo. If Altillo quits normally it terminates the
// child itself, but a crash or a force quit would leave `perl … stream` orphaned, silently listening for
// ever. This constructor runs when perl loads the framework and exits the process the moment its parent
// goes away: a kqueue process source, so it costs nothing while it waits.

#import <Foundation/Foundation.h>
#include <unistd.h>

static dispatch_source_t altillo_parentSource = NULL;

__attribute__((constructor)) static void altillo_watchParent(void) {
    pid_t parent = getppid();
    if (parent <= 1) {
        // Already orphaned (reparented to launchd): nobody is listening.
        _exit(0);
    }
    dispatch_queue_t queue = dispatch_get_global_queue(QOS_CLASS_UTILITY, 0);
    altillo_parentSource =
        dispatch_source_create(DISPATCH_SOURCE_TYPE_PROC, (uintptr_t)parent, DISPATCH_PROC_EXIT, queue);
    if (altillo_parentSource == NULL) {
        return;
    }
    dispatch_source_set_event_handler(altillo_parentSource, ^{
      _exit(0);
    });
    dispatch_resume(altillo_parentSource);
    // The parent may have died between getppid() and the source being armed.
    if (getppid() != parent) {
        _exit(0);
    }
}
