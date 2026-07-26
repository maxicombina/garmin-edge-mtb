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
    // Text font to draw the arrow GLYPH with, or null for the drawn primitive. Resolved ONCE here
    // (probing it costs text measurements) and never per tick -- same rule as every other font in
    // this class: measure in selectFonts, draw in onUpdate.
    private var mGlyphFont as Graphics.FontType or Null = null;
    // --- EXPERIMENTAL wide-cell (inline both-values) state ---
    private var mIsWide as Boolean = false;                 // full-width cell -> inline "cur / avg"
    private var mInlineFont as Graphics.FontType = Graphics.FONT_MEDIUM;
    private var mInlineUnitFont as Graphics.FontType = Graphics.FONT_XTINY;
    private var mInlineArrowFits as Boolean = false;        // did [arrow + gap + pair] fit?
    private var mInlineGlyphFont as Graphics.FontType or Null = null;

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

    // --- Trend arrow as a FONT GLYPH, with fallback to the drawn primitive (SPEC 6.6 / 11.2).
    //     Turn off to force the primitive everywhere. Availability is probed per device at runtime
    //     in arrowGlyphFor(); the fallback IS the previous behaviour, so a device that cannot draw
    //     the glyph loses nothing.
    private const USE_ARROW_GLYPH = true;
    private const ARROW_GLYPH_UP = "\u2191";     // line arrow up. Swap for "\u25B2" to get a
    private const ARROW_GLYPH_DOWN = "\u2193";   // line arrow down.       solid triangle instead
    private const GLYPH_CONTROL = "\uE000";      // private-use code point: no font can legitimately
                                                 // have it, so it is the "notdef" reference width
    private const GLYPH_MIN_W = 2;               // px: below this the glyph is effectively absent
    // Own ladder for the glyph: the TEXT fonts, largest first. FONT_LARGE is not in mTextLadder
    // (nothing else needs it) but it is the biggest text font, so it is the arrow's ceiling.
    private var mGlyphLadder as Array<Graphics.FontType> = [];

    // --- Glyph probe (SPEC 11.2). Flip to true + DEBUG build to replace the whole field with a
    //     gallery that answers, ON THE REAL DEVICE, whether the arrow could be a font glyph
    //     instead of the drawn primitive. It is SELF-DIAGNOSING: row 2 and the first item of row 3
    //     are CONTROLS whose expected result is "nothing is painted", so the probe also tells you
    //     whether the runtime is silently substituting fonts (which would make any glyph test in
    //     the simulator a false positive). Read the rows as:
    //       1. TEXT font, "^ v UP DOWN" glyphs   -> present in the edge840 font family
    //       2. NUMBER font, same glyphs + "8"    -> CONTROL: per the font tables they do NOT exist
    //          there; the "8" only proves the row was drawn. Arrows here == font substitution.
    //       3. TEXT font, U+2B06 + the two PRIMITIVES -> U+2B06 is absent even from the edge840
    //          TTF, so it is the "missing glyph" control: whatever it paints is what a missing
    //          glyph looks like on this device. Next to it, today's primitives, to compare shape.
    //     Glyphs are written as \u escapes on purpose: keeps the source pure ASCII (no editor or
    //     tooling can re-encode them) and it is verified to compile and reach the runtime as the
    //     right code point.
    private const GLYPH_PROBE = false;
    (:debug) private const G_UP = "\u2191";      // arrow up
    (:debug) private const G_DOWN = "\u2193";    // arrow down
    (:debug) private const G_TRI_UP = "\u25B2";  // black up-pointing triangle
    (:debug) private const G_TRI_DN = "\u25BC";  // black down-pointing triangle
    (:debug) private const G_ABSENT = "\u2B06";  // CONTROL: absent from every Edge font table

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

        mGlyphLadder = [
            Graphics.FONT_LARGE,
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

        if (GLYPH_PROBE) {
            // (:debug)-only body; the const-false guard drops it (and the call) in release.
            glyphProbe(dc, w, h, fg);
            return;
        }

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
            drawTrendValue(dc, w, fg, mInlineFont, mInlineUnitFont, mInlineGlyphFont, mBothStr, cyW,
                           mInlineArrowFits);
            return;
        }

        // --- Current value + arrow + native stacked unit, centred in the primary band ---
        var primaryCy = mLabelH + mPrimaryBandH / 2 + Graphics.getFontDescent(mValueFont) / 2 - VALUE_NUDGE;
        drawTrendValue(dc, w, fg, mValueFont, mUnitFont, mGlyphFont, mCurStr, primaryCy, mArrowFits);

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
                                    glyphFont as Graphics.FontType or Null,
                                    valueStr as String, cy as Number,
                                    reserveArrow as Boolean) as Void {
        // (CIQ 3.3 caps a method at 9 arguments -- the edge830 build enforces it, the edge840 one
        // does not. Hence "paint" is derived here from members instead of being a 10th parameter.)
        var paintArrow = reserveArrow && (mArrowState != TrendArrow.NONE) && !mCurStr.equals("--");
        var vW = dc.getTextWidthInPixels(valueStr, valueFont);
        var uW = unitBlockWidth(dc, unitFont);
        // The arrow's slot is reserved whenever an arrow COULD be drawn here, not only when one is
        // being drawn right now. Otherwise the group shrinks on the ticks with no arrow and, since
        // it is centred, the number visibly jumps sideways every time the speed crosses the average
        // -- which is constantly. Reserving keeps the number nailed in place (SPEC 6.11).
        var aH = reserveArrow ? (Graphics.getFontAscent(valueFont) * 4) / 5 : 0;
        var gf = reserveArrow ? glyphFont : null;   // resolved in selectFonts; null -> primitive
        var glyph = (mArrowState == TrendArrow.UP) ? ARROW_GLYPH_UP : ARROW_GLYPH_DOWN;
        var aW = 0;
        if (reserveArrow) {
            // Reserve the WIDER of the two states so up and down never shift the number either.
            if (gf != null) {
                var wu = dc.getTextWidthInPixels(ARROW_GLYPH_UP, gf);
                var wd = dc.getTextWidthInPixels(ARROW_GLYPH_DOWN, gf);
                aW = (wu > wd) ? wu : wd;
            } else {
                aW = (aH * 3) / 5;
            }
        }
        var lead = reserveArrow ? (aW + ARROW_GAP) : 0;
        var totalW = lead + vW + UNIT_GAP + uW;
        var x = w / 2 - totalW / 2;
        var vx = x + lead;
        dc.setColor(fg, Graphics.COLOR_TRANSPARENT);
        if (paintArrow) {
            // Both routes centre on the value's VISIBLE glyphs: the value is VCENTREd on a box
            // whose descent the digits never use, so shift up by descent/2, then B's fine nudge.
            var arrowCy = cy - Graphics.getFontDescent(valueFont) / 2 + ARROW_NUDGE;
            if (gf != null) {
                dc.drawText(x + aW / 2, arrowCy, gf, glyph,
                            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
            } else {
                if (mArrowState == TrendArrow.UP) {
                    drawUpArrow(dc, x, arrowCy, aW, aH);
                } else {
                    drawDownArrow(dc, x, arrowCy, aW, aH);
                }
            }
        }
        dc.drawText(vx, cy, valueFont, valueStr, Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
        // Unit is baseline-aligned to the number's baseline (native look: the "h" sits on the same
        // line as the digits' feet). numberBaseline for a VCENTREd value = cy + (ascent - descent)/2.
        var baseY = cy + (Graphics.getFontAscent(valueFont) - Graphics.getFontDescent(valueFont)) / 2 + UNIT_BOTTOM_NUDGE;
        drawStackedUnit(dc, vx + vW + UNIT_GAP, baseY, unitFont);
    }

    // Width to RESERVE for the arrow when choosing a value font: the primitive's, or the glyph's if
    // this device resolves it and it happens to be wider. Reserving the max means the group can
    // never overflow the cell whichever of the two ends up being drawn.
    private function arrowLeadWidth(dc as Graphics.Dc, valueFont as Graphics.FontType,
                                    primitiveW as Number) as Number {
        var gf = arrowGlyphFont(dc, (Graphics.getFontAscent(valueFont) * 4) / 5);
        if (gf == null) {
            return primitiveW;
        }
        var up = dc.getTextWidthInPixels(ARROW_GLYPH_UP, gf);
        var dn = dc.getTextWidthInPixels(ARROW_GLYPH_DOWN, gf);
        var g = (up > dn) ? up : dn;
        return (g > primitiveW) ? g : primitiveW;
    }

    // The TEXT font to draw the trend arrow glyph with, or null to fall back to the drawn
    // primitive. `targetAscent` is how tall the primitive would have been, so the glyph never
    // comes out bigger than what it replaces.
    //
    // WHY A TEXT FONT AND NOT THE VALUE'S OWN (NUMBER) FONT -- measured, 2026-07-25 (SPEC 11.2):
    // asking a number font for the glyph is a trap. On an edge840 `getTextWidthInPixels("↑",
    // FONT_SYSTEM_NUMBER_MEDIUM)` returns **0** and yet the device DOES paint an arrow there (26 px
    // tall, seen in a real-hardware capture) -- measurement and renderer disagree, so there is no
    // width to lay out around. In a TEXT font the two agree (11 px measured, 11 px drawn), which is
    // the only way the group can be positioned correctly. The cost is the ceiling: FONT_LARGE.
    //
    // AVAILABILITY IS MEASURED ON THE DEVICE, never assumed from a font table and never from a
    // device list -- the tables do not predict what the runtime draws and the simulator is wrong in
    // both directions (SPEC 11.2). Two signals, both must pass:
    //   1. the glyph advances more than a couple of pixels -- on the edge830 family, whose text
    //      font is a trimmed bitmap, a missing arrow measures exactly 1 px;
    //   2. it does not measure the same as a private-use code point that no font can have -- on
    //      that same family a number font reports 22 px for BOTH, i.e. one shared "notdef" box.
    // Either failing means the primitive, i.e. exactly the previous behaviour.
    private function arrowGlyphFont(dc as Graphics.Dc, targetAscent as Number) as Graphics.FontType or Null {
        if (!USE_ARROW_GLYPH) {
            return null;
        }
        for (var i = 0; i < mGlyphLadder.size(); i++) {
            var f = mGlyphLadder[i];
            if (Graphics.getFontAscent(f) > targetAscent) {
                continue;
            }
            var wUp = dc.getTextWidthInPixels(ARROW_GLYPH_UP, f);
            if (wUp <= GLYPH_MIN_W || wUp == dc.getTextWidthInPixels(GLYPH_CONTROL, f)) {
                return null;   // same font file at every size: if this one lacks it, all do
            }
            return f;
        }
        return null;
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
            var aw = arrowLeadWidth(dc, f, (ah * 3) / 5);
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

        // Arrow glyph availability: probed once here, cached with the rest of the layout.
        mGlyphFont = arrowGlyphFont(dc, (Graphics.getFontAscent(mValueFont) * 4) / 5);

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
            var aw = arrowLeadWidth(dc, f, (ah * 3) / 5);
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
        mInlineGlyphFont = arrowGlyphFont(dc, (Graphics.getFontAscent(mInlineFont) * 4) / 5);
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
        // Profile built to exercise the ARROW, not just the number. Symmetric around 20.0 km/h
        // (the eight values average exactly 20.0), so the running average converges there and the
        // cycle then visits the three states on purpose: clearly above (UP), clearly below (DOWN)
        // and AT the average (NO arrow -- the dead band), including the +/-0.1 edges where
        // DEAD_BAND_TENTHS decides. The no-arrow <-> arrow transitions are what reveals whether
        // the number stays put when the arrow comes and goes (SPEC 6.11).
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

    // Glyph gallery -- see the GLYPH_PROBE note above for how to read the three rows.
    (:debug)
    private function glyphProbe(dc as Graphics.Dc, w as Number, h as Number, fg as Graphics.ColorType) as Void {
        // One text font for rows 1 and 3, sized so three rows fit; one number font for row 2.
        var tf = Graphics.FONT_XTINY;
        for (var i = 0; i < mTextLadder.size(); i++) {
            if (dc.getFontHeight(mTextLadder[i]) <= h / 3) { tf = mTextLadder[i]; break; }
        }
        var nf = Graphics.FONT_SYSTEM_NUMBER_MILD;
        if (dc.getFontHeight(nf) > h / 3) { nf = Graphics.FONT_MEDIUM; }
        var y1 = h / 6;
        var y2 = h / 2;
        var y3 = (h * 5) / 6;
        dc.setColor(fg, Graphics.COLOR_TRANSPARENT);
        var C = Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER;
        // Row 1 -- the candidates, in a TEXT font.
        dc.drawText(w / 2, y1, tf, G_UP + G_DOWN + G_TRI_UP + G_TRI_DN, C);
        // Row 2 -- CONTROL: same candidates in a NUMBER font (they should NOT paint); the "8" only
        // proves the row ran. Anything arrow-shaped here means the runtime substituted a font.
        dc.drawText(w / 2, y2, nf, G_UP + G_TRI_UP + "8", C);
        // Row 3 -- CONTROL: a code point absent from every Edge font, then today's primitives.
        var aH = (Graphics.getFontAscent(tf) * 4) / 5;
        var aW = (aH * 3) / 5;
        var gW = dc.getTextWidthInPixels(G_ABSENT, tf);
        var total = gW + 8 + aW + 8 + aW;
        var x = w / 2 - total / 2;
        dc.drawText(x, y3, tf, G_ABSENT, Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
        drawUpArrow(dc, x + gW + 8, y3, aW, aH);
        drawDownArrow(dc, x + gW + 8 + aW + 8, y3, aW, aH);
    }

    // Release stub: never called (GLYPH_PROBE is const false -> the call site is eliminated).
    (:release)
    private function glyphProbe(dc as Graphics.Dc, w as Number, h as Number, fg as Graphics.ColorType) as Void {
    }

    // "GLYPH(w=N)" or "PRIMITIVE(w=N)" for the debug log -- same decision the drawing takes.
    (:debug)
    private function arrowRouteLabel(dc as Graphics.Dc, valueFont as Graphics.FontType) as String {
        var aH = (Graphics.getFontAscent(valueFont) * 4) / 5;
        var gf = arrowGlyphFont(dc, aH);
        if (gf == null) {
            return "PRIMITIVE(w=" + ((aH * 3) / 5) + " h=" + aH + ")";
        }
        return "GLYPH(w=" + dc.getTextWidthInPixels(ARROW_GLYPH_UP, gf)
               + " ascent=" + Graphics.getFontAscent(gf) + " vs primitive h=" + aH + ")";
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
            // Which arrow route this cell resolved to, so the simulator console answers
            // "glyph or primitive?" without having to judge it by eye.
            + " ARROW=" + arrowRouteLabel(dc, mValueFont)
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
