using Toybox.WatchUi as WatchUi;
using Toybox.Graphics as Graphics;
using Toybox.System as Sys;
using Toybox.Lang as Lang;

class GarminBoyView extends WatchUi.View {
    var _emulator;
    var _bitmap = null;

    const OFFSET_X = 60;
    const OFFSET_Y = 68;

    // SIMULATOR: use BLOCK=16 (360 iterations, safe under simulator watchdog)
    // DEVICE:    use BLOCK=2  (23040 iterations into RAM buffer — fast on real HW)
    const BLOCK = 2;

    function initialize(emulator) {
        View.initialize();
        _emulator = emulator;
    }

    function onLayout(dc) {
        try {
            _bitmap = Graphics.createBufferedBitmap({:width => 160, :height => 144}).get();
            Sys.println("bitmap ok");
        } catch (ex instanceof Lang.Exception) {
            Sys.println("bitmap fail: " + ex.getErrorMessage());
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
            // Fallback: direct screen rendering
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
}
