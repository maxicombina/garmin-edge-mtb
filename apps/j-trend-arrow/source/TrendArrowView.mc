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
    // Native-style unit: a small "km/h" drawn to the right of the number as "km" over "h", the two
    // lines CENTRED on each other and the bottom line's baseline on the digits' baseline -- measured
    // off the native VELOCIDAD field (2026-07-25, edge840 sim @246x322: digits ink 27px tall, unit
    // ink 11px per line, unit baselines 14px apart, "h" centred under "km"). NOT baked into the label.
    private const UNIT_GAP = 3;          // px between the number and the stacked unit block
    private const UNIT_LINE_GAP = 2;     // px added to the unit ascent to space the two stacked lines
    private const UNIT_BOTTOM_NUDGE = 0; // px: fine vertical tweak of the unit (positive pushes DOWN);
                                         // the unit is baseline-aligned to the number (native look)
    // Unit size is PROPORTIONAL to the number (native ratio: ascent 12 of a 33 number ascent ~ 2/5),
    // not a fixed FONT_XTINY -- that was what made our "km/h" look like a speck next to the native.
    private const UNIT_NUM = 2;          // unit ascent <= number ascent * UNIT_NUM / UNIT_DEN
    private const UNIT_DEN = 5;
    private const UNIT_SHRINK_STEPS = 2; // width-bound cells may shrink the unit this many ladder
                                         // steps below proportional before the NUMBER gives up a size
    // Vertical-centering trick (master spec 3.4, A 6.7, B 6.2): number fonts reserve descent the
    // digits don't use -> center then push DOWN by descent/2; VALUE_NUDGE is A's fine 2px-up tweak.
    private const VALUE_NUDGE = 2;       // px: raise the value a touch after the descent/2 drop
    private const ARROW_NUDGE = 2;       // px: align the arrow with the visible glyphs (B's idiom)
    // The SAME descent-is-unused fact also decides which number font fits a band: gate on the font's
    // ASCENT, not its full height. A number font's height includes a descent the digits never use, so
    // the old "height <= 90% of the band" gate dropped a whole size for nothing -- that is why our
    // number came out smaller than the native one in the same cell (native fits a 42px-tall font in a
    // 41px band because only its 33px ascent is ever painted). BAND_SLACK is the safety margin.
    private const BAND_SLACK = 2;        // px kept free between the number's ascent and the band
    private const VALUE_TPL = "88.8";    // width-stable template: 2 int digits + "." + 1 decimal.
                                         // SpeedFormat drops the decimal at >= 100 precisely so that
                                         // no real value is ever wider than this (SPEC 5.2).
    // Wide-cell mode (SPEC 6.8): a full-width field (w >= 80% of the device screen width) that is
    // ALSO SHORT (no room to stack) shows BOTH values inline on one line as "[arrow] cur / avg"
    // (e.g. "24.1 / 15.0"), label "SPEED / AVG". A full-width field that is TALL falls through to the
    // stacked layout instead (big current + arrow, average on its own line) -- a one-line inline can
    // only grow as wide as the cell, so a tall wide cell gets a much bigger number when stacked.
    private const WIDE_NUM = 8;          // wide iff w * WIDE_DEN >= screenWidth * WIDE_NUM ...
    private const WIDE_DEN = 10;         // ... i.e. cell width >= 80% of the screen width
    private const INLINE_SEP = " / ";    // separator between current and average in wide mode
    private const INLINE_TPL = "88.8 / 88.8";  // width-stable template for the inline pair

    // Number-font ladder, largest -> smallest (SPEC 6.3). System number fonts first, like A/B.
    private var mLadder as Array<Graphics.FontType> = [];
    // Text-font ladder, largest -> smallest: used for the stacked unit, the "AVG" prefix and the
    // label fallback (a proportional unit needs to walk sizes, so it cannot be a fixed font).
    private var mTextLadder as Array<Graphics.FontType> = [];

    // Labels loaded once, uppercased. The long name is drawn when it fits the cell ("VELOCIDAD",
    // like the native field); mLabelShort is the narrow-cell fallback ("VEL").
    private var mLabelLong as String = "SPEED";
    private var mLabelShort as String = "SPEED";
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
    private var mLabelText as String = "";        // long or short name, whichever fits (see selectLabel)
    private var mLabelFont as Graphics.FontType = Graphics.FONT_GLANCE;
    private var mShowAvg as Boolean = false;
    private var mPrimaryBandH as Number = 0;      // height of the current-value band (below the label)
    private var mAvgBandH as Number = 0;          // height of the average band (below the primary band)
    private var mValueFont as Graphics.FontType = Graphics.FONT_MEDIUM;
    private var mUnitFont as Graphics.FontType = Graphics.FONT_XTINY;      // unit next to the value
    private var mAvgFont as Graphics.FontType = Graphics.FONT_XTINY;
    private var mAvgUnitFont as Graphics.FontType = Graphics.FONT_XTINY;   // unit + prefix of the avg line
    private var mArrowFits as Boolean = false;    // did [arrow + gap + value] fit at the chosen font?
    // --- EXPERIMENTAL wide-cell (inline both-values) state ---
    private var mIsWide as Boolean = false;                 // full-width cell -> inline "cur / avg"
    private var mInlineFont as Graphics.FontType = Graphics.FONT_MEDIUM;
    private var mInlineUnitFont as Graphics.FontType = Graphics.FONT_XTINY;
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

    // Semantic dead-band for the trend arrow, in TENTHS of the display unit (SPEC 5.1). 1 == 0.1
    // km/h (or mph): a current-vs-average gap of <= 0.1 reads as "at the average" (no arrow); only
    // a gap > 0.1 earns an up/down arrow. NOT anti-flicker -- it defines what "above/below" means.
    private const DEAD_BAND_TENTHS = 1;

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

        mTextLadder = [
            Graphics.FONT_MEDIUM,
            Graphics.FONT_SMALL,
            Graphics.FONT_TINY,
            Graphics.FONT_XTINY
        ];

        mLabelLong = (WatchUi.loadResource(Rez.Strings.SpeedLabel) as String).toUpper();
        mLabelShort = (WatchUi.loadResource(Rez.Strings.SpeedLabelShort) as String).toUpper();
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

        // shownTenths is the ONLY rounding: the string and the arrow both start from it (SPEC 5.2).
        // The arrow compares those same tenths, but through a semantic dead-band (DEAD_BAND_TENTHS)
        // -- so a gap of <= 0.1 shows the two numbers slightly apart yet NO arrow, on purpose: that
        // gap means "at the average" (SPEC 5.1).
        var curTenths = SpeedFormat.shownTenths(curMps, mIsStatute);
        var avgTenths = SpeedFormat.shownTenths(avgMps, mIsStatute);
        mCurStr = SpeedFormat.displayString(curTenths);
        mAvgStr = SpeedFormat.displayString(avgTenths);
        mBothStr = mCurStr + INLINE_SEP + mAvgStr;   // used only by the wide inline mode
        mArrowState = TrendArrow.classify(curTenths, avgTenths, DEAD_BAND_TENTHS);
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

        // Label = metric NAME only (the unit is drawn next to the number, native style). The text and
        // its font were picked in selectFonts: long name if it fits, else short, else shrunk.
        if (mLabelH > 0) {
            dc.setColor(fg, Graphics.COLOR_TRANSPARENT);
            dc.drawText(w / 2, LABEL_MARGIN, mLabelFont, mLabelText, Graphics.TEXT_JUSTIFY_CENTER);
        }

        // Wide (full-width) cell: both values inline on one line, "[arrow] cur / avg [unit]".
        if (mIsWide) {
            var cyW = mLabelH + mPrimaryBandH / 2 + Graphics.getFontDescent(mInlineFont) / 2 - VALUE_NUDGE;
            var showArrowW = mInlineArrowFits && (mArrowState != TrendArrow.NONE) && !mCurStr.equals("--");
            drawTrendValue(dc, w, fg, mInlineFont, mInlineUnitFont, mBothStr, cyW, showArrowW);
            return;
        }

        // --- Current value + arrow + native stacked unit, centred in the primary band ---
        var primaryCy = mLabelH + mPrimaryBandH / 2 + Graphics.getFontDescent(mValueFont) / 2 - VALUE_NUDGE;
        var showArrow = mArrowFits && (mArrowState != TrendArrow.NONE) && !mCurStr.equals("--");
        drawTrendValue(dc, w, fg, mValueFont, mUnitFont, mCurStr, primaryCy, showArrow);

        // --- Average line (only if the cell is tall enough): "AVG 21.7 [unit]" ---
        if (mShowAvg) {
            var avgCy = mLabelH + mPrimaryBandH + mAvgBandH / 2 + Graphics.getFontDescent(mAvgFont) / 2 - VALUE_NUDGE;
            var wAvg = dc.getTextWidthInPixels(mAvgStr, mAvgFont);
            var prefixW = dc.getTextWidthInPixels(mAvgPrefix, mAvgUnitFont);
            var uW = unitBlockWidth(dc, mAvgUnitFont);
            var totalAvgW = prefixW + AVG_LABEL_GAP + wAvg + UNIT_GAP + uW;
            var ax = w / 2 - totalAvgW / 2;
            dc.setColor(fg, Graphics.COLOR_TRANSPARENT);
            dc.drawText(ax, avgCy, mAvgUnitFont, mAvgPrefix,
                        Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
            var numX = ax + prefixW + AVG_LABEL_GAP;
            dc.drawText(numX, avgCy, mAvgFont, mAvgStr,
                        Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
            var avgBaseY = avgCy + (Graphics.getFontAscent(mAvgFont) - Graphics.getFontDescent(mAvgFont)) / 2 + UNIT_BOTTOM_NUDGE;
            drawStackedUnit(dc, numX + wAvg + UNIT_GAP, avgBaseY, mAvgUnitFont);
        }
    }

    // Draws "[arrow] value [stacked unit]" as one horizontally-centred group, the value VCENTREd on
    // cy. Used by both the stacked primary line and the wide inline line (value = "cur / avg" there).
    // The arrow (trend of current vs average) precedes the value; the native km/h unit follows it.
    private function drawTrendValue(dc as Graphics.Dc, w as Number, fg as Graphics.ColorType,
                                    valueFont as Graphics.FontType, unitFont as Graphics.FontType,
                                    valueStr as String,
                                    cy as Number, showArrow as Boolean) as Void {
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
    // two lines are CENTRED on each other inside the block (the native centres the "h" under the
    // "km" -- measured 2026-07-25), and their baselines are one ascent + UNIT_LINE_GAP apart. A single
    // line (empty bottom, e.g. "mph") is placed with its own baseline at baseY. drawText's y is the
    // TOP of the glyph box; baseline = y + ascent.
    private function drawStackedUnit(dc as Graphics.Dc, xLeft as Number, baseY as Number, unitFont as Graphics.FontType) as Void {
        var uAsc = Graphics.getFontAscent(unitFont);
        var cx = xLeft + unitBlockWidth(dc, unitFont) / 2;
        if (mUnitBottom.length() > 0) {
            dc.drawText(cx, baseY - 2 * uAsc - UNIT_LINE_GAP, unitFont, mUnitTop, Graphics.TEXT_JUSTIFY_CENTER);
            dc.drawText(cx, baseY - uAsc, unitFont, mUnitBottom, Graphics.TEXT_JUSTIFY_CENTER);
        } else {
            dc.drawText(cx, baseY - uAsc, unitFont, mUnitTop, Graphics.TEXT_JUSTIFY_CENTER);
        }
    }

    // --- Font + band selection (measures the width-stable template; cached by onUpdate) --------
    private function selectFonts(dc as Graphics.Dc, w as Number, h as Number) as Void {
        var usableW = w - 2 * PAD;
        var labelShow = (h >= LABEL_MIN_H);

        // Full-width cell? Compare against the device screen width (screenWidth is always present).
        // Inline "cur / avg" is used ONLY when the cell is also SHORT (h < AVG_MIN_H -> no room to
        // stack a second line). A full-width cell that IS tall falls through to the stacked layout
        // below, where the current value gets a BIG font (bounded by height, not by the long inline
        // string) and the average sits on its own line -- the author's choice for the large wide cell.
        var screenW = System.getDeviceSettings().screenWidth;
        var fullWidth = (screenW != null) && (w * WIDE_DEN >= screenW * WIDE_NUM);
        mIsWide = fullWidth && (h < AVG_MIN_H);

        // Label text + font (depends on mIsWide: the wide mode names both columns).
        mLabelH = 0;
        mLabelText = "";
        if (labelShow) {
            selectLabel(dc, usableW);
            mLabelH = LABEL_MARGIN + Graphics.getFontAscent(mLabelFont) + 2;
        }

        if (mIsWide) {
            // One line: no separate stacked average band. Pick the largest font whose
            // [arrow + gap + "888.8 / 888.8" + unit] fits the width, height-capped to the band.
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

        // --- Current value font: largest whose ASCENT fits the band (see BAND_SLACK) and whose
        //     [arrow + gap + "88.8" + gap + proportional unit] fits the width. ---
        mValueFont = Graphics.FONT_XTINY;
        mUnitFont = Graphics.FONT_XTINY;
        mArrowFits = false;
        for (var i = 0; i < mLadder.size(); i++) {
            var f = mLadder[i];
            if (!fitsBand(f, mPrimaryBandH)) { continue; }
            var ah = (Graphics.getFontAscent(f) * 4) / 5;
            var aw = (ah * 3) / 5;
            var u = fitUnitFont(dc, f, VALUE_TPL, aw + ARROW_GAP, usableW, false);
            if (u != null) {
                mValueFont = f;
                mUnitFont = u;
                mArrowFits = true;
                break;
            }
        }
        if (!mArrowFits) {
            // Arrow fits at no size (very narrow cell) -> graceful fallback: drop the arrow, pick
            // the largest font the [value + unit] fits (same idiom as B's ramp fallback).
            for (var i = 0; i < mLadder.size(); i++) {
                var f = mLadder[i];
                if (!fitsBand(f, mPrimaryBandH)) { continue; }
                var u = fitUnitFont(dc, f, VALUE_TPL, 0, usableW, false);
                if (u != null) {
                    mValueFont = f;
                    mUnitFont = u;
                    break;
                }
            }
        }

        // --- Average font (no arrow; the "AVG" prefix shares the unit font so the whole secondary
        //     line scales together). ---
        mAvgFont = Graphics.FONT_XTINY;
        mAvgUnitFont = Graphics.FONT_XTINY;
        if (mShowAvg) {
            for (var i = 0; i < mLadder.size(); i++) {
                var f = mLadder[i];
                if (!fitsBand(f, mAvgBandH)) { continue; }
                var u = fitUnitFont(dc, f, VALUE_TPL, 0, usableW, true);
                if (u != null) {
                    mAvgFont = f;
                    mAvgUnitFont = u;
                    break;
                }
            }
        }
    }

    // --- Label: the long metric name if it fits the cell, else the short one, else the short one
    //     shrunk down the text ladder (last resort; may still clip in an absurdly narrow cell).
    //     Wide mode names both columns ("VELOCIDAD / PROM"). Mirrors what the native field does:
    //     full name in wide cells, abbreviation in narrow ones. ---
    private function selectLabel(dc as Graphics.Dc, usableW as Number) as Void {
        var suffix = mIsWide ? (INLINE_SEP + mAvgPrefix) : "";
        var longText = mLabelLong + suffix;
        var shortText = mLabelShort + suffix;
        mLabelFont = Graphics.FONT_GLANCE;
        if (dc.getTextWidthInPixels(longText, mLabelFont) <= usableW) {
            mLabelText = longText;
            return;
        }
        mLabelText = shortText;
        if (dc.getTextWidthInPixels(shortText, mLabelFont) <= usableW) {
            return;
        }
        for (var i = 0; i < mTextLadder.size(); i++) {
            var f = mTextLadder[i];
            if (dc.getTextWidthInPixels(shortText, f) <= usableW) {
                mLabelFont = f;
                return;
            }
        }
        mLabelFont = Graphics.FONT_XTINY;
    }

    // Does a number font's painted part fit a band? Gate on the ASCENT, not the full height: the
    // descent a number font reserves is never painted by digits (BAND_SLACK note above).
    private function fitsBand(f as Graphics.FontType, bandH as Number) as Boolean {
        return Graphics.getFontAscent(f) <= bandH - BAND_SLACK;
    }

    // Index in mTextLadder of the largest text font small enough to be the unit of `valueFont`
    // (native ratio UNIT_NUM/UNIT_DEN of the number's ascent). Falls back to the smallest font.
    private function unitFontIndexFor(valueFont as Graphics.FontType) as Number {
        var maxAsc = (Graphics.getFontAscent(valueFont) * UNIT_NUM) / UNIT_DEN;
        for (var i = 0; i < mTextLadder.size(); i++) {
            if (Graphics.getFontAscent(mTextLadder[i]) <= maxAsc) {
                return i;
            }
        }
        return mTextLadder.size() - 1;
    }

    // Largest unit font -- starting at the proportional size and shrinking at most
    // UNIT_SHRINK_STEPS ladder steps -- for which [lead + template + gap + unit block] fits usableW;
    // null if none does (the caller then tries a smaller NUMBER font). Shrinking the unit before the
    // number is deliberate: the number is the data, the unit is a hint. withPrefix also reserves the
    // "AVG" prefix, which is drawn in the same font as the unit (secondary line).
    private function fitUnitFont(dc as Graphics.Dc, valueFont as Graphics.FontType, tpl as String,
                                 lead as Number, usableW as Number,
                                 withPrefix as Boolean) as Graphics.FontType or Null {
        var start = unitFontIndexFor(valueFont);
        var last = start + UNIT_SHRINK_STEPS;
        if (last > mTextLadder.size() - 1) { last = mTextLadder.size() - 1; }
        var valueW = dc.getTextWidthInPixels(tpl, valueFont);
        for (var i = start; i <= last; i++) {
            var u = mTextLadder[i];
            var groupW = lead + valueW + UNIT_GAP + unitBlockWidth(dc, u);
            if (withPrefix) {
                groupW += dc.getTextWidthInPixels(mAvgPrefix, u) + AVG_LABEL_GAP;
            }
            if (groupW <= usableW) {
                return u;
            }
        }
        return null;
    }

    // --- Wide-mode font: largest whose [arrow + gap + "88.8 / 88.8" + gap + unit] fits; else drop
    //     the arrow. One stacked unit follows the whole "cur / avg" pair.
    private function selectInlineFont(dc as Graphics.Dc, usableW as Number) as Void {
        mInlineFont = Graphics.FONT_XTINY;
        mInlineUnitFont = Graphics.FONT_XTINY;
        mInlineArrowFits = false;
        for (var i = 0; i < mLadder.size(); i++) {
            var f = mLadder[i];
            if (!fitsBand(f, mPrimaryBandH)) { continue; }
            var ah = (Graphics.getFontAscent(f) * 4) / 5;
            var aw = (ah * 3) / 5;
            var u = fitUnitFont(dc, f, INLINE_TPL, aw + ARROW_GAP, usableW, false);
            if (u != null) {
                mInlineFont = f;
                mInlineUnitFont = u;
                mInlineArrowFits = true;
                break;
            }
        }
        if (!mInlineArrowFits) {
            // Arrow fits at no size -> graceful fallback: fit the [pair + unit] alone.
            for (var i = 0; i < mLadder.size(); i++) {
                var f = mLadder[i];
                if (!fitsBand(f, mPrimaryBandH)) { continue; }
                var u = fitUnitFont(dc, f, INLINE_TPL, 0, usableW, false);
                if (u != null) {
                    mInlineFont = f;
                    mInlineUnitFont = u;
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
        //var speedsKmh = [10.4, 10.2, 10.4, 10.4, 10.4, 10.4, 10.6, 10.3];
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
            + " unitF a=" + Graphics.getFontAscent(mUnitFont)
            + " unitBlockW=" + unitBlockWidth(dc, mUnitFont)
            + " avgF h=" + dc.getFontHeight(mAvgFont)
            + " label=\"" + mLabelText + "\" labelF a=" + Graphics.getFontAscent(mLabelFont)
            + " labelH=" + mLabelH + " showAvg=" + mShowAvg + " wide=" + mIsWide
            + " arrowFits=" + mArrowFits
            // The wide (inline) path uses its OWN fonts; the fields above are untouched there.
            + " | inlineF h/a=" + dc.getFontHeight(mInlineFont) + "/" + Graphics.getFontAscent(mInlineFont)
            + " inlineUnitF a=" + Graphics.getFontAscent(mInlineUnitFont)
            + " inlineArrowFits=" + mInlineArrowFits);
    }

    // Release stub: never called (DEBUG_MEASURE is const false -> the call site is eliminated).
    (:release)
    private function debugMeasure(dc as Graphics.Dc, w as Number, h as Number) as Void {
    }
}
