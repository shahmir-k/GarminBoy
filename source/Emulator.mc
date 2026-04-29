using Toybox.Timer as Timer;
using Toybox.WatchUi as WatchUi;

class Emulator {
    var _mem;
    var _cpu;
    var _ppu;
    var _gbTimer;
    var _joypad;
    var _sound;
    var _interrupts;
    var _rom;
    var _loop;

    const STATE_LOADING = 0;
    const STATE_SETUP   = 1;
    const STATE_RUNNING = 2;
    var _state = STATE_LOADING;

    // T-states to execute per timer tick.
    // Full GB frame = 70224 T-states. The simulator enforces a minimum timer
    // interval (~250ms) and has a tighter watchdog than the real device.
    // 1500 is stable in the simulator; raise toward 70224 on the real Fenix 7x.
    const CYCLES_PER_TICK = 1500;

    var _framesProduced = 0;

    function initialize() {}

    function init() {
        _interrupts = new Interrupts();
        _rom        = new Rom();
        _sound      = new Sound();
        _joypad     = new Joypad(_interrupts);
        _gbTimer    = new GbTimer(_interrupts);

        _loop = new Timer.Timer();
        var cb = method(:tick);
        _loop.start(cb, 16, true);
    }

    function tick() {
        if (_state == STATE_LOADING) {
            var done = _rom.loadStep();
            if (done) { _state = STATE_SETUP; }
            WatchUi.requestUpdate();
            return;
        }

        if (_state == STATE_SETUP) {
            _mem = new Memory(_rom.data, _interrupts);
            _ppu = new Ppu(_mem, _interrupts);
            _cpu = new Cpu(_mem, _interrupts);

            _mem.setPpu(_ppu);
            _mem.setTimer(_gbTimer);
            _mem.setJoypad(_joypad);
            _mem.setSound(_sound);

            _sound.start();
            _gbTimer.start();
            _ppu.start();
            _cpu.start();

            _state = STATE_RUNNING;
            return;
        }

        // STATE_RUNNING
        var cyclesLeft = CYCLES_PER_TICK;
        while (cyclesLeft > 0) {
            var c = _cpu.step();
            _ppu.cycle(c);
            _gbTimer.cycle(c);
            cyclesLeft -= c;
        }

        if (_ppu._frameReady) {
            _ppu._frameReady = false;
            _framesProduced++;
            WatchUi.requestUpdate();
        }
    }

    function isLoading()  { return _state != STATE_RUNNING; }
    function hasFrame()   { return _framesProduced > 0; }
    function getJoypad()      { return _joypad; }
    function getFramebuffer() { return _ppu.framebuffer; }
    function getPalette()     { return _ppu.palette; }
}
