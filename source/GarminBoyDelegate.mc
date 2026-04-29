using Toybox.WatchUi as WatchUi;

class GarminBoyDelegate extends WatchUi.InputDelegate {
    var _joypad;

    function initialize(joypad) {
        InputDelegate.initialize();
        _joypad = joypad;
    }

    function onKey(keyEvent) {
        var key    = keyEvent.getKey();
        var isDown = (keyEvent.getType() == WatchUi.PRESS_TYPE_DOWN);

        var gbKey = 0;
        switch (key) {
            case WatchUi.KEY_UP:    gbKey = BUTTON_UP;     break;
            case WatchUi.KEY_DOWN:  gbKey = BUTTON_DOWN;   break;
            case WatchUi.KEY_START: gbKey = BUTTON_A;      break;
            case WatchUi.KEY_LAP:   gbKey = BUTTON_B;      break;
            case WatchUi.KEY_ESC:   gbKey = BUTTON_SELECT; break;
            case WatchUi.KEY_LIGHT: gbKey = BUTTON_START;  break;
            default: return false;
        }

        if (isDown) { _joypad.keyDown(gbKey); }
        else        { _joypad.keyUp(gbKey); }
        return true;
    }
}
