using Toybox.System as Sys;

class Interrupts {
    var io_if as Number = 0;
    var io_ie as Number = 0;

    const INT_VBLANK = 0x01;
    const INT_STAT   = 0x02;
    const INT_TIMER  = 0x04;
    const INT_SERIAL = 0x08;
    const INT_JOYPAD = 0x10;

    function initialize() {}

    function request(bit as Number) as Void {
        io_if |= bit;
    }

    function ifRead() as Number {
        return (io_if & 0x1F) | 0xE0;
    }

    function ifWrite(val as Number) as Void {
        io_if = val & 0x1F;
    }

    function ieRead() as Number {
        return io_ie;
    }

    function ieWrite(val as Number) as Void {
        io_ie = val & 0xFF;
    }
}
