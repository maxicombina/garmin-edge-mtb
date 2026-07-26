import Toybox.Lang;
import Toybox.Activity;

//
// PURE orchestrator (SPEC 5): owns the sample buffer, the smoothing/outlier state and the timer
// state machine, and turns one (timerState, t, d, h, speed) update per second into a current
// grade (%) and VAM (m/h). It takes plain numbers -- never Dc or Activity.Info -- so the whole
// pipeline is unit-testable (GradeVamEngineTest.mc); GradeVamView.compute() is the thin,
// non-testable wrapper that null-checks Activity.Info and delegates here.
//
// Pipeline per update() (SPEC 5, in order):
//   1. EngineState.onTimerTransition -> NONE / RESET_WINDOWS / CLEAR
//   2. EngineState.shouldPush        -> sample only while running
//   3. median-of-3 over raw h        -> kill single-sample spikes
//   4. AltFilter.classify            -> ACCEPT / REJECT / RESEED (persistent-step recovery)
//   5. EMA over accepted h           -> reduce baro noise
//   6. push {t, d, h_smoothed}
//   7. RefSelect + GradeMath / VamMath -> current grade & VAM
//
// Display freeze contract (SPEC 5.4): while size() < 2 (cold start OR post-resume warm-up) the
// engine LEAVES the last grade/VAM untouched. At cold start they are null (-> "--"); after a
// resume they hold the pre-pause values, which the View greys until fresh values appear. Once
// size() >= 2, every update assigns the freshly computed value (which may itself be null for a
// hard reason: stop guard, out of range, too-short window).
//
class GradeVamEngine {

    private const EMA_ALPHA = 0.4;
    private const MIN_SPAN_SAMPLES = 3;    // distance-window span floor (SPEC 5.2)
    private const VAM_STOP_MIN_D_M = 2.0;  // horizontal span below this in the VAM window -> 0
    private const STOP_SPEED_MPS = 0.5;    // speed below this, SUSTAINED, -> VAM 0 (SPEC 5.3)
    private const STOP_PERSIST_TICKS = 3;  // "sustained" = this many consecutive slow ticks (~3 s)
    private const VAM_MIN_DT_FLOOR_MS = 2000;

    // Non-null inline default (matches Option A's "always initialise members" discipline so it
    // is safe at any type-check level); initialize() replaces it with the requested capacity.
    private var mBuffer as SampleBuffer = new SampleBuffer(64);

    // Configurable windows (SPEC 7).
    private var mGradeWindowM as Float = 20.0;
    private var mVamWindowMs as Number = 10000;
    private var mMinDtMs as Number = 5000;     // max(2000, W_vam/2), recomputed in setWindows()

    // Smoothing / outlier running state (owned here; AltFilter functions are stateless).
    private var mLastGoodH as Float or Null = null;
    private var mRejectCount as Number = 0;
    private var mEmaPrev as Float or Null = null;
    private var mRaw1 as Float or Null = null;   // previous raw h (t-1)
    private var mRaw2 as Float or Null = null;   // raw h before that  (t-2)

    private var mPrevState as Activity.TimerState or Null = null;

    // Consecutive running ticks with speed < STOP_SPEED_MPS (the VAM stop guard's persistence
    // state -- see the "sostenida" decision, SPEC 5.3 / 2026-07-21).
    private var mSlowTicks as Number = 0;

    // Latest outputs (see freeze contract above).
    private var mGrade as Float or Null = null;
    private var mVam as Float or Null = null;

    function initialize(capacity as Number, gradeWindowM as Number, vamWindowSec as Number) {
        mBuffer = new SampleBuffer(capacity);
        setWindows(gradeWindowM, vamWindowSec);
    }

    // Reload the two window settings (called from onSettingsChanged). Recomputes the VAM
    // minimum Δt = max(2000 ms, W_vam / 2).
    function setWindows(gradeWindowM as Number, vamWindowSec as Number) as Void {
        mGradeWindowM = gradeWindowM.toFloat();
        mVamWindowMs = vamWindowSec * 1000;
        var half = mVamWindowMs / 2;
        mMinDtMs = (half > VAM_MIN_DT_FLOOR_MS) ? half : VAM_MIN_DT_FLOOR_MS;
    }

    function gradePct() as Float or Null { return mGrade; }
    function vamMh() as Float or Null { return mVam; }
    function sampleCount() as Number { return mBuffer.size(); }

