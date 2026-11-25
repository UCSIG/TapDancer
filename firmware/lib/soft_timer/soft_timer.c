#include "soft_timer.h"
#include <Arduino.h>

void timer_set_absolute(soft_timer_t* timer, uint32_t current_time, uint32_t duration) {
    timer->_start_time = current_time;
    timer->_duration = duration;
    timer->active = true;
}

void timer_set_relative_ms(soft_timer_t* timer, uint32_t time_span) {
    uint32_t duration = time_span * TIMER_TICK_TO_MILLISECOND;
    timer_set_absolute(timer, millis(), duration);
}

void timer_set_relative_s(soft_timer_t* timer, uint32_t time_span) {
    uint32_t duration = time_span * TIMER_TICK_TO_SECOND;
    timer_set_absolute(timer, millis(), duration);
}

void timer_set_relative_m(soft_timer_t* timer, uint32_t time_span) {
    uint32_t duration = time_span * TIMER_TICK_TO_MINUTE;
    timer_set_absolute(timer, millis(), duration);
}

bool timer_is_expired(soft_timer_t* timer) {
    bool expired = false;

    if ((millis() - timer->_start_time) >= timer->_duration) {
        expired = true;
        timer->active = false;
    } else {
        expired = false;
    }

    return expired;
}

bool timer_is_active(soft_timer_t* timer) {
    return timer->active;
}