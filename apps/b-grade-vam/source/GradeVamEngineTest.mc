import Toybox.Lang;
import Toybox.Test;
import Toybox.Activity;

//
// Integration tests for GradeVamEngine (SPEC 10). These exercise the WHOLE pipeline (state
// machine + median + outlier gate + EMA + buffer + windows), so unlike the pure-module tests
// they see the effect of smoothing. Where EMA attenuates an exact value we assert the INTENT
// (sign / non-null / independence), and keep the exact arithmetic in the pure *MathTest files.
//
// Engine config used throughout: capacity 64, grade window 20 m, VAM window 10 s
// (-> minDt = max(2000, 5000) = 5000 ms).
//
// makeEngine() is a plain (un-annotated) helper, NOT a test case: the test runner invokes every
// (:test) function as func(logger)->Boolean, so helpers must stay un-annotated. In a release
// build it is unreferenced (its only callers are (:test)) and the optimizer drops it.
//

function makeEngine() as GradeVamEngine {
    return new GradeVamEngine(64, 20, 10);
}

// --- Cold start: 0 and 1 samples -> both metrics null ---
(:test)
function testEngineColdStart(logger as Test.Logger) as Boolean {
    var e = makeEngine();
    Test.assertMessage(e.gradePct() == null, "grade null at 0 samples");
    Test.assertMessage(e.vamMh() == null, "vam null at 0 samples");
    e.update(Activity.TIMER_STATE_ON, 0, 0.0, 100.0, 2.0);   // 1 sample
    Test.assertEqualMessage(e.sampleCount(), 1, "1 sample buffered");
    Test.assertMessage(e.gradePct() == null, "grade still null at 1 sample");
    Test.assertMessage(e.vamMh() == null, "vam still null at 1 sample");
    return true;
}

// --- Independent guards: 2 samples 2 m apart -> grade null (Δd<5), VAM real (Δt fine).
//     Speed is passed high enough to isolate the VAM stop guard from the tiny Δd. EMA
//     attenuates the first altitude step, so we assert VAM is a real positive reading, not a
//     specific value (the exact 360 lives in VamMathTest, EMA-free). ---
(:test)
function testEngineIndependentGuards(logger as Test.Logger) as Boolean {
    var e = makeEngine();
    e.update(Activity.TIMER_STATE_ON, 0,     0.0, 100.0, 1.0);
    e.update(Activity.TIMER_STATE_ON, 10000, 2.0, 101.0, 1.0);   // 2 m horizontal, 10 s, +1 m
    Test.assertEqualMessage(e.sampleCount(), 2, "2 samples");
    Test.assertMessage(e.gradePct() == null, "grade null: Δd 2 m < 5 m stop guard");
    var v = e.vamMh();
    Test.assertMessage(v != null, "VAM computes (its guard did not fire)");
    Test.assertMessage(v > 0, "VAM positive (climbing)");
    return true;
}

// --- Null input -> no push (state still advances) ---
(:test)
function testEngineNullInput(logger as Test.Logger) as Boolean {
    var e = makeEngine();
    e.update(Activity.TIMER_STATE_ON, 0, 0.0, null, 2.0);        // altitude null
    Test.assertEqualMessage(e.sampleCount(), 0, "null h -> no push");
    e.update(Activity.TIMER_STATE_ON, 1000, null, 100.0, 2.0);   // distance null
    Test.assertEqualMessage(e.sampleCount(), 0, "null d -> no push");
    e.update(Activity.TIMER_STATE_ON, null, 0.0, 100.0, 2.0);    // time null
    Test.assertEqualMessage(e.sampleCount(), 0, "null t -> no push");
    return true;
}

// --- PAUSED never pushes ---
(:test)
function testEnginePausedNoPush(logger as Test.Logger) as Boolean {
    var e = makeEngine();
    e.update(Activity.TIMER_STATE_PAUSED, 0,    0.0, 100.0, 0.0);
    e.update(Activity.TIMER_STATE_PAUSED, 1000, 0.0, 100.0, 0.0);
    Test.assertEqualMessage(e.sampleCount(), 0, "PAUSED -> nothing buffered");
    return true;
}

