import Toybox.Lang;
import Toybox.Test;

//
// Unit tests for RefSelect (SPEC 10). The key case: with variable speed but a CONSTANT grade,
// the distance window and the time window must pick DIFFERENT reference samples -- that is the
// proof grade is measured over distance and VAM over time.
//

// Build a buffer: slow start (2 m/s) then fast (10 m/s), constant 7% grade, 1 Hz samples.
// t in ms, d in m, h = 0.07 * d.  Samples (index: t, d):
//   0: 0ms,   0m     3: 3000, 6m      6: 6000, 30m
//   1: 1000,  2m     4: 4000, 16m     7: 7000, 40m
//   2: 2000,  4m     5: 5000, 26m     (speed 2,2,2,10,10,10,10 m/s)
// Plain (un-annotated) helper, NOT a test case (see the note in GradeVamEngineTest.mc).
function makeVarSpeedBuffer() as SampleBuffer {
    var b = new SampleBuffer(64);
    var d = [0.0, 2.0, 4.0, 6.0, 16.0, 26.0, 30.0, 40.0];
    for (var i = 0; i < d.size(); i++) {
        b.push(i * 1000, d[i], 0.07 * d[i]);
    }
    return b;
}

// --- Distance vs time pick DIFFERENT indices (grade=distance, VAM=time) ---
(:test)
function testRefDistinctIndices(logger as Test.Logger) as Boolean {
    var b = makeVarSpeedBuffer();               // newest = index 7 (t=7000, d=40)
    // byDistance(20 m): oldest with (40 - d) <= 20  -> d >= 20 -> index 5 (d=26)
    var gi = RefSelect.byDistance(b, 20.0, 3);
    Test.assertEqualMessage(gi, 5, "byDistance 20 m -> index 5");
    // byTime(10 s): all samples within 10 s -> oldest -> index 0
    var vi = RefSelect.byTime(b, 10000);
    Test.assertEqualMessage(vi, 0, "byTime 10 s -> index 0");
    Test.assert(gi != vi);
    return true;
}

// --- Inclusive border on time ---
(:test)
function testRefTimeInclusive(logger as Test.Logger) as Boolean {
    var b = makeVarSpeedBuffer();               // newest t=7000
    // window 3000 ms -> oldest with (7000 - t) <= 3000 -> t >= 4000 -> index 4
    Test.assertEqualMessage(RefSelect.byTime(b, 3000), 4, "3 s window -> index 4");
    return true;
}

// --- Window larger than the buffer -> index 0 (oldest available) ---
(:test)
function testRefWindowExceedsBuffer(logger as Test.Logger) as Boolean {
    var b = makeVarSpeedBuffer();
    Test.assertEqualMessage(RefSelect.byDistance(b, 999.0, 3), 0, "huge distance -> 0");
    Test.assertEqualMessage(RefSelect.byTime(b, 999000), 0, "huge time -> 0");
    return true;
}

// --- Span floor: distance window that reaches only recent samples is pushed back to
//     guarantee >= 3 samples in [ref .. newest] ---
(:test)
function testRefSpanFloor(logger as Test.Logger) as Boolean {
    var b = makeVarSpeedBuffer();               // n = 8, newest index 7
    // A tiny distance window (5 m): (40 - d) <= 5 -> d >= 35 -> index 7 (only the newest).
    // Span floor forces ref <= n - 3 = 5. So ref = 5, not 7.
    Test.assertEqualMessage(RefSelect.byDistance(b, 5.0, 3), 5, "span floor -> index 5");
    return true;
}

// --- Fewer than 2 samples -> -1 ---
(:test)
function testRefTooFew(logger as Test.Logger) as Boolean {
    var b = new SampleBuffer(4);
    Test.assertEqualMessage(RefSelect.byDistance(b, 20.0, 3), -1, "empty -> -1");
    Test.assertEqualMessage(RefSelect.byTime(b, 10000), -1, "empty -> -1");
    b.push(0, 0.0, 100.0);
    Test.assertEqualMessage(RefSelect.byDistance(b, 20.0, 3), -1, "1 sample -> -1");
    Test.assertEqualMessage(RefSelect.byTime(b, 10000), -1, "1 sample -> -1");
    return true;
}
