import Toybox.Lang;
import Toybox.Activity;

//
// PURE timer-state logic (SPEC 5.4). The source of truth for pause/resume/reset is the
// TimerState OBSERVED in compute() each second -- NOT the onTimer* hooks, whose behaviour under
// auto-pause is undocumented. This module maps a (prev -> next) state transition to the action
// the engine must take, and gates sampling to the running state. Toybox.Activity is referenced
// only for its TIMER_STATE_* integer constants; there is no device state here, so it is fully
// unit-testable (EngineStateTest.mc).
//
//   prev -> next                    action
//   ON   -> ON                      NONE           (normal flow)
//   ON   -> PAUSED / STOPPED        NONE           (gate freezes sampling; display greys)
//   !ON  -> ON  (start / resume)    RESET_WINDOWS  (flush the buffer -- see below)
//   any  -> OFF (reset)             CLEAR          (flush everything, display -> --)
//
// RESET_WINDOWS flushes the buffer on resume because keeping pre-pause samples fabricates a
// spike: t/d froze during the pause while h kept drifting, so the first post-resume window
// would see Δd~0 against a real Δh. The cost is a ~W-second warm-up showing the frozen values.
//
module EngineState {

    enum {
        NONE,           // nothing to do
        RESET_WINDOWS,  // flush buffer + smoothing state; keep last displayed values (grey)
        CLEAR           // flush everything; display returns to --
    }

    // shouldPush is true ONLY while the timer is actively running.
    function shouldPush(state as Activity.TimerState or Null) as Boolean {
        return state == Activity.TIMER_STATE_ON;
    }

    // prev may be null on the very first call (treated as "not ON").
    function onTimerTransition(prev as Activity.TimerState or Null,
                               next as Activity.TimerState or Null) as Number {
        if (next == Activity.TIMER_STATE_OFF) {
            return CLEAR;
        }
        var wasOn = (prev == Activity.TIMER_STATE_ON);
        var isOn  = (next == Activity.TIMER_STATE_ON);
        if (!wasOn && isOn) {
            return RESET_WINDOWS;
        }
        return NONE;
    }
}