// --- The spike killer: after a long pause with altitude drift, resuming flushes the buffer,
//     so the first post-resume sample is a clean baseline (no pre-pause sample -> no spike). ---
(:test)
function testEngineResumeFlush(logger as Test.Logger) as Boolean {
    var e = makeEngine();
    // Ride a bit (climbing) -> buffer fills.
    for (var i = 0; i < 5; i++) {
        e.update(Activity.TIMER_STATE_ON, i * 1000, i * 2.0, 100.0 + i * 0.14, 2.0);
    }
    Test.assertEqualMessage(e.sampleCount(), 5, "5 samples before pause");

    // Pause: no push, buffer untouched.
    e.update(Activity.TIMER_STATE_PAUSED, 5000, 8.0, 100.56, 0.0);
    Test.assertEqualMessage(e.sampleCount(), 5, "pause pushes nothing");

    // Resume with a drifted altitude (+5 m of baro drift during the pause) and the SAME
    // distance. Without the flush this would look like +5 m over ~0 m -> a huge fake grade.
    e.update(Activity.TIMER_STATE_ON, 6000, 8.0, 105.56, 2.0);
    Test.assertEqualMessage(e.sampleCount(), 1, "resume FLUSHED the buffer -> clean baseline");
    // Only 1 sample -> nothing computed yet -> no spike could have been produced.
    return true;
}

// --- Reset (OFF) clears everything and returns the display to -- ---
(:test)
function testEngineResetClears(logger as Test.Logger) as Boolean {
    var e = makeEngine();
    for (var i = 0; i < 20; i++) {
        e.update(Activity.TIMER_STATE_ON, i * 1000, i * 2.0, 100.0 + i * 0.14, 2.0);
    }
    Test.assertMessage(e.sampleCount() > 0, "buffered while running");
    e.update(Activity.TIMER_STATE_OFF, 20000, 40.0, 102.8, 0.0);
    Test.assertEqualMessage(e.sampleCount(), 0, "OFF clears the buffer");
    Test.assertMessage(e.gradePct() == null, "grade -> --");
    Test.assertMessage(e.vamMh() == null, "vam -> --");
    return true;
}

// --- VAM stop guard persistence (SPEC 5.3 "sostenida", decided 2026-07-21): a 1-2 tick speed
//     dip (trackstand, glitch) must NOT flash the VAM to 0; the 3rd consecutive slow tick zeroes
//     it; a fast tick resets the count. Distance keeps advancing throughout so the ddT < 2 m
//     branch never fires and the speed branch is exercised in isolation. ---
(:test)
function testEngineSpeedStopPersistence(logger as Test.Logger) as Boolean {
    var e = makeEngine();
    // Warm-up: 12 s climbing at 2 m/s (+0.14 m/s), well past the 5000 ms minDt.
    var i = 0;
    for (i = 0; i <= 12; i++) {
        e.update(Activity.TIMER_STATE_ON, i * 1000, i * 2.0, 100.0 + i * 0.14, 2.0);
    }
    var v = e.vamMh();
    Test.assertMessage(v != null && v > 0, "VAM positive after warm-up");

    // Slow ticks 1 and 2 (speed 0.2 < 0.5, distance still advancing): VAM must NOT drop to 0.
    for (var k = 0; k < 2; k++) {
        e.update(Activity.TIMER_STATE_ON, i * 1000, i * 2.0, 100.0 + i * 0.14, 0.2);
        i++;
        v = e.vamMh();
        Test.assertMessage(v != null && v > 0, "slow tick " + (k + 1) + " of 2: VAM still positive");
    }

    // 3rd consecutive slow tick: now it is "sustained" -> VAM 0.
    e.update(Activity.TIMER_STATE_ON, i * 1000, i * 2.0, 100.0 + i * 0.14, 0.2);
    i++;
    v = e.vamMh();
    Test.assertMessage(v != null, "sustained stop: VAM is 0, not null");
    TestUtil.assertNear(v, 0.0, 0.001, "sustained stop -> VAM 0");

    // Fast tick: counter resets, VAM comes back.
    e.update(Activity.TIMER_STATE_ON, i * 1000, i * 2.0, 100.0 + i * 0.14, 2.0);
    v = e.vamMh();
    Test.assertMessage(v != null && v > 0, "speed back -> VAM positive again");
    return true;
}

// --- Steady 7% climb -> grade converges to 7 (+/- 1). Constant slope + linear EMA => the
//     smoothed altitude difference over a window equals the true difference once converged. ---
(:test)
function testEngineSteadyGrade(logger as Test.Logger) as Boolean {
    var e = makeEngine();
    // 2 m/s, 7% -> +0.14 m altitude per second. Feed 40 s so the 20 m window is well inside
    // the buffer and the EMA transient is long gone.
    for (var i = 0; i <= 40; i++) {
        e.update(Activity.TIMER_STATE_ON, i * 1000, i * 2.0, 100.0 + i * 0.14, 2.0);
    }
    var g = e.gradePct();
    Test.assertMessage(g != null, "grade computed on steady climb");
    TestUtil.assertNear(g, 7.0, 1.0, "steady 7% grade");
    return true;
}
