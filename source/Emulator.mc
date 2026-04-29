using Toybox.Timer as Timer;
using Toybox.WatchUi as WatchUi;
using Toybox.System as Sys;

class Emulator {
    var _mem        as Memory;
    var _cpu        as Cpu;
    var _ppu        as Ppu;
    var _gbTimer    as GbTimer;
    var _joypad     as Joypad;
    var _sound      as Sound;
    var _interrupts as Interrupts;
    var _rom        as Rom;
    var _loop       as Timer.Timer;

    // T-states per 16ms tick ≈ one GB frame (70224 T-states per frame)
    const CYCLES_PER_TICK = 70224;

    function initialize() {}

    function init() as Void {
        _interrupts = new Interrupts();
        _rom        = new Rom();
        _sound      = new Sound();
        _joypad     = new Joypad(_interrupts);
        _gbTimer    = new GbTimer(_interrupts);
        _mem        = new Memory(_rom.data, _interrupts);
        _ppu        = new Ppu(_mem, _interrupts);
        _cpu        = new Cpu(_mem, _interrupts);

        _mem.setPpu(_ppu);
        _mem.setTimer(_gbTimer);
        _mem.setJoypad(_joypad);
        _mem.setSound(_sound);

        _sound.start();
        _gbTimer.start();
        _ppu.start();
        _cpu.start();

        _loop = new Timer.Timer();
        _loop.start(method(:tick), 16, true);
    }

    function tick() as Void {
        var cyclesLeft = CYCLES_PER_TICK;
        while (cyclesLeft > 0) {
            var c = _cpu.step();
            _ppu.cycle(c);
            _gbTimer.cycle(c);
            cyclesLeft -= c;
        }

        if (_ppu._frameReady) {
            _ppu._frameReady = false;
            WatchUi.requestUpdate();
        }
    }

    function getJoypad() as Joypad    { return _joypad; }
    function getFramebuffer() as ByteArray { return _ppu.framebuffer; }
    function getPalette() as Array    { return _ppu.palette; }
}
