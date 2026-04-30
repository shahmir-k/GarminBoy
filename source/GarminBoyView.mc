using Toybox.WatchUi as WatchUi;
using Toybox.Graphics as Graphics;
using Toybox.System as Sys;
using Toybox.Lang as Lang;

class GarminBoyView extends WatchUi.View {
    var _emulator;
    var _bitmap = null;

    const OFFSET_X = 60;
    const OFFSET_Y = 68;

    // BLOCK=8: 1440 fillRectangle calls to RAM buffer (~36K bytecodes) — safe on all devices
    // BLOCK=4: 5760 calls (~144K bytecodes) — only for devices with 240K+ bytecode budget
    const BLOCK = 8;

    function initialize(emulator) {
        View.initialize();
        _emulator = emulator;
    }

    function onLayout(dc) {
        try {
            _bitmap = Graphics.createBufferedBitmap({:width => 160, :height => 144}).get();
        } catch (ex instanceof Lang.Exception) {
            _bitmap = null;
        }
    }

    function onUpdate(dc) {
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();

        if (_emulator.isLoading()) {
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
            dc.drawText(140, 130, Graphics.FONT_SMALL, "Loading...", Graphics.TEXT_JUSTIFY_CENTER);
            return;
        }

        var fb      = _emulator.getFramebuffer();
        var palette = _emulator.getPalette();
        var step    = BLOCK;

        if (_bitmap != null) {
            var bdc = _bitmap.getDc();
            for (var c = 0; c < 4; c++) {
                bdc.setColor(palette[c], palette[c]);
                for (var y = 0; y < 144; y += step) {
                    var lineBase = y * 160;
                    for (var x = 0; x < 160; x += step) {
                        if ((fb[lineBase + x] & 0x03) == c) {
                            bdc.fillRectangle(x, y, step, step);
                        }
                    }
                }
            }
            dc.drawBitmap(OFFSET_X, OFFSET_Y, _bitmap);
        } else {
            // Fallback: direct rendering at lower resolution
            for (var c = 0; c < 4; c++) {
                dc.setColor(palette[c], palette[c]);
                for (var y = 0; y < 144; y += 8) {
                    var lineBase = y * 160;
                    for (var x = 0; x < 160; x += 8) {
                        if ((fb[lineBase + x] & 0x03) == c) {
                            dc.fillRectangle(OFFSET_X + x, OFFSET_Y + y, 8, 8);
                        }
                    }
                }
            }
        }
    }
}
