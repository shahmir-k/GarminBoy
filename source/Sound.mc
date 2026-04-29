// Sound register stub — no audio output (Connect IQ has no PCM API).
// All NR1x–NR5x and wave RAM registers are stored so ROM writes don't fault.

class Sound {
    var nr10 as Number = 0x80;
    var nr11 as Number = 0xBF;
    var nr12 as Number = 0xF3;
    var nr13 as Number = 0x00;
    var nr14 as Number = 0xBF;
    var nr21 as Number = 0x3F;
    var nr22 as Number = 0x00;
    var nr23 as Number = 0x00;
    var nr24 as Number = 0xBF;
    var nr30 as Number = 0x7F;
    var nr31 as Number = 0xFF;
    var nr32 as Number = 0x9F;
    var nr33 as Number = 0x00;
    var nr34 as Number = 0xBF;
    var nr41 as Number = 0xFF;
    var nr42 as Number = 0x00;
    var nr43 as Number = 0x00;
    var nr44 as Number = 0xBF;
    var nr50 as Number = 0x77;
    var nr51 as Number = 0xF3;
    var nr52 as Number = 0xF1;
    var wav  as ByteArray;

    function initialize() {
        wav = new [16]b;
    }

    function start() as Void {}

    function read(addr as Number) as Number {
        switch (addr) {
            case 0xFF10: return nr10;
            case 0xFF11: return nr11;
            case 0xFF12: return nr12;
            case 0xFF13: return nr13;
            case 0xFF14: return nr14;
            case 0xFF16: return nr21;
            case 0xFF17: return nr22;
            case 0xFF18: return nr23;
            case 0xFF19: return nr24;
            case 0xFF1A: return nr30;
            case 0xFF1B: return nr31;
            case 0xFF1C: return nr32;
            case 0xFF1D: return nr33;
            case 0xFF1E: return nr34;
            case 0xFF20: return nr41;
            case 0xFF21: return nr42;
            case 0xFF22: return nr43;
            case 0xFF23: return nr44;
            case 0xFF24: return nr50;
            case 0xFF25: return nr51;
            case 0xFF26: return nr52;
        }
        if (addr >= 0xFF30 && addr <= 0xFF3F) {
            return wav[addr - 0xFF30] & 0xFF;
        }
        return 0xFF;
    }

    function write(addr as Number, val as Number) as Void {
        switch (addr) {
            case 0xFF10: nr10 = val; break;
            case 0xFF11: nr11 = val; break;
            case 0xFF12: nr12 = val; break;
            case 0xFF13: nr13 = val; break;
            case 0xFF14: nr14 = val; break;
            case 0xFF16: nr21 = val; break;
            case 0xFF17: nr22 = val; break;
            case 0xFF18: nr23 = val; break;
            case 0xFF19: nr24 = val; break;
            case 0xFF1A: nr30 = val; break;
            case 0xFF1B: nr31 = val; break;
            case 0xFF1C: nr32 = val; break;
            case 0xFF1D: nr33 = val; break;
            case 0xFF1E: nr34 = val; break;
            case 0xFF20: nr41 = val; break;
            case 0xFF21: nr42 = val; break;
            case 0xFF22: nr43 = val; break;
            case 0xFF23: nr44 = val; break;
            case 0xFF24: nr50 = val; break;
            case 0xFF25: nr51 = val; break;
            case 0xFF26: nr52 = val; break;
            default:
                if (addr >= 0xFF30 && addr <= 0xFF3F) {
                    wav[addr - 0xFF30] = val & 0xFF;
                }
                break;
        }
    }
}
