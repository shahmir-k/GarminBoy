// Module-level joypad button constants
const BUTTON_A      = 0x01;
const BUTTON_B      = 0x02;
const BUTTON_SELECT = 0x04;
const BUTTON_START  = 0x08;
const BUTTON_RIGHT  = 0x10;
const BUTTON_LEFT   = 0x20;
const BUTTON_UP     = 0x40;
const BUTTON_DOWN   = 0x80;

class Joypad {
    var pressedKeys = 0;
    var _selection  = 2;
    var _interrupts;

    function initialize(interrupts) {
        _interrupts = interrupts;
    }

    function read() {
        var val;
        if (_selection == 1) {
            val = (~(pressedKeys >> 4)) & 0x0F;
        } else if (_selection == 0) {
            val = (~pressedKeys) & 0x0F;
        } else {
            val = 0x0F;
        }
        return val & 0xFF;
    }

    function write(val) {
        var sel = (~val) & 0x30;
        if (sel == 0x30 || sel == 0) {
            _selection = 2;
        } else if ((sel & 0x20) != 0) {
            _selection = 0;
        } else if ((sel & 0x10) != 0) {
            _selection = 1;
        } else {
            _selection = 2;
        }
    }

    function keyDown(gbKey) {
        pressedKeys |= gbKey;
        _interrupts.request(INT_JOYPAD);
    }

    function keyUp(gbKey) {
        pressedKeys &= ~gbKey;
    }
}
