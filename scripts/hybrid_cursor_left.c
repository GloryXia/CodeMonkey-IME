#include <ApplicationServices/ApplicationServices.h>
#include <CoreFoundation/CoreFoundation.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

static void build_log_path(char *buffer, size_t size) {
    const char *home = getenv("HOME");
    if (home == NULL || home[0] == '\0') {
        snprintf(buffer, size, "/tmp/hybrid_cursor_left.log");
        return;
    }
    snprintf(buffer, size, "%s/Library/Rime/hybrid_cursor_left.log", home);
}

static void log_line(const char *format, ...) {
    char path[1024];
    build_log_path(path, sizeof(path));

    FILE *file = fopen(path, "a");
    if (file == NULL) {
        return;
    }

    va_list args;
    va_start(args, format);
    vfprintf(file, format, args);
    va_end(args);
    fputc('\n', file);
    fclose(file);
}

static void sleep_millis(useconds_t millis) {
    usleep(millis * 1000);
}

static AXError copy_attribute_with_retry(
    AXUIElementRef element,
    CFStringRef attribute,
    CFTypeRef *value,
    int attempts,
    useconds_t delay_millis
) {
    AXError error = kAXErrorFailure;
    for (int i = 0; i < attempts; i++) {
        error = AXUIElementCopyAttributeValue(element, attribute, value);
        if (error == kAXErrorSuccess && *value != NULL) {
            return error;
        }
        if (error != kAXErrorCannotComplete) {
            return error;
        }
        sleep_millis(delay_millis);
    }
    return error;
}

static AXError copy_focused_element_with_fallback(
    AXUIElementRef system_wide,
    AXUIElementRef *focused
) {
    AXError error = copy_attribute_with_retry(
        system_wide,
        kAXFocusedUIElementAttribute,
        (CFTypeRef *)focused,
        8,
        20
    );
    if (error == kAXErrorSuccess && *focused != NULL) {
        return error;
    }

    AXUIElementRef focused_app = NULL;
    AXError app_error = copy_attribute_with_retry(
        system_wide,
        kAXFocusedApplicationAttribute,
        (CFTypeRef *)&focused_app,
        8,
        20
    );
    if (app_error != kAXErrorSuccess || focused_app == NULL) {
        return error;
    }

    error = copy_attribute_with_retry(
        focused_app,
        kAXFocusedUIElementAttribute,
        (CFTypeRef *)focused,
        8,
        20
    );
    CFRelease(focused_app);
    return error;
}

static AXError set_attribute_with_retry(
    AXUIElementRef element,
    CFStringRef attribute,
    CFTypeRef value,
    int attempts,
    useconds_t delay_millis
) {
    AXError error = kAXErrorFailure;
    for (int i = 0; i < attempts; i++) {
        error = AXUIElementSetAttributeValue(element, attribute, value);
        if (error == kAXErrorSuccess) {
            return error;
        }
        if (error != kAXErrorCannotComplete) {
            return error;
        }
        sleep_millis(delay_millis);
    }
    return error;
}

int main(int argc, char *argv[]) {
    double delay_seconds = 0.0;
    if (argc > 1) {
        delay_seconds = atof(argv[1]);
    }

    if (delay_seconds > 0.0) {
        useconds_t micros = (useconds_t)(delay_seconds * 1000000.0);
        usleep(micros);
    }

    const void *keys[] = { kAXTrustedCheckOptionPrompt };
    const void *values[] = { kCFBooleanTrue };
    CFDictionaryRef options = CFDictionaryCreate(
        kCFAllocatorDefault,
        keys,
        values,
        1,
        &kCFCopyStringDictionaryKeyCallBacks,
        &kCFTypeDictionaryValueCallBacks
    );
    Boolean trusted = AXIsProcessTrustedWithOptions(options);
    if (options != NULL) {
        CFRelease(options);
    }
    if (!trusted) {
        log_line("trusted=false");
        return 1;
    }

    AXUIElementRef system_wide = AXUIElementCreateSystemWide();
    if (system_wide == NULL) {
        log_line("system_wide=null");
        return 1;
    }

    AXUIElementRef focused = NULL;
    AXError focus_error = copy_focused_element_with_fallback(system_wide, &focused);
    CFRelease(system_wide);
    if (focus_error != kAXErrorSuccess || focused == NULL) {
        log_line("focused error=%d", focus_error);
        return 1;
    }

    AXValueRef selected_range = NULL;
    AXError range_error = copy_attribute_with_retry(
        focused,
        kAXSelectedTextRangeAttribute,
        (CFTypeRef *)&selected_range,
        8,
        20
    );
    if (range_error != kAXErrorSuccess || selected_range == NULL) {
        log_line("selected_range error=%d", range_error);
        CFRelease(focused);
        return 1;
    }

    CFRange range;
    Boolean ok = AXValueGetValue(selected_range, kAXValueCFRangeType, &range);
    CFRelease(selected_range);
    if (!ok) {
        log_line("selected_range decode failed");
        CFRelease(focused);
        return 1;
    }

    log_line("before location=%ld length=%ld", (long)range.location, (long)range.length);

    if (range.length > 0) {
        range.length = 0;
    } else if (range.location > 0) {
        range.location -= 1;
        range.length = 0;
    }

    AXValueRef new_range = AXValueCreate(kAXValueCFRangeType, &range);
    if (new_range == NULL) {
        log_line("new_range=null");
        CFRelease(focused);
        return 1;
    }

    AXError set_error = set_attribute_with_retry(
        focused,
        kAXSelectedTextRangeAttribute,
        new_range,
        8,
        20
    );
    CFRelease(new_range);
    CFRelease(focused);

    if (set_error != kAXErrorSuccess) {
        log_line("set_range error=%d", set_error);
        return 1;
    }

    log_line("after location=%ld length=%ld", (long)range.location, (long)range.length);
    return 0;
}
