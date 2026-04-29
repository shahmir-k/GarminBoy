using Toybox.WatchUi as WatchUi;
using Toybox.Graphics as Graphics;

class GarminBoyView extends WatchUi.View {
    var _emulator;

    const OFFSET_X = 60;
    const OFFSET_Y = 68;

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

        // Rendering stripped — show solid placeholder to confirm CPU loop is stable
        dc.setColor(0x00AA00, Graphics.COLOR_BLACK);
        dc.drawText(140, 120, Graphics.FONT_SMALL, "Running", Graphics.TEXT_JUSTIFY_CENTER);
        dc.setColor(0xC4CFA1, Graphics.COLOR_BLACK);
        dc.fillRectangle(OFFSET_X, OFFSET_Y, 160, 144);
    }
}
