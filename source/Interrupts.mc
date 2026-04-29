// Module-level interrupt bit constants — accessible everywhere without an instance
const INT_VBLANK = 0x01;
const INT_STAT   = 0x02;
const INT_TIMER  = 0x04;
const INT_SERIAL = 0x08;
const INT_JOYPAD = 0x10;

class Interrupts {
    var io_if = 0;
    var io_ie = 0;

    function initialize() {}

    function request(bit) {
        io_if |= bit;
    }

    function ifRead() {
        return (io_if & 0x1F) | 0xE0;
    }

    function ifWrite(val) {
        io_if = val & 0x1F;
    }

    function ieRead() {
        return io_ie;
    }

    function ieWrite(val) {
        io_ie = val & 0xFF;
    }
}
