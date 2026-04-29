using Toybox.WatchUi as WatchUi;

class GarminBoyDelegate extends WatchUi.InputDelegate {
    var _joypad as Joypad;

    function initialize(joypad as Joypad) {
        InputDelegate.initialize();
        _joypad = joypad;
    }

    function onKey(keyEvent as WatchUi.KeyEvent) as Boolean {
        var key    = keyEvent.getKey();
        var isDown = (keyEvent.getType() == WatchUi.PRESS_TYPE_DOWN);

        var gbKey = 0;
        switch (key) {
            case WatchUi.KEY_UP:    gbKey = Joypad.BUTTON_UP;     break;
            case WatchUi.KEY_DOWN:  gbKey = Joypad.BUTTON_DOWN;   break;
            case WatchUi.KEY_START: gbKey = Joypad.BUTTON_A;      break;
            case WatchUi.KEY_LAP:   gbKey = Joypad.BUTTON_B;      break;
            case WatchUi.KEY_ESC:   gbKey = Joypad.BUTTON_SELECT; break;
            case WatchUi.KEY_LIGHT: gbKey = Joypad.BUTTON_START;  break;
            default: return false;
        }

        if (isDown) { _joypad.keyDown(gbKey); }
        else        { _joypad.keyUp(gbKey); }
        return true;
    }
}
