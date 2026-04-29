using Toybox.WatchUi as WatchUi;
using Toybox.Graphics as Graphics;

class GarminBoyView extends WatchUi.View {
    var _emulator;

    // GB screen centered on 280×280 display at 1× scale
    const OFFSET_X = 60;   // (280 - 160) / 2
    const OFFSET_Y = 68;   // (280 - 144) / 2

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

        var fb      = _emulator.getFramebuffer();
        var palette = _emulator.getPalette();

        // Group pixels by palette index to minimise setColor() calls
        var groups = [new [160 * 144]b, new [160 * 144]b,
                      new [160 * 144]b, new [160 * 144]b];
        var counts = [0, 0, 0, 0];

        for (var i = 0; i < 160 * 144; i++) {
            var idx = fb[i] & 0x03;
            var g = groups[idx];
            var cnt = counts[idx];
            g[cnt * 2]     = (i % 160 + OFFSET_X) & 0xFF;
            g[cnt * 2 + 1] = (i / 160 + OFFSET_Y) & 0xFF;
            counts[idx] = cnt + 1;
        }

        for (var c = 0; c < 4; c++) {
            dc.setColor(palette[c], palette[c]);
            var g = groups[c];
            var cnt = counts[c];
            for (var p = 0; p < cnt; p++) {
                dc.drawPoint(g[p * 2] & 0xFF, g[p * 2 + 1] & 0xFF);
            }
        }
    }
}
