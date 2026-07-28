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

    // Label glyph box, width/height. The native measures 23x18 in a small cell and 30x26 in a wide one
    // (1.28 and 1.15); 1.25 sits between them and, importantly, leaves room for the lower pedal, whose
    // far end reaches 1.205 of the height. See drawCadenceIcon for the geometry and its source.
    private const ICON_ASPECT = 1.25;

    private var mRenderer as TrendCore.TrendRenderer;

    // --- Labels. Both prefixes load once; the active one depends on the settings. ---
    private var mAvgPrefix as String = "AVG";
    private var mTargetPrefix as String = "GOAL";

    // --- Settings state. Re-read in onSettingsChanged, NEVER per tick. ---
    private var mUseTarget as Boolean = false;          // referenceMode == 1
    private var mTargetRpm as Number or Null = null;    // whole rpm; null = not usable

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
        mAvgPrefix = (WatchUi.loadResource(Rez.Strings.AvgLabel) as String).toUpper();
        mTargetPrefix = (WatchUi.loadResource(Rez.Strings.TargetLabel) as String).toUpper();
        mRenderer.setTemplates(VALUE_TPL, VALUE_TPL + TrendCore.INLINE_SEP + VALUE_TPL);
        // Cadence has no unit variants, so unlike speed this can be set once and never revisited.
        mRenderer.setUnit(CadenceFormat.unitTop(), CadenceFormat.unitBottom());
        // The crank glyph in front of the label, like the native field. The renderer reserves the box
        // and calls back; it never learns what the shape is.
        mRenderer.setLabelIcon(method(:drawCadenceIcon), ICON_ASPECT);

        reloadSettings();   // sets the labels too: the prefix depends on the settings
    }

    // Re-read the 2 app settings and derive what the arrow compares against. Called from initialize()
    // and from CadenceTrendApp.onSettingsChanged() -- NEVER per tick (same rule as font selection).
    function reloadSettings() as Void {
        mUseTarget = (readNumber("referenceMode", 0) == 1);
        // RAW value, not readNumber: that would truncate a stray decimal and defeat the rounding
        // inside targetRpm, which also treats anything non-numeric as "not configured".
        mTargetRpm = CadenceFormat.targetRpm(Application.Properties.getValue("targetCadence"));
        // GOAL/META only when the target is actually usable. Target mode with an unset, zero or
        // negative number behaves exactly like average mode, silently, so a half-configured setting
        // can never leave the field useless.
        var refPrefix = (mUseTarget && mTargetRpm != null) ? mTargetPrefix : mAvgPrefix;
        // setLabels invalidates the layout cache for us: the prefix width changed, and in a wide cell
        // it is part of the label text too ("CADENCIA / PROM").
        mRenderer.setLabels(
            (WatchUi.loadResource(Rez.Strings.CadenceLabel) as String).toUpper(),
            (WatchUi.loadResource(Rez.Strings.CadenceLabelShort) as String).toUpper(),
            refPrefix);
    }

    private function readNumber(key as String, dflt as Number) as Number {
        var v = Application.Properties.getValue(key);
        if (v instanceof Lang.Number) { return v; }
        if (v instanceof Lang.Float) { return v.toNumber(); }
        return dflt;
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
        // The reference the arrow AND the secondary line compare against: the fixed target when it is
        // configured and usable, else the ride average (silent fallback).
        var refRpm = (mUseTarget && mTargetRpm != null) ? mTargetRpm : avgRpm;
        mRefStr = CadenceFormat.displayString(refRpm);
        // trendValue, not the raw rpm: it returns null while coasting, so the classifier's null path
        // gives NONE and a 0 shows without a down arrow (CadenceFormat's header explains why). Applied
        // to the reference too -- an average of 0, the first seconds before you pedal, is not something
        // to compare against either.
        mArrowState = TrendCore.TrendArrow.classify(CadenceFormat.trendValue(curRpm),
                                                    CadenceFormat.trendValue(refRpm),
                                                    DEAD_BAND_RPM);
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        mRenderer.setValues(mCurStr, mRefStr, mArrowState, mRunning);
        // getBackgroundColor() is a DataField method, so the renderer cannot call it itself.
        mRenderer.draw(dc, getBackgroundColor());
    }

    // --- The label glyph: Garmin's cadence symbol, drawn with primitives -------------------------
    //
    // The native Edge field puts a small pictogram in front of some field names (a stopwatch on
    // TIEMPO, a heart on ZONA) and none on others (VELOCIDAD, DISTANCIA). CADENCIA gets a CRANK: a
    // ring with the crank arm crossing it diagonally and a pedal at each end.
    //
    // MEASURED off the author's 246x322 capture, not guessed: the glyph is 23x19 px next to a 12 px
    // cap height, and leaves 3 px before the text (that 3 is the renderer's ICON_GAP). Hence the
    // 23/19 aspect and the fractions below, which were checked by rendering this same geometry
    // offline at 13/17/19/25 px and comparing the pixels against the native ones. At 13 px it turns
    // to mush, which is why the renderer drops the glyph below ICON_MIN_H rather than smudging it.
    //
    // Primitives only, no font glyph: exactly the same reason as the trend arrow (a symbol's coverage
    // is not guaranteed across the 13 devices, and a missing glyph is INVISIBLE, not a box).
    //
    // Public and un-annotated on purpose: the barrel invokes it, and a barrel cannot depend on this
    // app's (:debug)/(:release) exclusions.
    function drawCadenceIcon(dc as Graphics.Dc, x as Number, y as Number, w as Number, h as Number) as Void {
        // FITTED AGAINST THE NATIVE'S PIXELS, AT TWO SIZES. The author sent enlarged captures of the
        // real 840 showing this glyph in a small cell (23x18 px) and in a full-width one (30x26 px);
        // both maps were extracted and this geometry was fitted against BOTH at once. Match: 87 % of
        // the pixels on the small one, 94 % on the large one. Having two sizes is what pinned the
        // proportions down -- one size alone cannot tell a fraction from a constant. Do not "tidy" a
        // number here without redoing that comparison.
        //
        // THE SHAPE. It is a crank seen at an angle: a ring, TWO arms on the same diagonal, and a
        // tilted pedal at the end of each. What took several readings to see is that
        //
        //     THE DIAGONAL IS INTERRUPTED AT THE CENTRE OF THE RING.
        //
        // The two arms are short stubs -- one from the upper left, one to the lower right -- with a
        // GAP between them where the hub would be. That is why drawing a full diameter looked wrong
        // (it reads as a "forbidden" sign, the ring gets filled) and why dropping the upper arm
        // altogether looked wrong too (the author spotted that one immediately: "the upper left crank
        // is not there, the line is missing"). Both errors were made here before this version.
        //
        // BOTH PEDALS ARE TILTED, and parallel to each other -- two platforms in the same perspective.
        // That tilt is most of what makes them read as pedals instead of dashes, and it is why they
        // are drawn as thick LINES rather than as rectangles.
        var ringT = (0.101 * h + 0.5).toNumber();
        if (ringT < 2) { ringT = 2; }
        var armT = (0.078 * h + 0.5).toNumber();
        if (armT < 2) { armT = 2; }
        var pedT = (0.10 * h + 0.5).toNumber();
        if (pedT < 2) { pedT = 2; }
        var cx = x + 0.59 * h;
        var cy = y + 0.46 * h;
        // Ring. Inset by half the stroke so the pen lands inside the radius.
        dc.setPenWidth(ringT);
        dc.drawCircle(cx, cy, 0.343 * h - ringT / 2.0);
        dc.setPenWidth(armT);
        // Upper-left arm: a stub that stops SHORT of the centre (see the gap note above). It reaches
        // a little further in than the native's ink does, and starts a little further back, because
        // below ~18 px a shorter stub disappears into the ring's edge and the crank reads as missing.
        dc.drawLine(x + 0.215 * h, y + 0.105 * h, x + 0.465 * h, y + 0.335 * h);
        // Lower-right arm: from the centre out, crossing the ring's lower right edge.
        dc.drawLine(cx, cy, x + 0.96 * h, y + 0.895 * h);
        // The two pedals.
        dc.setPenWidth(pedT);
        dc.drawLine(x + 0.345 * h, y + 0.03 * h, x, y + 0.12 * h);
        dc.drawLine(x + 1.205 * h, y + 0.87 * h, x + 0.77 * h, y + 0.94 * h);
        dc.setPenWidth(1);                             // restore: the renderer draws text next
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
