#ifndef H_TIMER
#define H_TIMER

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// Smallest time increment is one milliseconds from the millis() function.
#define TIMER_TICK_TO_MILLISECOND (1)
#define TIMER_TICK_TO_SECOND (1000)
#define TIMER_TICK_TO_MINUTE (TIMER_TICK_TO_SECOND * 60)

typedef struct soft_timer {
    bool active;
    uint32_t _start_time;
    uint32_t _duration;
} soft_timer_t;

// Set the timer to a specified time span.
void timer_set_relative_ms(soft_timer_t* timer, uint32_t time_span);
void timer_set_relative_s(soft_timer_t* timer, uint32_t time_span);
void timer_set_relative_m(soft_timer_t* timer, uint32_t time_span);
void timer_set_absolute(soft_timer_t* timer, uint32_t current_time, uint32_t duration);

// Check the status of the timer.
bool timer_is_expired(soft_timer_t* timer);
bool timer_is_active(soft_timer_t* timer);

#ifdef __cplusplus
}
#endif

#endif // H_TIMER
