// arti_mobile.h
// C header for Arti Mobile FFI
// Auto-generated - do not edit manually

#ifndef ARTI_MOBILE_H
#define ARTI_MOBILE_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/// Start the Arti SOCKS proxy.
/// @param state_dir Directory for Tor state (null-terminated C string)
/// @param cache_dir Directory for Tor cache (null-terminated C string)
/// @param socks_port SOCKS proxy port
/// @param log_fn Callback for log messages
/// @return Result string (caller must free with arti_free_string)
char* arti_start(const char* state_dir,
                 const char* cache_dir,
                 int socks_port,
                 void (*log_fn)(const char*));

/// Stop the Arti proxy.
void arti_stop(void);

/// Get the current SOCKS port.
/// @return Port number, or 0 if not running
int arti_get_socks_port(void);

/// Check if Arti is running.
/// @return 1 if running, 0 otherwise
int arti_is_running(void);

/// Get the current state as a string.
/// @return State string (caller must free with arti_free_string)
char* arti_get_state(void);

/// Free a string returned by Arti functions.
/// @param s String to free (may be NULL)
void arti_free_string(char* s);

#ifdef __cplusplus
}
#endif

#endif // ARTI_MOBILE_H
