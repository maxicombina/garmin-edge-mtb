import Toybox.WatchUi;
import Toybox.Graphics;
import Toybox.Activity;
import Toybox.Lang;
import Toybox.System;

//
// Speed trend-arrow data field (Option J). THIN, non-testable wrapper by design (SPEC 3): compute()
// null-checks Activity.Info and delegates all logic to the PURE modules (TrendArrow, SpeedFormat);
// this file only reads inputs, formats display strings, and draws.
//
// MVP metric = speed (Tier 1): Garmin already gives BOTH current and average (currentSpeed /
// averageSpeed, m/s), so there is no buffer / smoothing / filter -- compute() is almost trivial
// (SPEC 5.3). The field shows the current speed (big, WITH a trend arrow) and, on tall enough
// cells, the average speed on a secondary line below (SPEC 6.1).
//
// Units follow the device pace-units setting (paceUnits, NOT distanceUnits/elevationUnits -- SPEC
// 2): UNIT_STATUTE -> mph, else km/h. Re-read every compute() (cheap): a device units change does
// NOT fire onSettingsChanged.
//
// The arrow is DATA (it changes every tick with current-vs-average), so unlike Option B's static
// grade ramp it sits next to the VALUE, not the label (SPEC intro / 6.1). The value has 1 decimal
// drawn as ONE string in ONE font -- the "." glyph is present in FONT_SYSTEM_NUMBER_* (SPEC 2).
//
class TrendArrowView extends WatchUi.DataField {

    // --- Layout tunables (SPEC 6.2). Calibrate in the simulator across the 6 resolutions. ---
    private const PAD = 3;               // horizontal padding per side, px
    private const LABEL_MARGIN = 4;      // px above the label
    private const LABEL_MIN_H = 60;      // >= this: draw the label (heredado de A, validado)
    private const AVG_MIN_H = 110;       // >= this: draw the secondary average line (to validate in sim)
    private const AVG_BAND_PCT = 35;     // % of the post-label height reserved to the average line
    private const ARROW_GAP = 4;         // px between the arrow and the current value
    private const AVG_LABEL_GAP = 4;     // px between the "AVG"/"PROM" prefix and the average number
    // Native-style unit: a small "km/h" drawn to the upper-right of the number as "km" over "h"
    // (like the native VELOCIDAD field), NOT baked into the label. Drawn in FONT_XTINY.
    private const UNIT_GAP = 3;          // px between the number and the stacked unit block
    private const UNIT_BOTTOM_NUDGE = 0; // px: fine vertical tweak of the unit (positive pushes DOWN);
                                         // the unit is baseline-aligned to the number (native look)
    // Vertical-centering trick (master spec 3.4, A 6.7, B 6.2): number fonts reserve descent the
    // digits don't use -> center then push DOWN by descent/2; VALUE_NUDGE is A's fine 2px-up tweak.
    private const VALUE_NUDGE = 2;       // px: raise the value a touch after the descent/2 drop
    private const ARROW_NUDGE = 2;       // px: align the arrow with the visible glyphs (B's idiom)
    private const VALUE_TPL = "888.8";   // width-stable template: 3 int digits + "." + 1 decimal
    // EXPERIMENTAL wide-cell mode (SPEC 6, to trial in the sim): a full-width field (w >= 80% of the
    // device screen width) shows BOTH values inline on one line as "[arrow] cur / avg" (e.g.
    // "24.1 / 15.0"), with the label reading "SPEED / AVG KM/H". Narrower cells keep the stacked
    // layout (big current+arrow, optional AVG line below).
    private const WIDE_NUM = 8;          // wide iff w * WIDE_DEN >= screenWidth * WIDE_NUM ...
    private const WIDE_DEN = 10;         // ... i.e. cell width >= 80% of the screen width
    private const INLINE_SEP = " / ";    // separator between current and average in wide mode
    private const INLINE_TPL = "888.8 / 888.8";  // width-stable template for the inline pair

    // Number-font ladder, largest -> smallest (SPEC 6.3). System number fonts first, like A/B.
    private var mLadder as Array<Graphics.FontType> = [];

    // Labels loaded once, uppercased.
    private var mLabel as String = "SPEED";
    private var mAvgPrefix as String = "AVG";

