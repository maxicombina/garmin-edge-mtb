import Toybox.Application;
import Toybox.WatchUi;
import Toybox.Graphics;
import Toybox.Activity;
import Toybox.Lang;
import Toybox.System;

//
// Speed trend-arrow data field (Option J). A THIN wrapper by design (SPEC 3): compute() null-checks
// Activity.Info, hands the logic to the PURE modules (SpeedFormat here, TrendCore.TrendArrow in the
// barrel) and the whole drawing to TrendCore.TrendRenderer. There is no layout code in this file.
//
// MIGRATED TO THE BARREL 2026-07-27 (SPEC 3.4). The ~840-line render engine that used to live here now
// lives in barrels/trend-core and is shared with Options K and L. Before deleting this copy, the 13
// engine functions were compared body-by-body against the barrel's, normalised (comments stripped, the
// barrel's renames applied): all 13 were character-for-character identical, so the migration cannot
// change a pixel. That check is worth repeating if the two ever have to be reconciled again.
//
// MVP metric = speed (Tier 1): Garmin already gives BOTH current and average (currentSpeed /
// averageSpeed, m/s), so there is no buffer / smoothing / filter -- compute() is almost trivial
// (SPEC 5.3). The field shows the current speed (big, WITH a trend arrow) and, on tall enough cells,
// the reference on a secondary line below (SPEC 6.1).
//
// Units follow the device pace-units setting (paceUnits, NOT distanceUnits/elevationUnits -- SPEC 2):
// UNIT_STATUTE -> mph, else km/h. Re-read every compute() (cheap): a device units change does NOT fire
// onSettingsChanged, and the renderer's setUnit only invalidates when the strings really change.
//
// The arrow is DATA (it changes every tick with current-vs-reference), so unlike Option B's static
// grade ramp it sits next to the VALUE, not the label (SPEC intro / 6.1). The value has 1 decimal drawn
// as ONE string in ONE font -- the "." glyph is present in FONT_SYSTEM_NUMBER_* (SPEC 2).
//
class TrendArrowView extends WatchUi.DataField {

    // Width-stable template: 2 integer digits + "." + 1 decimal. Two digits are enough because
    // SpeedFormat.displayString drops the decimal from 100 up ("104"), and w("888") < w("88.8") in every
    // number font -- so this is still an upper bound on every value the field can show (SPEC 6.10).
    private const VALUE_TPL = "88.8";

    // Semantic dead-band for the trend arrow, in TENTHS of the display unit (SPEC 5.1). 1 == 0.1 km/h
    // (or mph): a current-vs-reference gap of <= 0.1 reads as "at the reference" (no arrow); only a gap
    // > 0.1 earns an up/down arrow. NOT anti-flicker -- it defines what "above/below" means. The same
    // band applies in target mode (author's decision, so no second constant exists -- SPEC 9.1).
    private const DEAD_BAND_TENTHS = 1;

    private var mRenderer as TrendCore.TrendRenderer;

    // --- Labels. Both prefixes are loaded once; mRefPrefix picks the active one (see reloadSettings). ---
    private var mAvgPrefix as String = "AVG";
    private var mTargetPrefix as String = "GOAL";

    // --- Settings state (SPEC 9). Re-read in onSettingsChanged, never per tick. ---
    private var mUseTarget as Boolean = false;           // referenceMode == 1
    private var mTargetTenths as Number or Null = null;  // pre-rounded target; null = not usable

    // --- Live display state, rebuilt every second in compute() ---
    private var mCurStr as String = TrendCore.NO_DATA;
    private var mRefStr as String = TrendCore.NO_DATA;
    private var mArrowState as Number = 0;   // TrendCore.TrendArrow.UP / NONE / DOWN
    private var mRunning as Boolean = false;
    private var mIsStatute as Boolean = false;

    // --- Simulator test hook. TEST_MODE stays a PLAIN const false so the guard in compute() is
    //     dead-code-eliminated in release (-r drops the block AND the call); the synthetic generator and
    //     its state are (:debug)-only, and a (:release) stub keeps the call site resolving.
    //
    //     WARNING: leaving this true in a RELEASE build compiles clean, with no warning, and the field
    //     shows "--" forever -- the (:release) stub returns nulls, so Activity.Info is never read. It
    //     cost this app a burnt version number (v0.2.0). Verify it is false before exporting an .iq.
    private const TEST_MODE = false;
    (:debug) private var mSynTick as Number = 0;
    (:debug) private var mSynDist as Float = 0.0;
    (:debug) private var mSynTime as Number = 0;

