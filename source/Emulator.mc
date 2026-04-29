using Toybox.Timer as Timer;
using Toybox.WatchUi as WatchUi;

// Module-level state constants — class-level const can't be used in
// instance variable initializers reliably in Monkey C
const STATE_LOADING = 0;
const STATE_SETUP   = 1;
const STATE_RUNNING = 2;

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

    var _state = 0;  // STATE_LOADING

    // T-states per tick. Full GB frame = 70,224.
    // Simulator enforces ~250ms minimum timer interval and tighter watchdog.
    // 2000 is the highest stable value in the simulator.
    // On the real Fenix 7x (16ms timer, native VM) raise this to 70224.
    const CYCLES_PER_TICK = 2000;

    // Force a view update every N ticks even if no VBlank fired,
    // so the framebuffer is visible in the simulator.
    const UPDATE_EVERY_N_TICKS = 5;
    var _tickCount = 0;

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
            if (done) {
                _state = STATE_SETUP;
                WatchUi.requestUpdate();
            }
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
            _tickCount = 0;
            WatchUi.requestUpdate();
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

        _tickCount++;
        if (_ppu._frameReady || _tickCount >= UPDATE_EVERY_N_TICKS) {
            if (_ppu._frameReady) { _ppu._frameReady = false; }
            _tickCount = 0;
            WatchUi.requestUpdate();
        }
    }

    function isLoading()      { return _state != STATE_RUNNING; }
    function getJoypad()      { return _joypad; }
    function getFramebuffer() { return _ppu.framebuffer; }
    function getPalette()     { return _ppu.palette; }
}
