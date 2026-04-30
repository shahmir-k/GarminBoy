using Toybox.WatchUi as WatchUi;
using Toybox.Graphics as Graphics;
using Toybox.System as Sys;
using Toybox.Lang as Lang;

// Module-level — class-level const is unreliable in Monkey C SDK 9.x
const GB_OFFSET_X = 60;
const GB_OFFSET_Y = 68;
// BLOCK=8: 1440 fillRectangle calls → ~36K bytecodes, safe on all compatible devices
// BLOCK=4: 5760 calls → ~144K bytecodes, fine on Fenix 7x Pro (240K budget)
const GB_BLOCK = 8;

class GarminBoyView extends WatchUi.View {
    var _emulator;
    var _bitmap  = null;

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
        var step    = GB_BLOCK;

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
            dc.drawBitmap(GB_OFFSET_X, GB_OFFSET_Y, _bitmap);
        } else {
            for (var c = 0; c < 4; c++) {
                dc.setColor(palette[c], palette[c]);
                for (var y = 0; y < 144; y += step) {
                    var lineBase = y * 160;
                    for (var x = 0; x < 160; x += step) {
                        if ((fb[lineBase + x] & 0x03) == c) {
                            dc.fillRectangle(GB_OFFSET_X + x, GB_OFFSET_Y + y, step, step);
                        }
                    }
                }
            }
        }
    }
}