    // --- Layout measurement hook (SPEC 11.1). The engine reports its own decisions now: see
    //     TrendCore.TrendRenderer.debugSummary. Same const-false + (:debug)/(:release) scheme.
    private const DEBUG_MEASURE = false;
    (:debug) private var mDbgW as Number = -1;
    (:debug) private var mDbgH as Number = -1;

    function initialize() {
        DataField.initialize();

        mRenderer = new TrendCore.TrendRenderer();

        mAvgPrefix = (WatchUi.loadResource(Rez.Strings.AvgLabel) as String).toUpper();
        mTargetPrefix = (WatchUi.loadResource(Rez.Strings.TargetLabel) as String).toUpper();
        mRenderer.setTemplates(VALUE_TPL, VALUE_TPL + TrendCore.INLINE_SEP + VALUE_TPL);

        reloadSettings();   // sets the labels too, since the prefix depends on the settings
    }

    // Re-read the 2 app settings and derive what the arrow compares against. Called from initialize()
    // and from TrendArrowApp.onSettingsChanged() -- NEVER per tick (SPEC 9.5).
    function reloadSettings() as Void {
        mUseTarget = (readNumber("referenceMode", 0) == 1);
        mTargetTenths = SpeedFormat.targetTenths(readFloat("targetSpeed", 0.0));
        // Active prefix: GOAL/META only when the target is actually usable. Target mode with an unset,
        // zero or negative number behaves exactly like average mode, silently, so a half-configured
        // setting can never leave the field useless (SPEC 9.1 / 9.6).
        var refPrefix = (mUseTarget && mTargetTenths != null) ? mTargetPrefix : mAvgPrefix;
        // setLabels invalidates the layout cache for us: the prefix width changed, and in a wide cell it
        // is part of the label text too ("SPEED / AVG").
        mRenderer.setLabels(
            (WatchUi.loadResource(Rez.Strings.SpeedLabel) as String).toUpper(),
            (WatchUi.loadResource(Rez.Strings.SpeedLabelShort) as String).toUpper(),
            refPrefix);
    }

    private function readNumber(key as String, dflt as Number) as Number {
        var v = Application.Properties.getValue(key);
        if (v instanceof Lang.Number) { return v; }
        if (v instanceof Lang.Float) { return v.toNumber(); }
        return dflt;
    }

    private function readFloat(key as String, dflt as Float) as Float {
        var v = Application.Properties.getValue(key);
        if (v instanceof Lang.Float) { return v; }
        if (v instanceof Lang.Number) { return v.toFloat(); }
        return dflt;
    }

    // Runs ~1x/second. Reads inputs, formats the display strings. No drawing (SPEC 5.3).
    function compute(info as Activity.Info) as Void {
        // Device pace units can change without firing onSettingsChanged -> re-read each tick.
        mIsStatute = (System.getDeviceSettings().paceUnits == System.UNIT_STATUTE);
        mRenderer.setUnit(SpeedFormat.unitTop(mIsStatute), SpeedFormat.unitBottom(mIsStatute));

        var state = null;
        var curMps = null;
        var avgMps = null;

        if (TEST_MODE) {
            // Body is (:debug)-only; the const-false guard drops this whole block in release. Everything
            // comes back through the return value so compute() never references a (:debug) member
            // directly (that would fail to resolve in a release build).
            var syn = nextSynthetic();
            state = syn[0];
            curMps = syn[1];
            avgMps = syn[2];
        } else {
            state = (info has :timerState) ? info.timerState : null;
            curMps = (info has :currentSpeed) ? info.currentSpeed : null;
            avgMps = (info has :averageSpeed) ? info.averageSpeed : null;
        }

        mRunning = (state == Activity.TIMER_STATE_ON);

        // shownTenths is the ONLY rounding: the string and the arrow both start from it (SPEC 5.2). The
        // arrow compares those same tenths, but through the semantic dead band -- so a gap of <= 0.1
        // shows the two numbers slightly apart yet NO arrow, on purpose (SPEC 5.1).
        var curTenths = SpeedFormat.shownTenths(curMps, mIsStatute);
        var avgTenths = SpeedFormat.shownTenths(avgMps, mIsStatute);
        mCurStr = SpeedFormat.displayString(curTenths);
        // The reference the arrow AND the secondary line compare against: the fixed target when it is
        // configured and valid, else the ride average (silent fallback, SPEC 9.1).
        var refTenths = (mUseTarget && mTargetTenths != null) ? mTargetTenths : avgTenths;
        mRefStr = SpeedFormat.displayString(refTenths);
        mArrowState = TrendCore.TrendArrow.classify(curTenths, refTenths, DEAD_BAND_TENTHS);
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        mRenderer.setValues(mCurStr, mRefStr, mArrowState, mRunning);
        // getBackgroundColor() is a DataField method, so the renderer cannot call it itself.
        mRenderer.draw(dc, getBackgroundColor());

        if (DEBUG_MEASURE) {
            // (:debug)-only body; the const-false guard drops it (and the call) in release.
            debugMeasure(dc, dc.getWidth(), dc.getHeight());
        }
    }

