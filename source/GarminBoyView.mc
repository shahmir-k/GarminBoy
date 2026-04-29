using Toybox.WatchUi as WatchUi;
using Toybox.Graphics as Graphics;

class GarminBoyView extends WatchUi.View {
    var _emulator;
    var _bitmap = null;

    // GB screen centered on 280×280 display at 1× scale
    const OFFSET_X = 60;
    const OFFSET_Y = 68;

    function initialize(emulator) {
        View.initialize();
        _emulator = emulator;
    }

    function onLayout(dc) {
        // Allocate the off-screen buffer once — 160×144, drawn to RAM not display
        var opts = {:width => 160, :height => 144};
        _bitmap = Graphics.createBufferedBitmap(opts).get();
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
        var bdc     = _bitmap.getDc();

        // Draw into off-screen RAM buffer — one setColor + drawPoint per pixel group
        for (var c = 0; c < 4; c++) {
            bdc.setColor(palette[c], palette[c]);
            for (var y = 0; y < 144; y++) {
                var lineBase = y * 160;
                for (var x = 0; x < 160; x++) {
                    if ((fb[lineBase + x] & 0x03) == c) {
                        bdc.drawPoint(x, y);
                    }
                }
            }
        }

        // Single hardware blit to screen — one call regardless of content
        dc.drawBitmap(OFFSET_X, OFFSET_Y, _bitmap);
    }
}