    // One tick. tMs/dM/hM may be null (Activity.Info not ready yet) -> state is still advanced
    // but nothing is pushed. speedMps may be null (used only by the VAM stop guard).
    function update(timerState as Activity.TimerState or Null,
                    tMs as Number or Null, dM as Float or Null, hM as Float or Null,
                    speedMps as Float or Null) as Void {

        // 1. State machine (source of truth: the observed timerState).
        var action = EngineState.onTimerTransition(mPrevState, timerState);
        mPrevState = timerState;
        if (action == EngineState.CLEAR) {
            resetAll();                 // -> display returns to --
        } else if (action == EngineState.RESET_WINDOWS) {
            resetWindows();             // keep last displayed values (View greys them)
        }

        // 2. Gate: sample only while running.
        if (!EngineState.shouldPush(timerState)) {
            return;                     // frozen; keep last grade/VAM
        }

        // 2b. Stop-speed persistence (SPEC 5.3 "sostenida", decided 2026-07-21): the VAM stop
        //     guard fires only after STOP_PERSIST_TICKS consecutive slow ticks -- a single
        //     one-second dip (trackstand over an obstacle, a speed glitch) must not flash the
        //     VAM to 0 and back. A null speed cannot claim "slow" and resets the count.
        if (speedMps != null && speedMps < STOP_SPEED_MPS) {
            if (mSlowTicks < STOP_PERSIST_TICKS) {
                mSlowTicks++;           // capped: no unbounded growth on a long stop
            }
        } else {
            mSlowTicks = 0;
        }

        // 3. Need a full, valid sample to push.
        if (tMs == null || dM == null || hM == null) {
            return;
        }

        // 4. Median-of-3 over the raw altitude stream (needs 3 raw samples; before that, raw).
        var hMed;
        if (mRaw1 == null || mRaw2 == null) {
            hMed = hM;
        } else {
            hMed = AltFilter.median3(mRaw2, mRaw1, hM);
        }
        mRaw2 = mRaw1;
        mRaw1 = hM;

        // 5. Outlier gate against the last GOOD altitude.
        var cls = AltFilter.classify(mLastGoodH, hMed, mRejectCount);
        var hAccepted;
        if (cls == AltFilter.REJECT) {
            mRejectCount++;
            return;                     // spike: do not push, baseline unchanged
        } else if (cls == AltFilter.RESEED) {
            // Persistent step: new baseline from the raw sample, flush windows.
            mBuffer.clear();
            mEmaPrev = null;
            mRejectCount = 0;
            mLastGoodH = hM;
            hAccepted = hM;
        } else { // ACCEPT
            mRejectCount = 0;
            mLastGoodH = hMed;
            hAccepted = hMed;
        }

        // 6. EMA over the accepted altitude, then push the smoothed sample.
        mEmaPrev = AltFilter.ema(mEmaPrev, hAccepted, EMA_ALPHA);
        mBuffer.push(tMs, dM, mEmaPrev);

        // 7. Recompute outputs.
        recompute();
    }

    // Grade over the distance window, VAM over the time window. Only runs with >= 2 samples;
    // below that, the freeze contract leaves the last values untouched (see class header).
    private function recompute() as Void {
        var n = mBuffer.size();
        if (n < 2) {
            return;
        }
        var newest = n - 1;
        var hNow = mBuffer.hAt(newest);
        var dNow = mBuffer.dAt(newest);
        var tNow = mBuffer.tAt(newest);

        // --- grade (%) : distance window, hybrid with the span floor ---
        var gi = RefSelect.byDistance(mBuffer, mGradeWindowM, MIN_SPAN_SAMPLES);
        if (gi >= 0 && gi < newest) {
            mGrade = GradeMath.gradePct(hNow - mBuffer.hAt(gi), dNow - mBuffer.dAt(gi));
        } else {
            mGrade = null;
        }

        // --- VAM (m/h) : time window, with the stop guard ---
        var vi = RefSelect.byTime(mBuffer, mVamWindowMs);
        if (vi >= 0 && vi < newest) {
            var dhT = hNow - mBuffer.hAt(vi);
            var dtT = tNow - mBuffer.tAt(vi);                 // Number (ms)
            var ddT = dNow - mBuffer.dAt(vi);
            var stopped = (ddT < VAM_STOP_MIN_D_M)
                          || (mSlowTicks >= STOP_PERSIST_TICKS);
            if (stopped && dtT > 0) {
                mVam = 0.0;                                   // "stopped, not climbing" is valid
            } else {
                mVam = VamMath.vamMh(dhT, dtT, mMinDtMs);
            }
        } else {
            mVam = null;
        }
    }

    // Resume/start: flush buffer + all smoothing state so no pre-pause sample survives. Leaves
    // mGrade/mVam in place (View greys them through the warm-up).
    private function resetWindows() as Void {
        mBuffer.clear();
        mLastGoodH = null;
        mRejectCount = 0;
        mEmaPrev = null;
        mRaw1 = null;
        mRaw2 = null;
        mSlowTicks = 0;   // stale pre-pause speed state must not zero the first fresh VAM
    }

    // Reset/OFF: everything above, plus the outputs return to null (display -> --).
    private function resetAll() as Void {
        resetWindows();
        mGrade = null;
        mVam = null;
    }
}
