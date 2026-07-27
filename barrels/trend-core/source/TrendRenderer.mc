import Toybox.WatchUi;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;

//
// The shared render engine of the trend-arrow family: draws "[arrow] value [stacked unit]" big, with
// an optional secondary reference line below, adapting to the cell it is given.
//
// EXTRACTED VERBATIM from Option J's view (2026-07-27), which had been tuned pixel by pixel against
// the Edge's native speed field. Everything here was measured, not guessed, and the comments say
// against what -- do not "simplify" a constant without re-measuring. What the app supplies is only
// the metric-specific part: the strings to draw, the width-stable template, and the unit.
//
// SPLIT OF RESPONSIBILITIES
//   The app's View  ->  reads Activity.Info, formats the display strings, owns settings and TEST_MODE.
//   This Renderer   ->  measures the cell, picks fonts, draws. Knows nothing about any metric.
//
// USAGE (see any consuming app's View)
//   initialize()                              once
//   setLabels(long, short, refPrefix)         once (or when settings change the prefix)
//   setTemplates(valueTpl, inlineTpl)         once -- WIDTH-STABLE templates, see note below
//   setUnit(top, bottom)                      every tick is fine; it self-invalidates on change
//   setValues(cur, ref, arrowState, running)  every tick
//   draw(dc, backgroundColor)                 from onUpdate
//
// WIDTH-STABLE TEMPLATES. Fonts are chosen by measuring a template of all-8 digits, never the live
// value: measuring the live text would let one value fit and the next not, and the layout would jump
// every second. The template must be an upper bound on every value the metric can ever produce.
//
module TrendCore {

    // Separator between the current and reference values in the wide inline layout. Apps need it to
    // build their inline template, so it lives here rather than inside the class.
    const INLINE_SEP = " / ";
    // What a metric with no data shows. The arrow is suppressed on it: no data is not a trend.
    const NO_DATA = "--";

    class TrendRenderer {

        // --- Layout tunables. Calibrated in the simulator across the 6 resolutions of the 13 devices. ---
        private const PAD = 3;               // horizontal padding per side, px
        private const LABEL_MARGIN = 4;      // px above the label
        private const LABEL_MIN_H = 60;      // >= this: draw the label (inherited from Option A, validated)
        private const AVG_MIN_H = 110;       // >= this: draw the secondary reference line
        private const AVG_BAND_PCT = 35;     // % of the post-label height reserved to the reference line
        private const ARROW_GAP = 4;         // px between the arrow and the value
        private const AVG_LABEL_GAP = 4;     // px between the "AVG"/"PROM" prefix and the reference number
        // Native-style unit: a small "km/h" drawn to the right of the number as "km" over "h", the two
        // lines CENTRED on each other and the bottom line's baseline on the digits' baseline -- measured
        // off the native VELOCIDAD field (2026-07-25, edge840 sim @246x322: digits ink 27px tall, unit
        // ink 11px per line, unit baselines 14px apart, "h" centred under "km"). NOT baked into the label.
        private const UNIT_GAP = 3;          // px between the number and the stacked unit block
        private const UNIT_LINE_GAP = 2;     // px added to the unit ascent to space the two stacked lines
        private const UNIT_BOTTOM_NUDGE = 0; // px: fine vertical tweak of the unit (positive pushes DOWN)
        // Unit size is PROPORTIONAL to the number (native ratio: ascent 12 of a 33 number ascent ~ 2/5),
        // not a fixed FONT_XTINY -- that was what made our unit look like a speck next to the native one.
        private const UNIT_NUM = 2;          // unit ascent <= number ascent * UNIT_NUM / UNIT_DEN
        private const UNIT_DEN = 5;
        private const UNIT_SHRINK_STEPS = 2; // width-bound cells may shrink the unit this many ladder
                                             // steps below proportional before the NUMBER gives up a size
        // Vertical-centering trick (master spec 3.4): number fonts reserve descent the digits don't use
        // -> center then push DOWN by descent/2; VALUE_NUDGE is Option A's fine 2px-up tweak.
        private const VALUE_NUDGE = 2;       // px: raise the value a touch after the descent/2 drop
        // (There is deliberately no vertical nudge constant for the arrow: it is anchored to the number's
        // BASELINE, computed from the font. See drawTrendValue -- every constant tried here was a guess at
        // where the digits' ink sits, and each one was wrong on some device or cell size. SPEC 6.13.)
        // The SAME descent-is-unused fact also decides which number font fits a band: gate on the font's
        // ASCENT, not its full height. A number font's height includes a descent the digits never use, so
        // a "height <= 90% of the band" gate drops a whole size for nothing -- that is why our number
        // once came out smaller than the native one in the same cell (the native fits a 42px-tall font
        // in a 41px band because only its 33px ascent is ever painted). BAND_SLACK is the safety margin.
        private const BAND_SLACK = 2;        // px kept free between the number's ascent and the band
        // Wide-cell mode: a full-width field (w >= 80% of the device screen width) that is ALSO SHORT (no
        // room to stack) shows BOTH values inline on one line as "[arrow] cur / ref". A full-width field
        // that is TALL falls through to the stacked layout instead -- a one-line inline can only grow as
        // wide as the cell, so a tall wide cell gets a much bigger number when stacked.
        private const WIDE_NUM = 8;          // wide iff w * WIDE_DEN >= screenWidth * WIDE_NUM ...
        private const WIDE_DEN = 10;         // ... i.e. cell width >= 80% of the screen width

