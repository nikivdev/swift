#ifndef LAUNCHER_FFI_H
#define LAUNCHER_FFI_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// Result codes
typedef enum {
    LAUNCHER_DISMISSED = 0,
    LAUNCHER_SUBMITTED = 1,
    LAUNCHER_COMMAND = 2,   // Cmd+Return
    LAUNCHER_OPTION = 3     // Option+Return
} LauncherResultCode;

// Callback type for async launcher
typedef void (*launcher_callback_t)(int32_t result, const char* query, void* context);

// Show launcher asynchronously - callback is called when dismissed
void launcher_show(const char* placeholder, launcher_callback_t callback, void* context);

// Show launcher synchronously - blocks until dismissed
// Returns result code, writes query to buffer
int32_t launcher_show_sync(const char* placeholder, char* query_buffer, int32_t buffer_size);

// Hide the launcher programmatically
void launcher_hide(void);

// Check if launcher is visible
int32_t launcher_is_visible(void);

#ifdef __cplusplus
}
#endif

#endif // LAUNCHER_FFI_H
