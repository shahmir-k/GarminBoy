using Toybox.WatchUi as WatchUi;
using Toybox.Graphics as Graphics;
using Toybox.System as Sys;

class GarminBoyView extends WatchUi.View {
    var _emulator;

    // GB screen at 1x scale centered on 280×280 display
    const OFFSET_X = 60;
    const OFFSET_Y = 68;

    // Pixel block size: 1 = full 160×144 resolution.
    // If the watch is too slow, increase to 2 or 4 (each reduces draw calls by 4x).
    const PIXEL_STEP = 1;

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
        var step    = PIXEL_STEP;

        for (var c = 0; c < 4; c++) {
            dc.setColor(palette[c], palette[c]);
            for (var y = 0; y < 144; y += step) {
                var lineBase = y * 160;
                for (var x = 0; x < 160; x += step) {
                    if ((fb[lineBase + x] & 0x03) == c) {
                        dc.fillRectangle(OFFSET_X + x, OFFSET_Y + y, step, step);
                    }
                }
            }
        }
    }
}