        // --- Arrow glyph. The trend arrow is drawn as a FONT GLYPH on devices that have one and as
        //     drawn primitives everywhere else, decided by measuring on the device itself (see
        //     arrowGlyphFont). Set USE_ARROW_GLYPH to false to force the primitive everywhere. ---
        private const USE_ARROW_GLYPH = true;
        private const ARROW_GLYPH_UP   = "\u2191";  // line arrow up;   "\u25B2" for a solid triangle
        private const ARROW_GLYPH_DOWN = "\u2193";  // line arrow down; "\u25BC" for a solid triangle
        private const GLYPH_CONTROL = "\uE000";     // private-use point: no font can legitimately have it
        private const GLYPH_MIN_W = 2;               // a missing glyph measures 1px in the bitmap family

        // Number-font ladder, largest -> smallest. System number fonts first, like A/B.
        private var mLadder as Array<Graphics.FontType> = [];
        // Text-font ladder, largest -> smallest: used for the stacked unit, the reference prefix and the
        // label fallback (a proportional unit needs to walk sizes, so it cannot be a fixed font).
        private var mTextLadder as Array<Graphics.FontType> = [];
        // Fonts the arrow glyph may be drawn in. Text fonts only, and FONT_LARGE is the ceiling -- see
        // arrowGlyphFont for why the value's own number font cannot be used.
        private var mGlyphLadder as Array<Graphics.FontType> = [];

        // --- Config supplied by the app ---
        private var mLabelLong as String = "";
        private var mLabelShort as String = "";
        private var mRefPrefix as String = "";
        private var mValueTpl as String = "888";
        private var mInlineTpl as String = "888 / 888";
        private var mUnitTop as String = "";
        private var mUnitBottom as String = "";

        // --- Live display state, refreshed every tick by setValues ---
        private var mCurStr as String = $.TrendCore.NO_DATA;
        private var mRefStr as String = $.TrendCore.NO_DATA;
        private var mBothStr as String = $.TrendCore.NO_DATA + $.TrendCore.INLINE_SEP + $.TrendCore.NO_DATA;
        private var mArrowState as Number = 0;   // TrendArrow.UP / NONE / DOWN
        private var mRunning as Boolean = false;

        // --- Layout cache: re-run selectFonts only when the cell size or the configuration changes. ---
        private var mCacheW as Number = -1;
        private var mCacheH as Number = -1;
        private var mLabelH as Number = 0;            // 0 if the label is not shown
        private var mLabelText as String = "";        // long or short name, whichever fits (see selectLabel)
        private var mLabelFont as Graphics.FontType = Graphics.FONT_GLANCE;
        private var mShowRef as Boolean = false;
        private var mPrimaryBandH as Number = 0;      // height of the current-value band (below the label)
        private var mRefBandH as Number = 0;          // height of the reference band (below the primary band)
        private var mValueFont as Graphics.FontType = Graphics.FONT_MEDIUM;
        private var mUnitFont as Graphics.FontType = Graphics.FONT_XTINY;      // unit next to the value
        private var mRefFont as Graphics.FontType = Graphics.FONT_XTINY;
        private var mRefUnitFont as Graphics.FontType = Graphics.FONT_XTINY;   // unit + prefix of the ref line
        private var mArrowFits as Boolean = false;    // did [arrow + gap + value] fit at the chosen font?
        // Text font to draw the arrow GLYPH with, or null for the drawn primitive. Resolved ONCE here
        // (probing it costs text measurements) and never per tick -- the rule for every font in this
        // class: measure in selectFonts, draw in draw(). Getting this wrong once cost a per-tick probe.
        private var mGlyphFont as Graphics.FontType or Null = null;
        // --- Wide-cell (inline both-values) state ---
        private var mIsWide as Boolean = false;
        private var mInlineFont as Graphics.FontType = Graphics.FONT_MEDIUM;
        private var mInlineUnitFont as Graphics.FontType = Graphics.FONT_XTINY;
        private var mInlineArrowFits as Boolean = false;
        private var mInlineGlyphFont as Graphics.FontType or Null = null;

