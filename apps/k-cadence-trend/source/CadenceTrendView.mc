import Toybox.WatchUi;
import Toybox.Graphics;
import Toybox.Activity;
import Toybox.Lang;

//
// Cadence trend-arrow data field (Option K). A THIN wrapper by design: it reads Activity.Info,
// null-checks it, delegates the formatting to CadenceFormat (pure) and the whole drawing to
// TrendCore.TrendRenderer (the barrel). There is no layout code here at all -- that is the point of
// the barrel, and why this file is a fraction of the size of Option J's view before the split.
//
// Cadence is Tier 1: Garmin gives BOTH the current and the average value (currentCadence /
// averageCadence, whole rpm), so there is no buffer, no smoothing and no filter. compute() is
// almost trivial.
//
class CadenceTrendView extends WatchUi.DataField {

    // Dead band, in rpm. A gap this size or smaller reads as "you are at your average" and shows no
    // arrow. 3 rather than 1: a 1-second cadence reading jitters by a couple of rpm on its own, so a
    // tighter band would flip the arrow on noise rather than on your pedalling. It is also a
    // SEMANTIC choice, like Option J's 0.1 km/h -- for the author, riding within 3 rpm of your
    // average is riding at your average. One constant if it wants widening.
    private const DEAD_BAND_RPM = 3;

    // Width-stable template: 3 digits. Human cadence never reaches 4 (world-record track sprints sit
    // near 200 rpm), so "888" is a real upper bound on every value displayString can produce.
    private const VALUE_TPL = "888";

    private var mRenderer as TrendCore.TrendRenderer;

    // --- Live display state, rebuilt every second in compute() ---
    private var mCurStr as String = TrendCore.NO_DATA;
    private var mRefStr as String = TrendCore.NO_DATA;
    private var mArrowState as Number = 0;   // TrendCore.TrendArrow.UP / NONE / DOWN
    private var mRunning as Boolean = false;

    // --- Simulator test hook. TEST_MODE stays a PLAIN const false so the guard in compute() is
    //     dead-code-eliminated in release (-r drops the block AND the call); the synthetic generator
    //     and its state are (:debug)-only, and a (:release) stub keeps the call site resolving.
    //
    //     WARNING: leaving this true in a RELEASE build compiles clean, with no warning, and the
    //     field shows "--" forever -- the (:release) stub returns nulls, so Activity.Info is never
    //     read. It cost Option J a burnt version number. Verify it is false before exporting.
    private const TEST_MODE = false;
    (:debug) private var mSynTick as Number = 0;
    (:debug) private var mSynSum as Number = 0;
    (:debug) private var mSynCount as Number = 0;

    function initialize() {
        DataField.initialize();

        mRenderer = new TrendCore.TrendRenderer();
        // Metric name, long then short (the renderer picks whichever fits the cell, like the native
        // field), plus the prefix for the secondary line.
        mRenderer.setLabels(
            (WatchUi.loadResource(Rez.Strings.CadenceLabel) as String).toUpper(),
            (WatchUi.loadResource(Rez.Strings.CadenceLabelShort) as String).toUpper(),
            (WatchUi.loadResource(Rez.Strings.AvgLabel) as String).toUpper());
        mRenderer.setTemplates(VALUE_TPL, VALUE_TPL + TrendCore.INLINE_SEP + VALUE_TPL);
        // Cadence has no unit variants, so unlike speed this can be set once and never revisited.
        mRenderer.setUnit(CadenceFormat.unitTop(), CadenceFormat.unitBottom());
    }

    // Runs ~1x/second. Reads inputs, formats the display strings. No drawing.
    function compute(info as Activity.Info) as Void {
        var state = null;
        var curRpm = null;
        var avgRpm = null;

        if (TEST_MODE) {
            // Body is (:debug)-only; the const-false guard drops this whole block in release.
            // Everything comes back through the return value so compute() never references a
            // (:debug) member directly (that would fail to resolve in a release build).
            var syn = nextSynthetic();
            state = syn[0];
            curRpm = syn[1];
            avgRpm = syn[2];
        } else {
            state = (info has :timerState) ? info.timerState : null;
            curRpm = (info has :currentCadence) ? info.currentCadence : null;
            avgRpm = (info has :averageCadence) ? info.averageCadence : null;
        }

        mRunning = (state == Activity.TIMER_STATE_ON);

        mCurStr = CadenceFormat.displayString(curRpm);
        mRefStr = CadenceFormat.displayString(avgRpm);
        // trendValue, not the raw rpm: it returns null while coasting, so the classifier's null path
        // gives NONE and a 0 shows without a down arrow (CadenceFormat's header explains why).
        mArrowState = TrendCore.TrendArrow.classify(CadenceFormat.trendValue(curRpm),
                                                    CadenceFormat.trendValue(avgRpm),
                                                    DEAD_BAND_RPM);
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        mRenderer.setValues(mCurStr, mRefStr, mArrowState, mRunning);
        // getBackgroundColor() is a DataField method, so the renderer cannot call it itself.
        mRenderer.draw(dc, getBackgroundColor());
    }

    // --- Simulator-only synthetic generator. One call = one second. Walks a cadence profile and
    //     accumulates its own running average so it converges like Garmin's. Forces TIMER_STATE_ON.
    //     Returns [state, curRpm, avgRpm]. (:debug) only; see the TEST_MODE note above. ---
    (:debug)
    private function nextSynthetic() as Array {
        // Profile built to exercise the ARROW and the coasting rule, not just the number: values
        // above and below the average, the +/-3 rpm edges where DEAD_BAND_RPM decides, and two
        // segments of 0 (coasting on a descent) which must show "0" with NO arrow.
        var rpms = [95, 84, 0, 70, 87, 81, 0, 60];
        var segSec = 3;                                // each segment lasts 3 s
        var idx = (mSynTick / segSec) % rpms.size();
        var cur = rpms[idx];
        // Garmin's average cadence excludes the zeros on most devices, and so does this: averaging
        // them in would drag the reference down every descent and the arrow would read high for the
        // rest of the climb.
        if (cur > 0) {
            mSynSum += cur;
            mSynCount += 1;
        }
        var avg = (mSynCount > 0) ? (mSynSum / mSynCount) : 0;
        mSynTick++;
        return [Activity.TIMER_STATE_ON, cur, avg];
    }

    // Release stub: never called (TEST_MODE is const false -> the call site is eliminated).
    (:release)
    private function nextSynthetic() as Array {
        return [null, null, null];
    }
}