    // --- Simulator-only synthetic generator (SPEC 11). One call = one second. Walks a speed profile and
    //     accumulates its own distance/time so the running average = dist/time converges like Garmin's.
    //     Forces TIMER_STATE_ON. Returns [state, curMps, avgMps]. (:debug) only. ---
    (:debug)
    private function nextSynthetic() as Array {
        // Profile built to exercise the ARROW, not just the number. Symmetric around 20.0 km/h (the eight
        // values average exactly 20.0), so the running average converges there and the cycle then visits
        // the three states on purpose: clearly above (UP), clearly below (DOWN) and AT the average (NO
        // arrow -- the dead band), including the +/-0.1 edges where DEAD_BAND_TENTHS decides. The
        // no-arrow <-> arrow transitions are what reveals whether the number stays put when the arrow
        // comes and goes (SPEC 6.11).
        var speedsKmh = [30.0, 10.0, 20.0, 25.0, 15.0, 20.1, 19.9, 20.0];
        // Kept for reference, do not delete:
        //   original sweep -- average not centred, so the arrow stayed pinned most of the cycle:
        //var speedsKmh = [10.4, 25.7, 10.1, 30.2, 15.6, 20.3, 8.5, 28.9];
        //   near-constant slow ride, for watching the dead band alone:
        //var speedsKmh = [10.4, 10.2, 10.4, 10.4, 10.4, 10.4, 10.6, 10.3];
        var segSec = 3;                               // each segment lasts 3 s (fast cycling)
        var total = speedsKmh.size() * segSec;
        var phase = mSynTick % total;
        var idx = phase / segSec;                     // integer division -> segment index 0..7
        var curMps = speedsKmh[idx] / 3.6;
        mSynDist += curMps;                           // 1 s step
        mSynTime += 1;
        var avgMps = (mSynTime > 0) ? (mSynDist / mSynTime) : 0.0;
        mSynTick++;
        return [Activity.TIMER_STATE_ON, curMps, avgMps];
    }

    // Release stub: never called (TEST_MODE is const false -> the call site is eliminated).
    (:release)
    private function nextSynthetic() as Array {
        return [null, null, null];
    }

    // Prints the cell size + the engine's chosen fonts, once per distinct size. Use it to tune the
    // vertical layout across the 6 resolutions (same as A/B); the decisions themselves come from the
    // renderer, which is the code that took them.
    (:debug)
    private function debugMeasure(dc as Graphics.Dc, w as Number, h as Number) as Void {
        if (w == mDbgW && h == mDbgH) {
            return;
        }
        mDbgW = w;
        mDbgH = h;
        System.println("MEASURE cell=" + w + "x" + h + " " + mRenderer.debugSummary(dc));
    }

    // Release stub: never called (DEBUG_MEASURE is const false -> the call site is eliminated).
    (:release)
    private function debugMeasure(dc as Graphics.Dc, w as Number, h as Number) as Void {
    }
}