        function initialize() {
            // Number fonts first (designed for field values, legible with gloves), then text fonts so a
            // tiny cell still gets something. Largest -> smallest; selection walks this in order.
            mLadder = [
                Graphics.FONT_SYSTEM_NUMBER_THAI_HOT,
                Graphics.FONT_SYSTEM_NUMBER_HOT,
                Graphics.FONT_SYSTEM_NUMBER_MEDIUM,
                Graphics.FONT_SYSTEM_NUMBER_MILD,
                Graphics.FONT_LARGE,
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
        }

        // --- Configuration. Each of these invalidates the layout cache, because every one of them
        //     changes a measured width. Call them from initialize()/onSettingsChanged, not per tick. ---

        // Metric name, long and short. The long one is drawn when it fits (like the native field), else
        // the short one. refPrefix labels the secondary line ("AVG" / "PROM" / "GOAL" / "META").
        function setLabels(labelLong as String, labelShort as String, refPrefix as String) as Void {
            mLabelLong = labelLong;
            mLabelShort = labelShort;
            mRefPrefix = refPrefix;
            invalidate();
        }

        // Width-stable all-8 templates: one for the single value, one for the inline "cur / ref" pair.
        function setTemplates(valueTpl as String, inlineTpl as String) as Void {
            mValueTpl = valueTpl;
            mInlineTpl = inlineTpl;
            invalidate();
        }

        // The native stacked unit: two lines ("km" over "h") or one (bottom empty, e.g. "rpm", "mph").
        // Cheap to call every tick: it only invalidates when the strings actually change, which matters
        // because a device units change does NOT fire onSettingsChanged and must be picked up live.
        function setUnit(top as String, bottom as String) as Void {
            if (!mUnitTop.equals(top) || !mUnitBottom.equals(bottom)) {
                mUnitTop = top;
                mUnitBottom = bottom;
                invalidate();
            }
        }

        function invalidate() as Void {
            mCacheW = -1;
        }

        // --- Per-tick state. No measuring here: this only stores strings. ---
        function setValues(curStr as String, refStr as String, arrowState as Number, running as Boolean) as Void {
            mCurStr = curStr;
            mRefStr = refStr;
            mBothStr = curStr + $.TrendCore.INLINE_SEP + refStr;
            mArrowState = arrowState;
            mRunning = running;
        }

        // Was the inline (wide-cell) layout chosen for the current cell? Only meaningful after a draw;
        // exposed so an app's debug hook can report which branch it took.
        function isWide() as Boolean {
            return mIsWide;
        }

        // Every layout decision this engine took for the current cell, as one line. Call it AFTER draw().
        // It exists so a consumer's DEBUG_MEASURE hook keeps working now that the engine is not in the
        // view any more, and so the headless layout check still reports what the code CHOSE rather than a
        // re-derivation by hand (that check is the only way to verify font selection without the GUI:
        // Monkey C has no getPixel, so pixels still need the author's eye).
        //
        // Public and un-annotated on purpose: a barrel cannot rely on the consumer's (:debug) exclusions,
        // and nothing is built unless someone calls this.
        function debugSummary(dc as Graphics.Dc) as String {
            return "valueF h/a/d=" + dc.getFontHeight(mValueFont) + "/"
                       + Graphics.getFontAscent(mValueFont) + "/" + Graphics.getFontDescent(mValueFont)
                 + " unitF a=" + Graphics.getFontAscent(mUnitFont)
                 + " unitBlockW=" + unitBlockWidth(dc, mUnitFont)
                 + " refF h=" + dc.getFontHeight(mRefFont)
                 + " label=\"" + mLabelText + "\" labelF a=" + Graphics.getFontAscent(mLabelFont)
                 + " labelH=" + mLabelH + " showRef=" + mShowRef + " wide=" + mIsWide
                 + " arrowFits=" + mArrowFits
                 // Which arrow route this cell resolved to, so the console answers "glyph or primitive?"
                 // without anyone judging it by eye -- the two differ by font FAMILY, not by resolution.
                 + " ARROW=" + arrowRouteLabel(dc, mValueFont)
                 // The wide (inline) path uses its OWN fonts; the fields above are untouched there.
                 + " | inlineF h/a=" + dc.getFontHeight(mInlineFont) + "/" + Graphics.getFontAscent(mInlineFont)
                 + " inlineUnitF a=" + Graphics.getFontAscent(mInlineUnitFont)
                 + " inlineArrowFits=" + mInlineArrowFits;
        }

        private function arrowRouteLabel(dc as Graphics.Dc, valueFont as Graphics.FontType) as String {
            var aH = (Graphics.getFontAscent(valueFont) * 4) / 5;
            var gf = arrowGlyphFont(dc, aH);
            if (gf == null) {
                return "PRIMITIVE(w=" + ((aH * 3) / 5) + " h=" + aH + ")";
            }
            return "GLYPH(w=" + dc.getTextWidthInPixels(ARROW_GLYPH_UP, gf)
                   + " ascent=" + Graphics.getFontAscent(gf) + " vs primitive h=" + aH + ")";
        }

        // --- The draw entry point. `bg` is the app's getBackgroundColor(): a DataField method, so the
        //     app has to pass it in. Everything grey when the timer is not running, like A and B. ---
        function draw(dc as Graphics.Dc, bg as Graphics.ColorType) as Void {
            var w = dc.getWidth();
            var h = dc.getHeight();

            var fg = Graphics.COLOR_BLACK;
            if (bg == Graphics.COLOR_BLACK) {
                fg = mRunning ? Graphics.COLOR_WHITE : Graphics.COLOR_LT_GRAY;
            } else {
                fg = mRunning ? Graphics.COLOR_BLACK : Graphics.COLOR_DK_GRAY;
            }
            dc.setColor(fg, bg);
            dc.clear();

            // Font/layout selection is cached; re-run only when the cell size or the config changes.
            if (w != mCacheW || h != mCacheH) {
                selectFonts(dc, w, h);
                mCacheW = w;
                mCacheH = h;
            }

            // Label = metric NAME only (the unit is drawn next to the number, native style). The text and
            // its font were picked in selectFonts: long name if it fits, else short, else shrunk.
            if (mLabelH > 0) {
                dc.setColor(fg, Graphics.COLOR_TRANSPARENT);
                dc.drawText(w / 2, LABEL_MARGIN, mLabelFont, mLabelText, Graphics.TEXT_JUSTIFY_CENTER);
            }

            // Wide (full-width, short) cell: both values inline on one line, "[arrow] cur / ref [unit]".
            if (mIsWide) {
                var cyW = mLabelH + mPrimaryBandH / 2 + Graphics.getFontDescent(mInlineFont) / 2 - VALUE_NUDGE;
                drawTrendValue(dc, w, fg, mInlineFont, mInlineUnitFont, mInlineGlyphFont, mBothStr, cyW,
                               mInlineArrowFits);
                return;
            }

            // --- Current value + arrow + native stacked unit, centred in the primary band ---
            var primaryCy = mLabelH + mPrimaryBandH / 2 + Graphics.getFontDescent(mValueFont) / 2 - VALUE_NUDGE;
            drawTrendValue(dc, w, fg, mValueFont, mUnitFont, mGlyphFont, mCurStr, primaryCy, mArrowFits);

            // --- Reference line (only if the cell is tall enough): "AVG 21.7 [unit]" ---
            if (mShowRef) {
                var refCy = mLabelH + mPrimaryBandH + mRefBandH / 2 + Graphics.getFontDescent(mRefFont) / 2 - VALUE_NUDGE;
                var wRef = dc.getTextWidthInPixels(mRefStr, mRefFont);
                var prefixW = dc.getTextWidthInPixels(mRefPrefix, mRefUnitFont);
                var uW = unitBlockWidth(dc, mRefUnitFont);
                var totalRefW = prefixW + AVG_LABEL_GAP + wRef + UNIT_GAP + uW;
                var ax = w / 2 - totalRefW / 2;
                dc.setColor(fg, Graphics.COLOR_TRANSPARENT);
                dc.drawText(ax, refCy, mRefUnitFont, mRefPrefix,
                            Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
                var numX = ax + prefixW + AVG_LABEL_GAP;
                dc.drawText(numX, refCy, mRefFont, mRefStr,
                            Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
                var refBaseY = refCy + (Graphics.getFontAscent(mRefFont) - Graphics.getFontDescent(mRefFont)) / 2 + UNIT_BOTTOM_NUDGE;
                drawStackedUnit(dc, numX + wRef + UNIT_GAP, refBaseY, mRefUnitFont);
            }
        }

        // Draws "[arrow] value [stacked unit]" as one horizontally-centred group, the value VCENTREd on
        // cy. Used by both the stacked primary line and the wide inline line (value = "cur / ref" there).
        private function drawTrendValue(dc as Graphics.Dc, w as Number, fg as Graphics.ColorType,
                                        valueFont as Graphics.FontType, unitFont as Graphics.FontType,
                                        glyphFont as Graphics.FontType or Null,
                                        valueStr as String, cy as Number,
                                        reserveArrow as Boolean) as Void {
            // (CIQ 3.3 caps a method at 9 arguments -- the edge830 build enforces it, the edge840 one
            // does not. Hence "paint" is derived here from members instead of being a 10th parameter.)
            var paintArrow = reserveArrow && (mArrowState != TrendArrow.NONE) && !mCurStr.equals($.TrendCore.NO_DATA);
            var vW = dc.getTextWidthInPixels(valueStr, valueFont);
            var uW = unitBlockWidth(dc, unitFont);
            // The arrow's slot is reserved whenever an arrow COULD be drawn here, not only when one is
            // being drawn right now. Otherwise the group shrinks on the ticks with no arrow and, since
            // it is centred, the number visibly jumps sideways every time the value crosses the
            // reference -- which is constantly. Reserving keeps the number nailed in place.
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
            // The number's BASELINE, and the anchor for everything drawn beside it. For a VCENTREd value
            // that is cy + (ascent - descent)/2, and the digits' feet land exactly on it -- VERIFIED on
            // both font families off the author's screenshots (SPEC 6.13). It is the only anchor that is
            // both queryable and exact: the digits' ink TOP is not, because how much of the ascent the
            // digits fill differs by family (0.79 on the 840's TTF, 0.91 on the 830's bitmap fonts) and
            // no API exposes it. Two earlier attempts at "centre on the ink" therefore had to guess, and
            // both were wrong on one family or one cell size.
            var valueBaseY = cy + (Graphics.getFontAscent(valueFont) - Graphics.getFontDescent(valueFont)) / 2;
            // The arrow lives in a BAND that sits on that baseline: [valueBaseY - aH, valueBaseY], aH being
            // 4/5 of the value's ascent. Anchoring the band (not the drawn shape) is what makes the two
            // routes agree, because they fill it differently -- author's choice, 2026-07-27.
            var arrowCy = valueBaseY - aH / 2;
            if (paintArrow) {
                if (gf != null) {
                    // Glyph: CENTRED IN the band, not sitting on its floor. The glyph is capped at
                    // FONT_LARGE (SPEC 6.12), so in a big cell its ink is half the digits' height (21 vs
                    // 42 px) and resting it on the baseline would read as a subscript. Centring needs
                    // + descent/2 because VCENTER centres the font BOX and the glyph never paints that
                    // box's descent, so its ink would otherwise float up by half of it (SPEC 6.13).
                    dc.drawText(x + aW / 2, arrowCy + Graphics.getFontDescent(gf) / 2, gf, glyph,
                                Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
                } else {
                    // Primitive: FILLS the band -- drawUp/DownArrow centre the shape on the y they are
                    // given, so the band centre puts its bottom exactly on the baseline, the digits' feet.
                    if (mArrowState == TrendArrow.UP) {
                        drawUpArrow(dc, x, arrowCy, aW, aH);
                    } else {
                        drawDownArrow(dc, x, arrowCy, aW, aH);
                    }
                }
            }
            dc.drawText(vx, cy, valueFont, valueStr, Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
            // Unit is baseline-aligned too (native look: the "h" sits on the same line as the digits'
            // feet), with its own nudge so it can be trimmed without moving the arrow.
            drawStackedUnit(dc, vx + vW + UNIT_GAP, valueBaseY + UNIT_BOTTOM_NUDGE, unitFont);
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

        // The TEXT font to draw the trend arrow glyph with, or null to fall back to the drawn primitive.
        // `targetAscent` is how tall the primitive would have been, so the glyph never comes out bigger
        // than what it replaces.
        //
        // WHY A TEXT FONT AND NOT THE VALUE'S OWN (NUMBER) FONT -- measured on hardware, 2026-07-25:
        // asking a number font for the glyph is a trap. On an edge840 `getTextWidthInPixels("↑",
        // FONT_SYSTEM_NUMBER_MEDIUM)` returns **0** and yet the device DOES paint an arrow there (26 px
        // tall, seen in a real-hardware capture) -- measurement and renderer disagree, so there is no
        // width to lay out around. In a TEXT font the two agree, which is the only way the group can be
        // positioned correctly. The cost is the ceiling, FONT_LARGE, which is why the glyph reads
        // smaller than the digits in a large cell (see Option J's SPEC 6.12).
        //
        // AVAILABILITY IS MEASURED ON THE DEVICE, never assumed from a font table and never from a
        // device list -- the tables do not predict what the runtime draws and the simulator is wrong in
        // both directions. Two signals, both must pass:
        //   1. the glyph advances more than a couple of pixels -- on the edge830 family, whose text
        //      font is a trimmed bitmap, a missing arrow measures exactly 1 px;
        //   2. it does not measure the same as a private-use code point that no font can have -- on
        //      that same family a number font reports 22 px for BOTH, i.e. one shared "notdef" box.
        // Either failing means the primitive, i.e. the safe behaviour.
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
        // line (empty bottom, e.g. "rpm") is placed with its own baseline at baseY. drawText's y is the
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

        // --- Font + band selection (measures the width-stable template; cached by draw) --------------
        private function selectFonts(dc as Graphics.Dc, w as Number, h as Number) as Void {
            var usableW = w - 2 * PAD;
            var labelShow = (h >= LABEL_MIN_H);

            // Full-width cell? Compare against the device screen width (screenWidth is always present).
            // Inline "cur / ref" is used ONLY when the cell is also SHORT (h < AVG_MIN_H -> no room to
            // stack a second line). A full-width cell that IS tall falls through to the stacked layout
            // below, where the current value gets a BIG font (bounded by height, not by the long inline
            // string) and the reference sits on its own line.
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
                // One line: no separate stacked reference band.
                mShowRef = false;
                mPrimaryBandH = h - mLabelH;
                mRefBandH = 0;
                selectInlineFont(dc, usableW);
                return;
            }

            mShowRef = (h >= AVG_MIN_H);   // implies labelShow (AVG_MIN_H > LABEL_MIN_H)

            var postLabelH = h - mLabelH;
            if (mShowRef) {
                mPrimaryBandH = (postLabelH * (100 - AVG_BAND_PCT)) / 100;
                mRefBandH = postLabelH - mPrimaryBandH;
            } else {
                mPrimaryBandH = postLabelH;
                mRefBandH = 0;
            }

            // --- Current value font: largest whose ASCENT fits the band (see BAND_SLACK) and whose
            //     [arrow + gap + template + gap + proportional unit] fits the width. ---
            mValueFont = Graphics.FONT_XTINY;
            mUnitFont = Graphics.FONT_XTINY;
            mArrowFits = false;
            for (var i = 0; i < mLadder.size(); i++) {
                var f = mLadder[i];
                if (!fitsBand(f, mPrimaryBandH)) { continue; }
                var ah = (Graphics.getFontAscent(f) * 4) / 5;
                var aw = arrowLeadWidth(dc, f, (ah * 3) / 5);
                var u = fitUnitFont(dc, f, mValueTpl, aw + ARROW_GAP, usableW, false);
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
                    var u = fitUnitFont(dc, f, mValueTpl, 0, usableW, false);
                    if (u != null) {
                        mValueFont = f;
                        mUnitFont = u;
                        break;
                    }
                }
            }

            // Arrow glyph availability: probed once here, cached with the rest of the layout.
            mGlyphFont = arrowGlyphFont(dc, (Graphics.getFontAscent(mValueFont) * 4) / 5);

            // --- Reference font (no arrow; the prefix shares the unit font so the whole secondary line
            //     scales together). ---
            mRefFont = Graphics.FONT_XTINY;
            mRefUnitFont = Graphics.FONT_XTINY;
            if (mShowRef) {
                for (var i = 0; i < mLadder.size(); i++) {
                    var f = mLadder[i];
                    if (!fitsBand(f, mRefBandH)) { continue; }
                    var u = fitUnitFont(dc, f, mValueTpl, 0, usableW, true);
                    if (u != null) {
                        mRefFont = f;
                        mRefUnitFont = u;
                        break;
                    }
                }
            }
        }

        // --- Label: the long metric name if it fits the cell, else the short one, else the short one
        //     shrunk down the text ladder (last resort; may still clip in an absurdly narrow cell).
        //     Wide mode names both columns ("VELOCIDAD / PROM"). Mirrors what the native field does. ---
        private function selectLabel(dc as Graphics.Dc, usableW as Number) as Void {
            var suffix = mIsWide ? ($.TrendCore.INLINE_SEP + mRefPrefix) : "";
            var longText = mLabelLong + suffix;
            var shortText = mLabelShort + suffix;
            mLabelFont = labelBaseFont();
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

        // The BIGGEST font a label may use, decided by MEASURING, not by naming devices.
        //
        // FONT_GLANCE is the right answer on the TTF family (edge840: ascent 15, bigger than FONT_MEDIUM's
        // 14) -- but the bitmap family HAS NO GLANCE FONT and silently resolves it to the smallest text
        // font there is: on the edge830, FONT_GLANCE and FONT_XTINY are the same metrics down to the pixel
        // (a=10 d=3 h=13), while FONT_SMALL is a=17. So asking for GLANCE unconditionally left the label at
        // 10 px of ascent on 6 of the 13 devices, when the NATIVE data field of that device uses `small`
        // (that is literally what edge830's simulator.json declares for its datafield label). Measured
        // 2026-07-27 from the author's 830 screenshot -- and it reads as "the 830's fonts are worse", which
        // is only half true: the hard edges are the device's bitmap fonts (2 bits per pixel, 4 grey levels
        // -- the native field looks exactly as hard), but the SIZE was ours.
        //
        // Taking the larger of the two fixes the whole bitmap family without naming a single device: the
        // TTF family keeps GLANCE (15 > 12) and nothing changes there.
        private function labelBaseFont() as Graphics.FontType {
            if (Graphics.getFontAscent(Graphics.FONT_SMALL) > Graphics.getFontAscent(Graphics.FONT_GLANCE)) {
                return Graphics.FONT_SMALL;
            }
            return Graphics.FONT_GLANCE;
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
        // reference prefix, which is drawn in the same font as the unit (secondary line).
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
                    groupW += dc.getTextWidthInPixels(mRefPrefix, u) + AVG_LABEL_GAP;
                }
                if (groupW <= usableW) {
                    return u;
                }
            }
            return null;
        }

        // --- Wide-mode font: largest whose [arrow + gap + inline template + gap + unit] fits; else drop
        //     the arrow. One stacked unit follows the whole "cur / ref" pair.
        private function selectInlineFont(dc as Graphics.Dc, usableW as Number) as Void {
            mInlineFont = Graphics.FONT_XTINY;
            mInlineUnitFont = Graphics.FONT_XTINY;
            mInlineArrowFits = false;
            for (var i = 0; i < mLadder.size(); i++) {
                var f = mLadder[i];
                if (!fitsBand(f, mPrimaryBandH)) { continue; }
                var ah = (Graphics.getFontAscent(f) * 4) / 5;
                var aw = arrowLeadWidth(dc, f, (ah * 3) / 5);
                var u = fitUnitFont(dc, f, mInlineTpl, aw + ARROW_GAP, usableW, false);
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
                    var u = fitUnitFont(dc, f, mInlineTpl, 0, usableW, false);
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
        // horizontally and centred vertically on cyMid with height h. COPY of Option B's drawUpArrow.
        // Paints in the colour the caller set; fill ops ignore pen width, so nothing to restore.
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
    }

}
