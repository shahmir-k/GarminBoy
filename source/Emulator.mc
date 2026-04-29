using Toybox.Timer as Timer;
using Toybox.WatchUi as WatchUi;
using Toybox.System as Sys;
using Toybox.Lang as Lang;

class Emulator {
    var _mem       ;
    var _cpu       ;
    var _ppu       ;
    var _gbTimer   ;
    var _joypad    ;
    var _sound     ;
    var _interrupts;
    var _rom       ;
    var _loop      ;

    // T-states per 16ms tick ≈ one GB frame (70224 T-states per frame)
    const CYCLES_PER_TICK = 70224;

    function initialize() {}

    function init() {
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
        var cb = method(:tick);
        _loop.start(cb, 16, true);
    }

    function tick() {
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

    function getJoypad()    { return _joypad; }
    function getFramebuffer() { return _ppu.framebuffer; }
    function getPalette()    { return _ppu.palette; }
}
