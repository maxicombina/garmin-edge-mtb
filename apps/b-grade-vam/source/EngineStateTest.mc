import Toybox.Lang;
import Toybox.Test;
import Toybox.Activity;

//
// Unit tests for EngineState (SPEC 10): the full transition table (5.4) and the sampling gate.
//

// --- shouldPush: only while ON ---
(:test)
function testShouldPush(logger as Test.Logger) as Boolean {
    Test.assert(EngineState.shouldPush(Activity.TIMER_STATE_ON));
    Test.assert(!EngineState.shouldPush(Activity.TIMER_STATE_PAUSED));
    Test.assert(!EngineState.shouldPush(Activity.TIMER_STATE_STOPPED));
    Test.assert(!EngineState.shouldPush(Activity.TIMER_STATE_OFF));
    Test.assert(!EngineState.shouldPush(null));
    return true;
}

// --- Transition table ---
(:test)
function testTransitions(logger as Test.Logger) as Boolean {
    var ON = Activity.TIMER_STATE_ON;
    var PAUSED = Activity.TIMER_STATE_PAUSED;
    var STOPPED = Activity.TIMER_STATE_STOPPED;
    var OFF = Activity.TIMER_STATE_OFF;

    // ON -> ON : normal flow
    Test.assertEqualMessage(EngineState.onTimerTransition(ON, ON), EngineState.NONE, "ON->ON");
    // ON -> PAUSED / STOPPED : freeze (NONE; the gate does the freezing)
    Test.assertEqualMessage(EngineState.onTimerTransition(ON, PAUSED), EngineState.NONE, "ON->PAUSED");
    Test.assertEqualMessage(EngineState.onTimerTransition(ON, STOPPED), EngineState.NONE, "ON->STOPPED");
    // !ON -> ON : resume / start
    Test.assertEqualMessage(EngineState.onTimerTransition(PAUSED, ON), EngineState.RESET_WINDOWS, "PAUSED->ON");
    Test.assertEqualMessage(EngineState.onTimerTransition(STOPPED, ON), EngineState.RESET_WINDOWS, "STOPPED->ON");
    Test.assertEqualMessage(EngineState.onTimerTransition(null, ON), EngineState.RESET_WINDOWS, "null->ON (cold start)");
    // any -> OFF : reset
    Test.assertEqualMessage(EngineState.onTimerTransition(ON, OFF), EngineState.CLEAR, "ON->OFF");
    Test.assertEqualMessage(EngineState.onTimerTransition(PAUSED, OFF), EngineState.CLEAR, "PAUSED->OFF");
    // OFF -> PAUSED : nothing yet
    Test.assertEqualMessage(EngineState.onTimerTransition(OFF, PAUSED), EngineState.NONE, "OFF->PAUSED");
    return true;
}
