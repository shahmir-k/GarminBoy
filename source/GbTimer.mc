// GbTimer — DIV/TIMA/TMA/TAC cycle-counted timer.
// Named GbTimer to avoid collision with Toybox.Timer.

class GbTimer {
    var div  = 0;
    var tima = 0;
    var tma  = 0;
    var tac  = 0;

    var _divCycles  = 0;
    var _timaCycles = 0;
    var _timaThreshold = 1024;

    var _interrupts;

    // Cycles-per-TIMA-tick at each TAC frequency (T-states)
    // 4194304 Hz / freq
    // 00: 4096   Hz -> 1024 T-states
    // 01: 262144 Hz -> 16 T-states
    // 10: 65536  Hz -> 64 T-states
    // 11: 16384  Hz -> 256 T-states
    var TIMA_THRESHOLDS = [1024, 16, 64, 256];

    function initialize(interrupts) {
        _interrupts = interrupts;
    }

    function start() {
        div  = 0;
        tima = 0;
        tma  = 0;
        tac  = 0;
        _divCycles  = 0;
        _timaCycles = 0;
        _timaThreshold = 1024;
    }

    function cycle(tStates) {
        // DIV increments every 256 T-states
        _divCycles += tStates;
        if (_divCycles >= 256) {
            _divCycles -= 256;
            div = (div + 1) & 0xFF;
        }

        if ((tac & 0x04) == 0) { return; }

        _timaCycles += tStates;
        if (_timaCycles >= _timaThreshold) {
            _timaCycles -= _timaThreshold;
            tima = (tima + 1) & 0xFF;
            if (tima == 0) {
                tima = tma;
                _interrupts.request(INT_TIMER);
            }
        }
    }

    function read(addr) {
        switch (addr) {
            case 0xFF04: return div  & 0xFF;
            case 0xFF05: return tima & 0xFF;
            case 0xFF06: return tma  & 0xFF;
            case 0xFF07: return tac  & 0xFF;
        }
        return 0xFF;
    }

    function write(addr, val) {
        switch (addr) {
            case 0xFF04:
                div = 0;
                _divCycles = 0;
                break;
            case 0xFF05:
                tima = val & 0xFF;
                break;
            case 0xFF06:
                tma = val & 0xFF;
                break;
            case 0xFF07:
                tac = val & 0xFF;
                _timaThreshold = TIMA_THRESHOLDS[tac & 0x03];
                break;
        }
    }
}
