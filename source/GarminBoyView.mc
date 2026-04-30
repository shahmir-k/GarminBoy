using Toybox.WatchUi as WatchUi;
using Toybox.Graphics as Graphics;

// Module-level constants
const GB_OFFSET_X = 60;
const GB_OFFSET_Y = 68;
const GB_BLOCK    = 8;   // 1440 fillRectangle calls per frame — safe on all devices

class GarminBoyView extends WatchUi.View {
    var _emulator;

    function initialize(emulator) {
        View.initialize();
        _emulator = emulator;
    }

    function onLayout(dc) {}

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
