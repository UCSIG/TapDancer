/// @file debug.h
#ifndef H_DEBUG
#define H_DEBUG

#include <Arduino.h>
#include <stdint.h>
#include <stdbool.h>

#define console_printf(_fmt, ...) Serial.printf(_fmt, ##__VA_ARGS__)

#define LOG_NONE                  0
#define LOG_ERROR                 1
#define LOG_WARNING               2
#define LOG_INFO                  3
#define LOG_DEBUG                 4
#define LOG_TRACE                 5

/* ------------------------------ SET LOG LEVEL ----------------------------- */
#ifndef CONFIG_LOG_LEVEL
#define CONFIG_LOG_LEVEL LOG_DEBUG
// #define CONFIG_LOG_LEVEL LOG_NONE
#endif
/* -------------------------------------------------------------------------- */

/* --------------------------------- COLORS --------------------------------- */

// Foreground colors
#define CLR_RESET             "\033[0m"
#define CLR_BLACK             "\033[30m"
#define CLR_RED               "\033[31m"
#define CLR_GREEN             "\033[32m"
#define CLR_YELLOW            "\033[33m"
#define CLR_BLUE              "\033[34m"
#define CLR_MAGENTA           "\033[35m"
#define CLR_CYAN              "\033[36m"
#define CLR_WHITE             "\033[37m"

// Bright foreground colors
#define CLR_BRIGHT_BLACK      "\033[90m"
#define CLR_BRIGHT_RED        "\033[91m"
#define CLR_BRIGHT_GREEN      "\033[92m"
#define CLR_BRIGHT_YELLOW     "\033[93m"
#define CLR_BRIGHT_BLUE       "\033[94m"
#define CLR_BRIGHT_MAGENTA    "\033[95m"
#define CLR_BRIGHT_CYAN       "\033[96m"
#define CLR_BRIGHT_WHITE      "\033[97m"

// Background colors
#define CLR_BG_BLACK          "\033[40m"
#define CLR_BG_RED            "\033[41m"
#define CLR_BG_GREEN          "\033[42m"
#define CLR_BG_YELLOW         "\033[43m"
#define CLR_BG_BLUE           "\033[44m"
#define CLR_BG_MAGENTA        "\033[45m"
#define CLR_BG_CYAN           "\033[46m"
#define CLR_BG_WHITE          "\033[47m"

// Bright background colors
#define CLR_BG_BRIGHT_BLACK   "\033[100m"
#define CLR_BG_BRIGHT_RED     "\033[101m"
#define CLR_BG_BRIGHT_GREEN   "\033[102m"
#define CLR_BG_BRIGHT_YELLOW  "\033[103m"
#define CLR_BG_BRIGHT_BLUE    "\033[104m"
#define CLR_BG_BRIGHT_MAGENTA "\033[105m"
#define CLR_BG_BRIGHT_CYAN    "\033[106m"
#define CLR_BG_BRIGHT_WHITE   "\033[107m"

/* --------------------------- SPECIFY LOG COLORS --------------------------- */
#define TRACE_COLOR           CLR_BG_BRIGHT_BLUE
#define DEBUG_COLOR           CLR_BRIGHT_BLUE
#define INFO_COLOR            ""
#define WARNING_COLOR         CLR_BRIGHT_YELLOW
#define ERROR_COLOR           CLR_BRIGHT_RED
#define CRITICAL_COLOR        CLR_BRIGHT_RED

#if CONFIG_LOG_LEVEL >= LOG_TRACE
#define LOGT(tag, format, ...)  console_printf(TRACE_COLOR "%s" CLR_RESET format "\n", tag, ##__VA_ARGS__)
#define LOGNT(tag, format, ...) console_printf(TRACE_COLOR "%s" CLR_RESET format, tag, ##__VA_ARGS__)
#else
#define LOGT(tag, format, ...)  (void)tag
#define LOGNT(tag, format, ...) (void)tag
#endif

#if CONFIG_LOG_LEVEL >= LOG_DEBUG
#define LOGD(tag, format, ...)  console_printf(DEBUG_COLOR "%s" CLR_RESET format "\n", tag, ##__VA_ARGS__)
#define LOGND(tag, format, ...) console_printf(DEBUG_COLOR "%s" CLR_RESET format, tag, ##__VA_ARGS__)
#else
#define LOGD(tag, format, ...)  (void)tag
#define LOGND(tag, format, ...) (void)tag
#endif

#if CONFIG_LOG_LEVEL >= LOG_INFO
#define LOGI(tag, format, ...)  console_printf(INFO_COLOR "%s" CLR_RESET format "\n", tag, ##__VA_ARGS__)
#define LOGNI(tag, format, ...) console_printf(INFO_COLOR "%s" CLR_RESET format, tag, ##__VA_ARGS__)
#else
#define LOGI(tag, format, ...)  (void)tag
#define LOGNI(tag, format, ...) (void)tag
#endif

#if CONFIG_LOG_LEVEL >= LOG_WARNING
#define LOGW(tag, format, ...)  console_printf(WARNING_COLOR "%s" CLR_RESET format "\n", tag, ##__VA_ARGS__)
#define LOGNW(tag, format, ...) console_printf(WARNING_COLOR "%s" CLR_RESET format, tag, ##__VA_ARGS__)
#else
#define LOGW(tag, format, ...)  (void)tag
#define LOGNW(tag, format, ...) (void)tag
#endif

#if CONFIG_LOG_LEVEL >= LOG_ERROR
#define LOGE(tag, format, ...)  console_printf(ERROR_COLOR "%s" CLR_RESET format "\n", tag, ##__VA_ARGS__)
#define LOGNE(tag, format, ...) console_printf(ERROR_COLOR "%s" CLR_RESET format, tag, ##__VA_ARGS__)
#define LOGC(tag, format, ...)  console_printf(CRITICAL_COLOR "%s" CLR_RESET format "\n", tag, ##__VA_ARGS__)
#define LOGNC(tag, format, ...) console_printf(CRITICAL_COLOR "%s" CLR_RESET format, tag, ##__VA_ARGS__)
#else
#define LOGE(tag, format, ...)  (void)tag
#define LOGNE(tag, format, ...) (void)tag
#define LOGC(tag, format, ...)  (void)tag
#define LOGNC(tag, format, ...) (void)tag
#endif

void debug_init(void);

#endif // H_DEBUG