    // --- Live display state, rebuilt every second in compute() ---
    private var mCurStr as String = "--";
    private var mAvgStr as String = "--";
    private var mBothStr as String = "-- / --";   // "cur / avg" for the wide inline mode
    private var mArrowState as Number = 0;   // TrendArrow.UP / NONE / DOWN
    private var mRunning as Boolean = false;
    private var mIsStatute as Boolean = false;   // device paceUnits == statute (re-read each tick)
    private var mUnitTop as String = "km";       // native stacked unit, top line ("km"/"mph")
    private var mUnitBottom as String = "h";     // native stacked unit, bottom line ("h"/"" for statute)

    // --- Layout cache: re-run selectFonts only when the cell size or the unit system changes. ---
    private var mCacheW as Number = -1;
    private var mCacheH as Number = -1;
    private var mCacheStatute as Boolean = false;
    private var mLabelH as Number = 0;            // 0 if the label is not shown
    private var mShowAvg as Boolean = false;
    private var mPrimaryBandH as Number = 0;      // height of the current-value band (below the label)
    private var mAvgBandH as Number = 0;          // height of the average band (below the primary band)
    private var mValueFont as Graphics.FontType = Graphics.FONT_MEDIUM;
    private var mAvgFont as Graphics.FontType = Graphics.FONT_XTINY;
    private var mArrowFits as Boolean = false;    // did [arrow + gap + value] fit at the chosen font?
    // --- EXPERIMENTAL wide-cell (inline both-values) state ---
    private var mIsWide as Boolean = false;                 // full-width cell -> inline "cur / avg"
    private var mInlineFont as Graphics.FontType = Graphics.FONT_MEDIUM;
    private var mInlineArrowFits as Boolean = false;        // did [arrow + gap + pair] fit?

    // --- Simulator test hook (SPEC 11). TEST_MODE stays a PLAIN const false so the guard in
    //     compute() is dead-code-eliminated in release (-r drops the block AND the call); the
    //     synthetic generator and its state are (:debug)-only, and a (:release) stub keeps the
    //     call site resolving. Flip to true + run a DEBUG build to drive the field without a FIT:
    //     a speed profile whose running average converges realistically, so all 3 arrow states
    //     and the average line are visible. ---
    private const TEST_MODE = false;
    (:debug) private var mSynTick as Number = 0;
    (:debug) private var mSynDist as Float = 0.0;   // synthetic accumulated distance (m)
    (:debug) private var mSynTime as Number = 0;    // synthetic accumulated moving time (s)

    // --- Simulator measurement hook (SPEC 11, same scheme as A/B). ---
    private const DEBUG_MEASURE = false;
    (:debug) private var mDbgW as Number = -1;
    (:debug) private var mDbgH as Number = -1;

    function initialize() {
        DataField.initialize();

        mLadder = [
            Graphics.FONT_SYSTEM_NUMBER_THAI_HOT,
            Graphics.FONT_SYSTEM_NUMBER_HOT,
            Graphics.FONT_SYSTEM_NUMBER_MEDIUM,
            Graphics.FONT_SYSTEM_NUMBER_MILD,
            Graphics.FONT_MEDIUM,
            Graphics.FONT_SMALL,
            Graphics.FONT_TINY,
            Graphics.FONT_XTINY
        ];

        mLabel = (WatchUi.loadResource(Rez.Strings.SpeedLabel) as String).toUpper();
        mAvgPrefix = (WatchUi.loadResource(Rez.Strings.AvgLabel) as String).toUpper();
    }

