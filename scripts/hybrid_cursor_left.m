#import <ApplicationServices/ApplicationServices.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

int main(int argc, char *argv[]) {
    CGKeyCode keycode = 123;  // Left arrow
    int arg_offset = 1;

    if (argc > 1) {
        if (strcmp(argv[1], "right") == 0) {
            keycode = 124;
            arg_offset = 2;
        } else if (strcmp(argv[1], "left") == 0) {
            keycode = 123;
            arg_offset = 2;
        }
    }

    double delay_seconds = 0.0;
    if (argc > arg_offset) {
        delay_seconds = atof(argv[arg_offset]);
    }

    if (delay_seconds > 0.0) {
        usleep((useconds_t)(delay_seconds * 1000000.0));
    }

    // Determine target location for event tap
    CGEventTapLocation location = kCGSessionEventTap; // Often works better for background tools

    CGEventRef key_down = CGEventCreateKeyboardEvent(NULL, keycode, true);
    CGEventRef key_up = CGEventCreateKeyboardEvent(NULL, keycode, false);
    if (!key_down || !key_up) {
        if (key_down) CFRelease(key_down);
        if (key_up) CFRelease(key_up);
        return 1;
    }

    CGEventSetFlags(key_down, 0);
    CGEventSetFlags(key_up, 0);

    CGEventPost(location, key_down);
    CGEventPost(location, key_up);

    CFRelease(key_down);
    CFRelease(key_up);
    return 0;
}
