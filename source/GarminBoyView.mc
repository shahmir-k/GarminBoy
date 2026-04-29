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

    function onLayout(dc) {
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();
    }

    function onUpdate(dc) {
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();

        if (_emulator.isLoading()) {
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(140, 116, Graphics.FONT_MEDIUM, "GarminBoy", Graphics.TEXT_JUSTIFY_CENTER);

            var pct = _emulator._rom.progress();
            var barW = (pct * 160).toNumber();
            dc.setColor(0x00AA00, Graphics.COLOR_TRANSPARENT);
            dc.fillRectangle(60, 150, barW, 10);
            dc.setColor(0x444444, Graphics.COLOR_TRANSPARENT);
            dc.drawRectangle(60, 150, 160, 10);
            return;
        }

        // Render framebuffer — show whatever the PPU has produced so far
        var fb      = _emulator.getFramebuffer();
        var palette = _emulator.getPalette();

        for (var c = 0; c < 4; c++) {
            dc.setColor(palette[c], palette[c]);
            for (var i = 0; i < 160 * 144; i++) {
                if ((fb[i] & 0x03) == c) {
                    dc.drawPoint(OFFSET_X + (i % 160), OFFSET_Y + (i / 160));
                }
            }
        }
    }
}