    // Runs ~1x/second. Reads inputs, formats the display strings. No drawing (SPEC 5.3).
    function compute(info as Activity.Info) as Void {
        // Device pace units can change without firing onSettingsChanged -> re-read each tick.
        mIsStatute = (System.getDeviceSettings().paceUnits == System.UNIT_STATUTE);
        mUnitTop = SpeedFormat.unitTop(mIsStatute);
        mUnitBottom = SpeedFormat.unitBottom(mIsStatute);

        var state = null;
        var curMps = null;
        var avgMps = null;

        if (TEST_MODE) {
            // Body is (:debug)-only; the const-false guard drops this whole block in release.
            // Everything comes back through the return value so compute() never references a
            // (:debug) member directly (that would fail to resolve in a release build).
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

        // shownTenths is the ONLY rounding: the string and the arrow both start from it (SPEC 5.2),
        // so the number and the arrow can never contradict each other.
        var curTenths = SpeedFormat.shownTenths(curMps, mIsStatute);
        var avgTenths = SpeedFormat.shownTenths(avgMps, mIsStatute);
        mCurStr = SpeedFormat.displayString(curTenths);
        mAvgStr = SpeedFormat.displayString(avgTenths);
        mBothStr = mCurStr + INLINE_SEP + mAvgStr;   // used only by the wide inline mode
        mArrowState = TrendArrow.classify(curTenths, avgTenths);
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();

        // Colours: contrast against the black/white theme; grey everything when not running.
        var bg = getBackgroundColor();
        var fg = Graphics.COLOR_BLACK;
        if (bg == Graphics.COLOR_BLACK) {
            fg = mRunning ? Graphics.COLOR_WHITE : Graphics.COLOR_LT_GRAY;
        } else {
            fg = mRunning ? Graphics.COLOR_BLACK : Graphics.COLOR_DK_GRAY;
        }
        dc.setColor(fg, bg);
        dc.clear();

        // Font/layout selection is cached; re-run only when the cell size or unit system changes.
        if (w != mCacheW || h != mCacheH || mIsStatute != mCacheStatute) {
            selectFonts(dc, w, h);
            mCacheW = w;
            mCacheH = h;
            mCacheStatute = mIsStatute;
        }

        if (DEBUG_MEASURE) {
            // (:debug)-only body; the const-false guard drops it (and the call) in release.
            debugMeasure(dc, w, h);
        }

        // Label = metric name only (the unit is now drawn next to the number, native style).
        // Wide mode names both columns: "SPEED / AVG".
        if (mLabelH > 0) {
            dc.setColor(fg, Graphics.COLOR_TRANSPARENT);
            var labelText = mIsWide ? (mLabel + INLINE_SEP + mAvgPrefix) : mLabel;
            dc.drawText(w / 2, LABEL_MARGIN, Graphics.FONT_GLANCE, labelText,
                        Graphics.TEXT_JUSTIFY_CENTER);
        }

        // Wide (full-width) cell: both values inline on one line, "[arrow] cur / avg [unit]".
        if (mIsWide) {
            var cyW = mLabelH + mPrimaryBandH / 2 + Graphics.getFontDescent(mInlineFont) / 2 - VALUE_NUDGE;
            var showArrowW = mInlineArrowFits && (mArrowState != TrendArrow.NONE) && !mCurStr.equals("--");
            drawTrendValue(dc, w, fg, mInlineFont, mBothStr, cyW, showArrowW);
            return;
        }

        // --- Current value + arrow + native stacked unit, centred in the primary band ---
        var primaryCy = mLabelH + mPrimaryBandH / 2 + Graphics.getFontDescent(mValueFont) / 2 - VALUE_NUDGE;
        var showArrow = mArrowFits && (mArrowState != TrendArrow.NONE) && !mCurStr.equals("--");
        drawTrendValue(dc, w, fg, mValueFont, mCurStr, primaryCy, showArrow);

        // --- Average line (only if the cell is tall enough): "AVG 21.7 [unit]" ---
        if (mShowAvg) {
            var avgCy = mLabelH + mPrimaryBandH + mAvgBandH / 2 + Graphics.getFontDescent(mAvgFont) / 2 - VALUE_NUDGE;
            var wAvg = dc.getTextWidthInPixels(mAvgStr, mAvgFont);
            var prefixW = dc.getTextWidthInPixels(mAvgPrefix, Graphics.FONT_XTINY);
            var uW = unitBlockWidth(dc, Graphics.FONT_XTINY);
            var totalAvgW = prefixW + AVG_LABEL_GAP + wAvg + UNIT_GAP + uW;
            var ax = w / 2 - totalAvgW / 2;
            dc.setColor(fg, Graphics.COLOR_TRANSPARENT);
            dc.drawText(ax, avgCy, Graphics.FONT_XTINY, mAvgPrefix,
                        Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
            var numX = ax + prefixW + AVG_LABEL_GAP;
            dc.drawText(numX, avgCy, mAvgFont, mAvgStr,
                        Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
            var avgBaseY = avgCy + (Graphics.getFontAscent(mAvgFont) - Graphics.getFontDescent(mAvgFont)) / 2 + UNIT_BOTTOM_NUDGE;
            drawStackedUnit(dc, numX + wAvg + UNIT_GAP, avgBaseY, Graphics.FONT_XTINY);
        }
    }

    // Draws "[arrow] value [stacked unit]" as one horizontally-centred group, the value VCENTREd on
    // cy. Used by both the stacked primary line and the wide inline line (value = "cur / avg" there).
    // The arrow (trend of current vs average) precedes the value; the native km/h unit follows it.
    private function drawTrendValue(dc as Graphics.Dc, w as Number, fg as Graphics.ColorType,
                                    valueFont as Graphics.FontType, valueStr as String,
                                    cy as Number, showArrow as Boolean) as Void {
        var unitFont = Graphics.FONT_XTINY;
        var vW = dc.getTextWidthInPixels(valueStr, valueFont);
        var uW = unitBlockWidth(dc, unitFont);
        var aW = 0;
        var aH = 0;
        if (showArrow) {
            aH = (Graphics.getFontAscent(valueFont) * 4) / 5;
            aW = (aH * 3) / 5;
        }
        var lead = showArrow ? (aW + ARROW_GAP) : 0;
        var totalW = lead + vW + UNIT_GAP + uW;
        var x = w / 2 - totalW / 2;
        var vx = x + lead;
        dc.setColor(fg, Graphics.COLOR_TRANSPARENT);
        if (showArrow) {
            // Value is VCENTREd on its box, whose descent the digits don't use -> centre the arrow on
            // the visible glyphs (cy - descent/2), then a fine +ARROW_NUDGE (B's idiom).
            var arrowCy = cy - Graphics.getFontDescent(valueFont) / 2 + ARROW_NUDGE;
            if (mArrowState == TrendArrow.UP) {
                drawUpArrow(dc, x, arrowCy, aW, aH);
            } else {
                drawDownArrow(dc, x, arrowCy, aW, aH);
            }
        }
        dc.drawText(vx, cy, valueFont, valueStr, Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
        // Unit is baseline-aligned to the number's baseline (native look: the "h" sits on the same
        // line as the digits' feet). numberBaseline for a VCENTREd value = cy + (ascent - descent)/2.
        var baseY = cy + (Graphics.getFontAscent(valueFont) - Graphics.getFontDescent(valueFont)) / 2 + UNIT_BOTTOM_NUDGE;
        drawStackedUnit(dc, vx + vW + UNIT_GAP, baseY, unitFont);
    }

    // Width of the stacked unit block = max width of its two lines (bottom may be empty -> width 0).
    private function unitBlockWidth(dc as Graphics.Dc, unitFont as Graphics.FontType) as Number {
        var wt = dc.getTextWidthInPixels(mUnitTop, unitFont);
        var wb = (mUnitBottom.length() > 0) ? dc.getTextWidthInPixels(mUnitBottom, unitFont) : 0;
        return (wt > wb) ? wt : wb;
    }

    // Draws the native stacked unit ("km" over "h"), BOTTOM-aligned: the bottom line's baseline sits
    // at baseY (= the number's baseline), so "h" rests on the digits' feet like the native field. The
    // top line sits one ascent above (tight). A single line (empty bottom, e.g. "mph") is placed with
    // its own baseline at baseY. drawText's y is the TOP of the glyph box; baseline = y + ascent.
    private function drawStackedUnit(dc as Graphics.Dc, xLeft as Number, baseY as Number, unitFont as Graphics.FontType) as Void {
        var uAsc = Graphics.getFontAscent(unitFont);
        if (mUnitBottom.length() > 0) {
            dc.drawText(xLeft, baseY - 2 * uAsc, unitFont, mUnitTop, Graphics.TEXT_JUSTIFY_LEFT);
            dc.drawText(xLeft, baseY - uAsc, unitFont, mUnitBottom, Graphics.TEXT_JUSTIFY_LEFT);
        } else {
            dc.drawText(xLeft, baseY - uAsc, unitFont, mUnitTop, Graphics.TEXT_JUSTIFY_LEFT);
        }
    }

    // --- Font + band selection (measures the width-stable template; cached by onUpdate) --------
    private function selectFonts(dc as Graphics.Dc, w as Number, h as Number) as Void {
        var usableW = w - 2 * PAD;
        var labelShow = (h >= LABEL_MIN_H);
        mLabelH = labelShow ? (LABEL_MARGIN + Graphics.getFontAscent(Graphics.FONT_GLANCE) + 2) : 0;

        // Full-width cell? Compare against the device screen width (screenWidth is always present).
        var screenW = System.getDeviceSettings().screenWidth;
        mIsWide = (screenW != null) && (w * WIDE_DEN >= screenW * WIDE_NUM);
        if (mIsWide) {
            // One line: no separate stacked average band. Pick the largest font whose
            // [arrow + gap + "888.8 / 888.8"] fits the width, height-capped to the post-label band.
            mShowAvg = false;
            mPrimaryBandH = h - mLabelH;
            mAvgBandH = 0;
            selectInlineFont(dc, usableW);
            return;
        }

        mShowAvg = (h >= AVG_MIN_H);   // implies labelShow (AVG_MIN_H > LABEL_MIN_H)

        var postLabelH = h - mLabelH;
        if (mShowAvg) {
            mPrimaryBandH = (postLabelH * (100 - AVG_BAND_PCT)) / 100;
            mAvgBandH = postLabelH - mPrimaryBandH;
        } else {
            mPrimaryBandH = postLabelH;
            mAvgBandH = 0;
        }

        // Native stacked unit width (fixed FONT_XTINY) reserved in every group below.
        var unitW = unitBlockWidth(dc, Graphics.FONT_XTINY);

        // --- Current value font: largest whose [arrow + gap + "888.8" + gap + unit] fits. ---
        mValueFont = Graphics.FONT_XTINY;
        mArrowFits = false;
        for (var i = 0; i < mLadder.size(); i++) {
            var f = mLadder[i];
            if (dc.getFontHeight(f) > (mPrimaryBandH * 9) / 10) { continue; }
            var ah = (Graphics.getFontAscent(f) * 4) / 5;
            var aw = (ah * 3) / 5;
            var groupW = aw + ARROW_GAP + dc.getTextWidthInPixels(VALUE_TPL, f) + UNIT_GAP + unitW;
            if (groupW <= usableW) {
                mValueFont = f;
                mArrowFits = true;
                break;
            }
        }
        if (!mArrowFits) {
            // Arrow fits at no size (very narrow cell) -> graceful fallback: drop the arrow, pick
            // the largest font the [value + unit] fits (same idiom as B's ramp fallback).
            for (var i = 0; i < mLadder.size(); i++) {
                var f = mLadder[i];
                var groupW = dc.getTextWidthInPixels(VALUE_TPL, f) + UNIT_GAP + unitW;
                if (groupW <= usableW && dc.getFontHeight(f) <= (mPrimaryBandH * 9) / 10) {
                    mValueFont = f;
                    break;
                }
            }
        }

        // --- Average font (no arrow; its own fixed-size prefix + the stacked unit). ---
        mAvgFont = Graphics.FONT_XTINY;
        if (mShowAvg) {
            var prefixW = dc.getTextWidthInPixels(mAvgPrefix, Graphics.FONT_XTINY);
            for (var i = 0; i < mLadder.size(); i++) {
                var f = mLadder[i];
                if (dc.getFontHeight(f) > (mAvgBandH * 85) / 100) { continue; }
                var groupW = prefixW + AVG_LABEL_GAP + dc.getTextWidthInPixels(VALUE_TPL, f) + UNIT_GAP + unitW;
                if (groupW <= usableW) {
                    mAvgFont = f;
                    break;
                }
            }
        }
    }

    // --- Wide-mode font: largest whose [arrow + gap + "888.8 / 888.8" + gap + unit] fits; else drop
    //     the arrow. One stacked unit follows the whole "cur / avg" pair.
    private function selectInlineFont(dc as Graphics.Dc, usableW as Number) as Void {
        var unitW = unitBlockWidth(dc, Graphics.FONT_XTINY);
        mInlineFont = Graphics.FONT_XTINY;
        mInlineArrowFits = false;
        for (var i = 0; i < mLadder.size(); i++) {
            var f = mLadder[i];
            if (dc.getFontHeight(f) > (mPrimaryBandH * 9) / 10) { continue; }
            var ah = (Graphics.getFontAscent(f) * 4) / 5;
            var aw = (ah * 3) / 5;
            var groupW = aw + ARROW_GAP + dc.getTextWidthInPixels(INLINE_TPL, f) + UNIT_GAP + unitW;
            if (groupW <= usableW) {
                mInlineFont = f;
                mInlineArrowFits = true;
                break;
            }
        }
        if (!mInlineArrowFits) {
            // Arrow fits at no size -> graceful fallback: fit the [pair + unit] alone.
            for (var i = 0; i < mLadder.size(); i++) {
                var f = mLadder[i];
                var groupW = dc.getTextWidthInPixels(INLINE_TPL, f) + UNIT_GAP + unitW;
                if (groupW <= usableW && dc.getFontHeight(f) <= (mPrimaryBandH * 9) / 10) {
                    mInlineFont = f;
                    break;
                }
            }
        }
    }


    // Small solid up-arrow (filled triangular head + rectangular stem), occupying [x0, x0+w]
    // horizontally and centred vertically on cyMid with height h. COPY of Option B's drawUpArrow
    // (apps/b-grade-vam/source/GradeVamView.mc). Paints in the colour the caller set; fill ops
    // ignore pen width, so nothing to restore.
    private function drawUpArrow(dc as Graphics.Dc, x0 as Number, cyMid as Number, w as Number, h as Number) as Void {
        var top = cyMid - h / 2;
        var headH = (h * 55) / 100;
        var headBase = top + headH;
        dc.fillPolygon([[x0 + w / 2, top], [x0, headBase], [x0 + w, headBase]]);
        var stemW = w / 3;
        if (stemW < 2) { stemW = 2; }
        dc.fillRectangle(x0 + w / 2 - stemW / 2, headBase, stemW, h - headH);
    }

    // Vertical mirror of drawUpArrow: head at the BOTTOM (apex pointing down), stem on top. Same
    // 55%-head proportion and stem width.
    private function drawDownArrow(dc as Graphics.Dc, x0 as Number, cyMid as Number, w as Number, h as Number) as Void {
        var bot = cyMid + h / 2;
        var headH = (h * 55) / 100;
        var headTop = bot - headH;
        dc.fillPolygon([[x0 + w / 2, bot], [x0, headTop], [x0 + w, headTop]]);
        var stemW = w / 3;
        if (stemW < 2) { stemW = 2; }
        dc.fillRectangle(x0 + w / 2 - stemW / 2, cyMid - h / 2, stemW, h - headH);
    }

    // --- Simulator-only synthetic generator (SPEC 11). One call = one second. Walks a speed
    //     profile and accumulates its own distance/time so the running average = dist/time
    //     converges like Garmin's. Forces TIMER_STATE_ON. Returns [state, curMps, avgMps].
    //     (:debug) only; see the TEST_MODE note above. ---
    (:debug)
    private function nextSynthetic() as Array {
        var speedsKmh = [10.4, 25.7, 10.1, 30.2, 15.6, 20.3, 8.5, 28.9];
        var segSec = 4;                               // each segment lasts 4 s (faster sim cycling)
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

    // Prints each distinct cell size + the chosen fonts + arrow/avg flags, once per size. Use it to
    // tune the vertical layout across the 6 resolutions (same as A/B).
    (:debug)
    private function debugMeasure(dc as Graphics.Dc, w as Number, h as Number) as Void {
        if (w == mDbgW && h == mDbgH) {
            return;
        }
        mDbgW = w;
        mDbgH = h;
        System.println("MEASURE cell=" + w + "x" + h
            + " valueF h/a/d=" + dc.getFontHeight(mValueFont) + "/"
                + Graphics.getFontAscent(mValueFont) + "/" + Graphics.getFontDescent(mValueFont)
            + " avgF h=" + dc.getFontHeight(mAvgFont)
            + " labelH=" + mLabelH + " showAvg=" + mShowAvg + " arrowFits=" + mArrowFits);
    }

    // Release stub: never called (DEBUG_MEASURE is const false -> the call site is eliminated).
    (:release)
    private function debugMeasure(dc as Graphics.Dc, w as Number, h as Number) as Void {
    }
}
