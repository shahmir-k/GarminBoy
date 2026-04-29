using Toybox.System as Sys;

class Cpu {
    var regA = 0;
    var regF = 0;
    var regB = 0;
    var regC = 0;
    var regD = 0;
    var regE = 0;
    var regH = 0;
    var regL = 0;
    var sp   = 0;
    var pc   = 0;
    var ime  = 0;
    var halted = false;

    const FLAG_Z  = 0x80;
    const FLAG_N  = 0x40;
    const FLAG_H  = 0x20;
    const FLAG_CY = 0x10;

    var _mem       ;
    var _interrupts;

    function initialize(mem, interrupts) {
        _mem = mem;
        _interrupts = interrupts;
    }

    function start() {
        regA = 0x01; regF = 0xB0;
        regB = 0x00; regC = 0x13;
        regD = 0x00; regE = 0xD8;
        regH = 0x01; regL = 0x4D;
        sp = 0xFFFE;
        pc = 0x0100;
        ime = 0;
        halted = false;
    }

    // ── register pair helpers ──────────────────────────────────────────────
    function regHL() { return ((regH & 0xFF) << 8) | (regL & 0xFF); }
    function setHL(v) { regH = (v >> 8) & 0xFF; regL = v & 0xFF; }
    function regBC() { return ((regB & 0xFF) << 8) | (regC & 0xFF); }
    function setBC(v) { regB = (v >> 8) & 0xFF; regC = v & 0xFF; }
    function regDE() { return ((regD & 0xFF) << 8) | (regE & 0xFF); }
    function setDE(v) { regD = (v >> 8) & 0xFF; regE = v & 0xFF; }
    function regAF() { return ((regA & 0xFF) << 8) | (regF & 0xF0); }
    function setAF(v) { regA = (v >> 8) & 0xFF; regF = v & 0xF0; }

    // ── 8-bit register helpers (reg 0-7: B C D E H L (HL) A) ──────────────
    function readReg8(reg) {
        switch (reg) {
            case 0: return regB & 0xFF;
            case 1: return regC & 0xFF;
            case 2: return regD & 0xFF;
            case 3: return regE & 0xFF;
            case 4: return regH & 0xFF;
            case 5: return regL & 0xFF;
            case 6: return _mem.readByte(regHL()) & 0xFF;
            default: return regA & 0xFF;
        }
    }

    function writeReg8(reg, val) {
        val = val & 0xFF;
        switch (reg) {
            case 0: regB = val; break;
            case 1: regC = val; break;
            case 2: regD = val; break;
            case 3: regE = val; break;
            case 4: regH = val; break;
            case 5: regL = val; break;
            case 6: _mem.writeByte(regHL(), val); break;
            default: regA = val; break;
        }
    }

    // ── 16-bit register helpers (0=BC 1=DE 2=HL 3=SP) ─────────────────────
    function readReg16(reg) {
        switch (reg) {
            case 0: return regBC();
            case 1: return regDE();
            case 2: return regHL();
            default: return sp & 0xFFFF;
        }
    }

    function writeReg16(reg, val) {
        val = val & 0xFFFF;
        switch (reg) {
            case 0: setBC(val); break;
            case 1: setDE(val); break;
            case 2: setHL(val); break;
            default: sp = val; break;
        }
    }

    // ── stack helpers ──────────────────────────────────────────────────────
    function push16(val) {
        sp = (sp - 1) & 0xFFFF;
        _mem.writeByte(sp, (val >> 8) & 0xFF);
        sp = (sp - 1) & 0xFFFF;
        _mem.writeByte(sp, val & 0xFF);
    }

    function pop16() {
        var lo = _mem.readByte(sp) & 0xFF;
        sp = (sp + 1) & 0xFFFF;
        var hi = _mem.readByte(sp) & 0xFF;
        sp = (sp + 1) & 0xFFFF;
        return (hi << 8) | lo;
    }

    // ── interrupt dispatch ─────────────────────────────────────────────────
    function handleInterrupts() {
        var pending = _interrupts.io_if & _interrupts.io_ie & 0x1F;
        if (pending != 0) {
            halted = false;
            if (ime != 0) {
                for (var i = 0; i <= 4; i++) {
                    if ((pending & (1 << i)) != 0) {
                        _interrupts.io_if &= ~(1 << i);
                        ime = 0;
                        push16(pc);
                        pc = (i << 3) + 0x40;
                        return;
                    }
                }
            }
        }
    }

    // ── main step ─────────────────────────────────────────────────────────
    function step() {
        handleInterrupts();
        if (halted) { return 4; }

        var opcode = _mem.readByte(pc) & 0xFF;
        pc = (pc + 1) & 0xFFFF;

        switch (opcode) {
            // ── 0x00 NOP ──
            case 0x00: return 4;

            // ── 0x01 LD BC,nn ──
            case 0x01: {
                var lo = _mem.readByte(pc) & 0xFF;
                var hi = _mem.readByte(pc + 1) & 0xFF;
                pc = (pc + 2) & 0xFFFF;
                setBC((hi << 8) | lo);
                return 12;
            }

            // ── 0x02 LD (BC),A ──
            case 0x02:
                _mem.writeByte(regBC(), regA & 0xFF);
                return 8;

            // ── 0x03 INC BC ──
            case 0x03:
                setBC((regBC() + 1) & 0xFFFF);
                return 8;

            // ── 0x04 INC B ──
            case 0x04: { var old = regB & 0xFF; regB = (old + 1) & 0xFF; regF = incFlags(old, regB) | (regF & FLAG_CY); return 4; }

            // ── 0x05 DEC B ──
            case 0x05: { var old = regB & 0xFF; regB = (old - 1) & 0xFF; regF = decFlags(old, regB) | (regF & FLAG_CY); return 4; }

            // ── 0x06 LD B,n ──
            case 0x06: regB = _mem.readByte(pc) & 0xFF; pc = (pc + 1) & 0xFFFF; return 8;

            // ── 0x07 RLCA ──
            case 0x07: {
                var a = regA & 0xFF;
                var cy = (a >> 7) & 1;
                regA = ((a << 1) | cy) & 0xFF;
                regF = cy != 0 ? FLAG_CY : 0;
                return 4;
            }

            // ── 0x08 LD (a16),SP ──
            case 0x08: {
                var addr = readWord(pc); pc = (pc + 2) & 0xFFFF;
                _mem.writeByte(addr, sp & 0xFF);
                _mem.writeByte((addr + 1) & 0xFFFF, (sp >> 8) & 0xFF);
                return 20;
            }

            // ── 0x09 ADD HL,BC ──
            case 0x09: { addHL(regBC()); return 8; }

            // ── 0x0A LD A,(BC) ──
            case 0x0A: regA = _mem.readByte(regBC()) & 0xFF; return 8;

            // ── 0x0B DEC BC ──
            case 0x0B: setBC((regBC() - 1) & 0xFFFF); return 8;

            // ── 0x0C INC C ──
            case 0x0C: { var old = regC & 0xFF; regC = (old + 1) & 0xFF; regF = incFlags(old, regC) | (regF & FLAG_CY); return 4; }

            // ── 0x0D DEC C ──
            case 0x0D: { var old = regC & 0xFF; regC = (old - 1) & 0xFF; regF = decFlags(old, regC) | (regF & FLAG_CY); return 4; }

            // ── 0x0E LD C,n ──
            case 0x0E: regC = _mem.readByte(pc) & 0xFF; pc = (pc + 1) & 0xFFFF; return 8;

            // ── 0x0F RRCA ──
            case 0x0F: {
                var a = regA & 0xFF;
                var cy = a & 1;
                regA = ((a >> 1) | (cy << 7)) & 0xFF;
                regF = cy != 0 ? FLAG_CY : 0;
                return 4;
            }

            // ── 0x10 STOP (treat as NOP for DMG) ──
            case 0x10: pc = (pc + 1) & 0xFFFF; return 4;

            // ── 0x11 LD DE,nn ──
            case 0x11: {
                var lo = _mem.readByte(pc) & 0xFF;
                var hi = _mem.readByte(pc + 1) & 0xFF;
                pc = (pc + 2) & 0xFFFF;
                setDE((hi << 8) | lo);
                return 12;
            }

            // ── 0x12 LD (DE),A ──
            case 0x12: _mem.writeByte(regDE(), regA & 0xFF); return 8;

            // ── 0x13 INC DE ──
            case 0x13: setDE((regDE() + 1) & 0xFFFF); return 8;

            // ── 0x14 INC D ──
            case 0x14: { var old = regD & 0xFF; regD = (old + 1) & 0xFF; regF = incFlags(old, regD) | (regF & FLAG_CY); return 4; }

            // ── 0x15 DEC D ──
            case 0x15: { var old = regD & 0xFF; regD = (old - 1) & 0xFF; regF = decFlags(old, regD) | (regF & FLAG_CY); return 4; }

            // ── 0x16 LD D,n ──
            case 0x16: regD = _mem.readByte(pc) & 0xFF; pc = (pc + 1) & 0xFFFF; return 8;

            // ── 0x17 RLA ──
            case 0x17: {
                var a = regA & 0xFF;
                var oldCy = (regF & FLAG_CY) != 0 ? 1 : 0;
                var newCy = (a >> 7) & 1;
                regA = ((a << 1) | oldCy) & 0xFF;
                regF = newCy != 0 ? FLAG_CY : 0;
                return 4;
            }

            // ── 0x18 JR e ──
            case 0x18: {
                var e = _mem.readByte(pc) & 0xFF;
                pc = (pc + 1) & 0xFFFF;
                var off = (e & 0x80) != 0 ? e - 256 : e;
                pc = (pc + off) & 0xFFFF;
                return 12;
            }

            // ── 0x19 ADD HL,DE ──
            case 0x19: { addHL(regDE()); return 8; }

            // ── 0x1A LD A,(DE) ──
            case 0x1A: regA = _mem.readByte(regDE()) & 0xFF; return 8;

            // ── 0x1B DEC DE ──
            case 0x1B: setDE((regDE() - 1) & 0xFFFF); return 8;

            // ── 0x1C INC E ──
            case 0x1C: { var old = regE & 0xFF; regE = (old + 1) & 0xFF; regF = incFlags(old, regE) | (regF & FLAG_CY); return 4; }

            // ── 0x1D DEC E ──
            case 0x1D: { var old = regE & 0xFF; regE = (old - 1) & 0xFF; regF = decFlags(old, regE) | (regF & FLAG_CY); return 4; }

            // ── 0x1E LD E,n ──
            case 0x1E: regE = _mem.readByte(pc) & 0xFF; pc = (pc + 1) & 0xFFFF; return 8;

            // ── 0x1F RRA ──
            case 0x1F: {
                var a = regA & 0xFF;
                var oldCy = (regF & FLAG_CY) != 0 ? 0x80 : 0;
                var newCy = a & 1;
                regA = ((a >> 1) | oldCy) & 0xFF;
                regF = newCy != 0 ? FLAG_CY : 0;
                return 4;
            }

            // ── 0x20 JR NZ,e ──
            case 0x20: {
                var e = _mem.readByte(pc) & 0xFF;
                pc = (pc + 1) & 0xFFFF;
                if ((regF & FLAG_Z) == 0) {
                    var off = (e & 0x80) != 0 ? e - 256 : e;
                    pc = (pc + off) & 0xFFFF;
                    return 12;
                }
                return 8;
            }

            // ── 0x21 LD HL,nn ──
            case 0x21: {
                var lo = _mem.readByte(pc) & 0xFF;
                var hi = _mem.readByte(pc + 1) & 0xFF;
                pc = (pc + 2) & 0xFFFF;
                setHL((hi << 8) | lo);
                return 12;
            }

            // ── 0x22 LDI (HL),A ──
            case 0x22: { var hl = regHL(); _mem.writeByte(hl, regA & 0xFF); setHL((hl + 1) & 0xFFFF); return 8; }

            // ── 0x23 INC HL ──
            case 0x23: setHL((regHL() + 1) & 0xFFFF); return 8;

            // ── 0x24 INC H ──
            case 0x24: { var old = regH & 0xFF; regH = (old + 1) & 0xFF; regF = incFlags(old, regH) | (regF & FLAG_CY); return 4; }

            // ── 0x25 DEC H ──
            case 0x25: { var old = regH & 0xFF; regH = (old - 1) & 0xFF; regF = decFlags(old, regH) | (regF & FLAG_CY); return 4; }

            // ── 0x26 LD H,n ──
            case 0x26: regH = _mem.readByte(pc) & 0xFF; pc = (pc + 1) & 0xFFFF; return 8;

            // ── 0x27 DAA ──
            case 0x27: {
                var a = regA & 0xFF;
                var correction = 0;
                var newCy = 0;
                if ((regF & FLAG_N) == 0) {
                    if ((regF & FLAG_H) != 0 || (a & 0x0F) > 9) { correction |= 0x06; }
                    if ((regF & FLAG_CY) != 0 || a > 0x99) { correction |= 0x60; newCy = FLAG_CY; }
                    a = (a + correction) & 0xFF;
                } else {
                    if ((regF & FLAG_H) != 0) { correction |= 0x06; }
                    if ((regF & FLAG_CY) != 0) { correction |= 0x60; newCy = FLAG_CY; }
                    a = (a - correction) & 0xFF;
                }
                regA = a;
                regF = (regF & FLAG_N) | newCy | (a == 0 ? FLAG_Z : 0);
                return 4;
            }

            // ── 0x28 JR Z,e ──
            case 0x28: {
                var e = _mem.readByte(pc) & 0xFF;
                pc = (pc + 1) & 0xFFFF;
                if ((regF & FLAG_Z) != 0) {
                    var off = (e & 0x80) != 0 ? e - 256 : e;
                    pc = (pc + off) & 0xFFFF;
                    return 12;
                }
                return 8;
            }

            // ── 0x29 ADD HL,HL ──
            case 0x29: { addHL(regHL()); return 8; }

            // ── 0x2A LDI A,(HL) ──
            case 0x2A: { var hl = regHL(); regA = _mem.readByte(hl) & 0xFF; setHL((hl + 1) & 0xFFFF); return 8; }

            // ── 0x2B DEC HL ──
            case 0x2B: setHL((regHL() - 1) & 0xFFFF); return 8;

            // ── 0x2C INC L ──
            case 0x2C: { var old = regL & 0xFF; regL = (old + 1) & 0xFF; regF = incFlags(old, regL) | (regF & FLAG_CY); return 4; }

            // ── 0x2D DEC L ──
            case 0x2D: { var old = regL & 0xFF; regL = (old - 1) & 0xFF; regF = decFlags(old, regL) | (regF & FLAG_CY); return 4; }

            // ── 0x2E LD L,n ──
            case 0x2E: regL = _mem.readByte(pc) & 0xFF; pc = (pc + 1) & 0xFFFF; return 8;

            // ── 0x2F CPL ──
            case 0x2F:
                regA = (~regA) & 0xFF;
                regF = (regF & (FLAG_Z | FLAG_CY)) | FLAG_N | FLAG_H;
                return 4;

            // ── 0x30 JR NC,e ──
            case 0x30: {
                var e = _mem.readByte(pc) & 0xFF;
                pc = (pc + 1) & 0xFFFF;
                if ((regF & FLAG_CY) == 0) {
                    var off = (e & 0x80) != 0 ? e - 256 : e;
                    pc = (pc + off) & 0xFFFF;
                    return 12;
                }
                return 8;
            }

            // ── 0x31 LD SP,nn ──
            case 0x31: {
                var lo = _mem.readByte(pc) & 0xFF;
                var hi = _mem.readByte(pc + 1) & 0xFF;
                pc = (pc + 2) & 0xFFFF;
                sp = (hi << 8) | lo;
                return 12;
            }

            // ── 0x32 LDD (HL),A ──
            case 0x32: { var hl = regHL(); _mem.writeByte(hl, regA & 0xFF); setHL((hl - 1) & 0xFFFF); return 8; }

            // ── 0x33 INC SP ──
            case 0x33: sp = (sp + 1) & 0xFFFF; return 8;

            // ── 0x34 INC (HL) ──
            case 0x34: {
                var hl = regHL();
                var old = _mem.readByte(hl) & 0xFF;
                var n = (old + 1) & 0xFF;
                _mem.writeByte(hl, n);
                regF = incFlags(old, n) | (regF & FLAG_CY);
                return 12;
            }

            // ── 0x35 DEC (HL) ──
            case 0x35: {
                var hl = regHL();
                var old = _mem.readByte(hl) & 0xFF;
                var n = (old - 1) & 0xFF;
                _mem.writeByte(hl, n);
                regF = decFlags(old, n) | (regF & FLAG_CY);
                return 12;
            }

            // ── 0x36 LD (HL),n ──
            case 0x36: {
                var n = _mem.readByte(pc) & 0xFF; pc = (pc + 1) & 0xFFFF;
                _mem.writeByte(regHL(), n);
                return 12;
            }

            // ── 0x37 SCF ──
            case 0x37:
                regF = (regF & FLAG_Z) | FLAG_CY;
                return 4;

            // ── 0x38 JR C,e ──
            case 0x38: {
                var e = _mem.readByte(pc) & 0xFF;
                pc = (pc + 1) & 0xFFFF;
                if ((regF & FLAG_CY) != 0) {
                    var off = (e & 0x80) != 0 ? e - 256 : e;
                    pc = (pc + off) & 0xFFFF;
                    return 12;
                }
                return 8;
            }

            // ── 0x39 ADD HL,SP ──
            case 0x39: { addHL(sp); return 8; }

            // ── 0x3A LDD A,(HL) ──
            case 0x3A: { var hl = regHL(); regA = _mem.readByte(hl) & 0xFF; setHL((hl - 1) & 0xFFFF); return 8; }

            // ── 0x3B DEC SP ──
            case 0x3B: sp = (sp - 1) & 0xFFFF; return 8;

            // ── 0x3C INC A ──
            case 0x3C: { var old = regA & 0xFF; regA = (old + 1) & 0xFF; regF = incFlags(old, regA) | (regF & FLAG_CY); return 4; }

            // ── 0x3D DEC A ──
            case 0x3D: { var old = regA & 0xFF; regA = (old - 1) & 0xFF; regF = decFlags(old, regA) | (regF & FLAG_CY); return 4; }

            // ── 0x3E LD A,n ──
            case 0x3E: regA = _mem.readByte(pc) & 0xFF; pc = (pc + 1) & 0xFFFF; return 8;

            // ── 0x3F CCF ──
            case 0x3F:
                regF = (regF & FLAG_Z) | ((regF & FLAG_CY) != 0 ? 0 : FLAG_CY);
                return 4;

            // ── 0x40-0x7F LD r,r (0x76 = HALT) ──
            case 0x40: case 0x41: case 0x42: case 0x43: case 0x44: case 0x45: case 0x47:
            case 0x48: case 0x49: case 0x4A: case 0x4B: case 0x4C: case 0x4D: case 0x4F:
            case 0x50: case 0x51: case 0x52: case 0x53: case 0x54: case 0x55: case 0x57:
            case 0x58: case 0x59: case 0x5A: case 0x5B: case 0x5C: case 0x5D: case 0x5F:
            case 0x60: case 0x61: case 0x62: case 0x63: case 0x64: case 0x65: case 0x67:
            case 0x68: case 0x69: case 0x6A: case 0x6B: case 0x6C: case 0x6D: case 0x6F:
            case 0x78: case 0x79: case 0x7A: case 0x7B: case 0x7C: case 0x7D: case 0x7F: {
                var dst = (opcode >> 3) & 7;
                var src = opcode & 7;
                writeReg8(dst, readReg8(src));
                return 4;
            }

            // ── LD r,(HL) — src or dst is 6 ──
            case 0x46: case 0x4E: case 0x56: case 0x5E:
            case 0x66: case 0x6E: case 0x7E: {
                // LD r,(HL)
                var dst = (opcode >> 3) & 7;
                writeReg8(dst, _mem.readByte(regHL()) & 0xFF);
                return 8;
            }

            case 0x70: case 0x71: case 0x72: case 0x73: case 0x74: case 0x75: case 0x77: {
                // LD (HL),r
                var src = opcode & 7;
                _mem.writeByte(regHL(), readReg8(src));
                return 8;
            }

            // ── 0x76 HALT ──
            case 0x76:
                halted = true;
                return 4;

            // ── 0x80-0x87 ADD A,r ──
            case 0x80: case 0x81: case 0x82: case 0x83: case 0x84: case 0x85: case 0x87: {
                var r = readReg8(opcode & 7); addA(r); return 4;
            }
            case 0x86: { addA(_mem.readByte(regHL()) & 0xFF); return 8; }

            // ── 0x88-0x8F ADC A,r ──
            case 0x88: case 0x89: case 0x8A: case 0x8B: case 0x8C: case 0x8D: case 0x8F: {
                var r = readReg8(opcode & 7); adcA(r); return 4;
            }
            case 0x8E: { adcA(_mem.readByte(regHL()) & 0xFF); return 8; }

            // ── 0x90-0x97 SUB r ──
            case 0x90: case 0x91: case 0x92: case 0x93: case 0x94: case 0x95: case 0x97: {
                var r = readReg8(opcode & 7); subA(r); return 4;
            }
            case 0x96: { subA(_mem.readByte(regHL()) & 0xFF); return 8; }

            // ── 0x98-0x9F SBC A,r ──
            case 0x98: case 0x99: case 0x9A: case 0x9B: case 0x9C: case 0x9D: case 0x9F: {
                var r = readReg8(opcode & 7); sbcA(r); return 4;
            }
            case 0x9E: { sbcA(_mem.readByte(regHL()) & 0xFF); return 8; }

            // ── 0xA0-0xA7 AND r ──
            case 0xA0: case 0xA1: case 0xA2: case 0xA3: case 0xA4: case 0xA5: case 0xA7: {
                andA(readReg8(opcode & 7)); return 4;
            }
            case 0xA6: { andA(_mem.readByte(regHL()) & 0xFF); return 8; }

            // ── 0xA8-0xAF XOR r ──
            case 0xA8: case 0xA9: case 0xAA: case 0xAB: case 0xAC: case 0xAD: case 0xAF: {
                xorA(readReg8(opcode & 7)); return 4;
            }
            case 0xAE: { xorA(_mem.readByte(regHL()) & 0xFF); return 8; }

            // ── 0xB0-0xB7 OR r ──
            case 0xB0: case 0xB1: case 0xB2: case 0xB3: case 0xB4: case 0xB5: case 0xB7: {
                orA(readReg8(opcode & 7)); return 4;
            }
            case 0xB6: { orA(_mem.readByte(regHL()) & 0xFF); return 8; }

            // ── 0xB8-0xBF CP r ──
            case 0xB8: case 0xB9: case 0xBA: case 0xBB: case 0xBC: case 0xBD: case 0xBF: {
                cpA(readReg8(opcode & 7)); return 4;
            }
            case 0xBE: { cpA(_mem.readByte(regHL()) & 0xFF); return 8; }

            // ── 0xC0 RET NZ ──
            case 0xC0:
                if ((regF & FLAG_Z) == 0) { pc = pop16(); return 20; }
                return 8;

            // ── 0xC1 POP BC ──
            case 0xC1: setBC(pop16()); return 12;

            // ── 0xC2 JP NZ,a16 ──
            case 0xC2: {
                var addr = readWord(pc); pc = (pc + 2) & 0xFFFF;
                if ((regF & FLAG_Z) == 0) { pc = addr; return 16; }
                return 12;
            }

            // ── 0xC3 JP nn ──
            case 0xC3: pc = readWord(pc); return 16;

            // ── 0xC4 CALL NZ,a16 ──
            case 0xC4: {
                var addr = readWord(pc); pc = (pc + 2) & 0xFFFF;
                if ((regF & FLAG_Z) == 0) { push16(pc); pc = addr; return 24; }
                return 12;
            }

            // ── 0xC5 PUSH BC ──
            case 0xC5: push16(regBC()); return 16;

            // ── 0xC6 ADD A,d8 ──
            case 0xC6: { var d = _mem.readByte(pc) & 0xFF; pc = (pc + 1) & 0xFFFF; addA(d); return 8; }

            // ── 0xC7 RST 0x00 ──
            case 0xC7: push16(pc); pc = 0x0000; return 16;

            // ── 0xC8 RET Z ──
            case 0xC8:
                if ((regF & FLAG_Z) != 0) { pc = pop16(); return 20; }
                return 8;

            // ── 0xC9 RET ──
            case 0xC9: pc = pop16(); return 16;

            // ── 0xCA JP Z,a16 ──
            case 0xCA: {
                var addr = readWord(pc); pc = (pc + 2) & 0xFFFF;
                if ((regF & FLAG_Z) != 0) { pc = addr; return 16; }
                return 12;
            }

            // ── 0xCB CB-prefix ──
            case 0xCB: return stepCB();

            // ── 0xCC CALL Z,a16 ──
            case 0xCC: {
                var addr = readWord(pc); pc = (pc + 2) & 0xFFFF;
                if ((regF & FLAG_Z) != 0) { push16(pc); pc = addr; return 24; }
                return 12;
            }

            // ── 0xCD CALL a16 ──
            case 0xCD: {
                var addr = readWord(pc); pc = (pc + 2) & 0xFFFF;
                push16(pc); pc = addr; return 24;
            }

            // ── 0xCE ADC A,d8 ──
            case 0xCE: { var d = _mem.readByte(pc) & 0xFF; pc = (pc + 1) & 0xFFFF; adcA(d); return 8; }

            // ── 0xCF RST 0x08 ──
            case 0xCF: push16(pc); pc = 0x0008; return 16;

            // ── 0xD0 RET NC ──
            case 0xD0:
                if ((regF & FLAG_CY) == 0) { pc = pop16(); return 20; }
                return 8;

            // ── 0xD1 POP DE ──
            case 0xD1: setDE(pop16()); return 12;

            // ── 0xD2 JP NC,a16 ──
            case 0xD2: {
                var addr = readWord(pc); pc = (pc + 2) & 0xFFFF;
                if ((regF & FLAG_CY) == 0) { pc = addr; return 16; }
                return 12;
            }

            // ── 0xD3 undefined ──
            case 0xD3: halted = true; return 4;

            // ── 0xD4 CALL NC,a16 ──
            case 0xD4: {
                var addr = readWord(pc); pc = (pc + 2) & 0xFFFF;
                if ((regF & FLAG_CY) == 0) { push16(pc); pc = addr; return 24; }
                return 12;
            }

            // ── 0xD5 PUSH DE ──
            case 0xD5: push16(regDE()); return 16;

            // ── 0xD6 SUB d8 ──
            case 0xD6: { var d = _mem.readByte(pc) & 0xFF; pc = (pc + 1) & 0xFFFF; subA(d); return 8; }

            // ── 0xD7 RST 0x10 ──
            case 0xD7: push16(pc); pc = 0x0010; return 16;

            // ── 0xD8 RET C ──
            case 0xD8:
                if ((regF & FLAG_CY) != 0) { pc = pop16(); return 20; }
                return 8;

            // ── 0xD9 RETI ──
            case 0xD9: pc = pop16(); ime = 1; return 16;

            // ── 0xDA JP C,a16 ──
            case 0xDA: {
                var addr = readWord(pc); pc = (pc + 2) & 0xFFFF;
                if ((regF & FLAG_CY) != 0) { pc = addr; return 16; }
                return 12;
            }

            // ── 0xDB undefined ──
            case 0xDB: halted = true; return 4;

            // ── 0xDC CALL C,a16 ──
            case 0xDC: {
                var addr = readWord(pc); pc = (pc + 2) & 0xFFFF;
                if ((regF & FLAG_CY) != 0) { push16(pc); pc = addr; return 24; }
                return 12;
            }

            // ── 0xDD undefined ──
            case 0xDD: halted = true; return 4;

            // ── 0xDE SBC A,d8 ──
            case 0xDE: { var d = _mem.readByte(pc) & 0xFF; pc = (pc + 1) & 0xFFFF; sbcA(d); return 8; }

            // ── 0xDF RST 0x18 ──
            case 0xDF: push16(pc); pc = 0x0018; return 16;

            // ── 0xE0 LDH (a8),A ──
            case 0xE0: {
                var a8 = _mem.readByte(pc) & 0xFF; pc = (pc + 1) & 0xFFFF;
                _mem.writeByte(0xFF00 + a8, regA & 0xFF);
                return 12;
            }

            // ── 0xE1 POP HL ──
            case 0xE1: setHL(pop16()); return 12;

            // ── 0xE2 LDH (C),A ──
            case 0xE2:
                _mem.writeByte(0xFF00 + (regC & 0xFF), regA & 0xFF);
                return 8;

            // ── 0xE3 0xE4 undefined ──
            case 0xE3: case 0xE4: halted = true; return 4;

            // ── 0xE5 PUSH HL ──
            case 0xE5: push16(regHL()); return 16;

            // ── 0xE6 AND d8 ──
            case 0xE6: { var d = _mem.readByte(pc) & 0xFF; pc = (pc + 1) & 0xFFFF; andA(d); return 8; }

            // ── 0xE7 RST 0x20 ──
            case 0xE7: push16(pc); pc = 0x0020; return 16;

            // ── 0xE8 ADD SP,s ──
            case 0xE8: {
                var e = _mem.readByte(pc) & 0xFF; pc = (pc + 1) & 0xFFFF;
                var off = (e & 0x80) != 0 ? e - 256 : e;
                var result = (sp + off) & 0xFFFF;
                var loSP = sp & 0xFF;
                var loR  = result & 0xFF;
                var cy = loR < loSP ? FLAG_CY : 0;
                var h  = (loR & 0x0F) < (loSP & 0x0F) ? FLAG_H : 0;
                regF = cy | h;
                sp = result;
                return 16;
            }

            // ── 0xE9 JP (HL) ──
            case 0xE9: pc = regHL(); return 4;

            // ── 0xEA LD (a16),A ──
            case 0xEA: {
                var addr = readWord(pc); pc = (pc + 2) & 0xFFFF;
                _mem.writeByte(addr, regA & 0xFF);
                return 16;
            }

            // ── 0xEB 0xEC 0xED undefined ──
            case 0xEB: case 0xEC: case 0xED: halted = true; return 4;

            // ── 0xEE XOR d8 ──
            case 0xEE: { var d = _mem.readByte(pc) & 0xFF; pc = (pc + 1) & 0xFFFF; xorA(d); return 8; }

            // ── 0xEF RST 0x28 ──
            case 0xEF: push16(pc); pc = 0x0028; return 16;

            // ── 0xF0 LDH A,(a8) ──
            case 0xF0: {
                var a8 = _mem.readByte(pc) & 0xFF; pc = (pc + 1) & 0xFFFF;
                regA = _mem.readByte(0xFF00 + a8) & 0xFF;
                return 12;
            }

            // ── 0xF1 POP AF ──
            case 0xF1: setAF(pop16()); return 12;

            // ── 0xF2 LDH A,(C) ──
            case 0xF2:
                regA = _mem.readByte(0xFF00 + (regC & 0xFF)) & 0xFF;
                return 8;

            // ── 0xF3 DI ──
            case 0xF3: ime = 0; return 4;

            // ── 0xF4 undefined ──
            case 0xF4: halted = true; return 4;

            // ── 0xF5 PUSH AF ──
            case 0xF5: push16(regAF()); return 16;

            // ── 0xF6 OR d8 ──
            case 0xF6: { var d = _mem.readByte(pc) & 0xFF; pc = (pc + 1) & 0xFFFF; orA(d); return 8; }

            // ── 0xF7 RST 0x30 ──
            case 0xF7: push16(pc); pc = 0x0030; return 16;

            // ── 0xF8 LD HL,SP+s ──
            case 0xF8: {
                var e = _mem.readByte(pc) & 0xFF; pc = (pc + 1) & 0xFFFF;
                var off = (e & 0x80) != 0 ? e - 256 : e;
                var result = (sp + off) & 0xFFFF;
                var loSP = sp & 0xFF;
                var loR  = result & 0xFF;
                var cy = loR < loSP ? FLAG_CY : 0;
                var h  = (loR & 0x0F) < (loSP & 0x0F) ? FLAG_H : 0;
                regF = cy | h;
                setHL(result);
                return 12;
            }

            // ── 0xF9 LD SP,HL ──
            case 0xF9: sp = regHL(); return 8;

            // ── 0xFA LD A,(a16) ──
            case 0xFA: {
                var addr = readWord(pc); pc = (pc + 2) & 0xFFFF;
                regA = _mem.readByte(addr) & 0xFF;
                return 16;
            }

            // ── 0xFB EI ──
            case 0xFB: ime = 1; return 4;

            // ── 0xFC 0xFD undefined ──
            case 0xFC: case 0xFD: halted = true; return 4;

            // ── 0xFE CP d8 ──
            case 0xFE: { var d = _mem.readByte(pc) & 0xFF; pc = (pc + 1) & 0xFFFF; cpA(d); return 8; }

            // ── 0xFF RST 0x38 ──
            case 0xFF: push16(pc); pc = 0x0038; return 16;

            default: halted = true; return 4;
        }
    }

    // ── CB-prefix opcodes ─────────────────────────────────────────────────
    function stepCB() {
        var cbop = _mem.readByte(pc) & 0xFF;
        pc = (pc + 1) & 0xFFFF;

        var reg = cbop & 7;
        var bit = (cbop >> 3) & 7;
        var isHL = (reg == 6);
        var cycles = isHL ? 16 : 8;

        if (cbop <= 0x07) {
            // RLC
            var v = readReg8(reg);
            var cy = (v >> 7) & 1;
            v = ((v << 1) | cy) & 0xFF;
            writeReg8(reg, v);
            regF = (v == 0 ? FLAG_Z : 0) | (cy != 0 ? FLAG_CY : 0);
        } else if (cbop <= 0x0F) {
            // RRC
            var v = readReg8(reg);
            var cy = v & 1;
            v = ((v >> 1) | (cy << 7)) & 0xFF;
            writeReg8(reg, v);
            regF = (v == 0 ? FLAG_Z : 0) | (cy != 0 ? FLAG_CY : 0);
        } else if (cbop <= 0x17) {
            // RL
            var v = readReg8(reg);
            var oldCy = (regF & FLAG_CY) != 0 ? 1 : 0;
            var newCy = (v >> 7) & 1;
            v = ((v << 1) | oldCy) & 0xFF;
            writeReg8(reg, v);
            regF = (v == 0 ? FLAG_Z : 0) | (newCy != 0 ? FLAG_CY : 0);
        } else if (cbop <= 0x1F) {
            // RR
            var v = readReg8(reg);
            var oldCy = (regF & FLAG_CY) != 0 ? 0x80 : 0;
            var newCy = v & 1;
            v = ((v >> 1) | oldCy) & 0xFF;
            writeReg8(reg, v);
            regF = (v == 0 ? FLAG_Z : 0) | (newCy != 0 ? FLAG_CY : 0);
        } else if (cbop <= 0x27) {
            // SLA
            var v = readReg8(reg);
            var cy = (v >> 7) & 1;
            v = (v << 1) & 0xFF;
            writeReg8(reg, v);
            regF = (v == 0 ? FLAG_Z : 0) | (cy != 0 ? FLAG_CY : 0);
        } else if (cbop <= 0x2F) {
            // SRA
            var v = readReg8(reg);
            var cy = v & 1;
            v = ((v >> 1) | (v & 0x80)) & 0xFF;
            writeReg8(reg, v);
            regF = (v == 0 ? FLAG_Z : 0) | (cy != 0 ? FLAG_CY : 0);
        } else if (cbop <= 0x37) {
            // SWAP
            var v = readReg8(reg);
            v = ((v & 0x0F) << 4) | ((v >> 4) & 0x0F);
            writeReg8(reg, v);
            regF = v == 0 ? FLAG_Z : 0;
        } else if (cbop <= 0x3F) {
            // SRL
            var v = readReg8(reg);
            var cy = v & 1;
            v = (v >> 1) & 0xFF;
            writeReg8(reg, v);
            regF = (v == 0 ? FLAG_Z : 0) | (cy != 0 ? FLAG_CY : 0);
        } else if (cbop <= 0x7F) {
            // BIT b,r
            var v = readReg8(reg);
            var testBit = (v >> bit) & 1;
            regF = (testBit == 0 ? FLAG_Z : 0) | FLAG_H | (regF & FLAG_CY);
            // BIT on (HL) costs 12, not 16
            cycles = isHL ? 12 : 8;
        } else if (cbop <= 0xBF) {
            // RES b,r
            var v = readReg8(reg);
            writeReg8(reg, v & ~(1 << bit));
        } else {
            // SET b,r
            var v = readReg8(reg);
            writeReg8(reg, v | (1 << bit));
        }

        return cycles;
    }

    // ── ALU helpers ────────────────────────────────────────────────────────

    function addA(r) {
        var a = regA & 0xFF;
        var result = (a + r) & 0xFF;
        regF = (result == 0 ? FLAG_Z : 0)
             | (result < a ? FLAG_CY : 0)
             | ((result & 0x0F) < (a & 0x0F) ? FLAG_H : 0);
        regA = result;
    }

    function adcA(r) {
        var a = regA & 0xFF;
        var cy = (regF & FLAG_CY) != 0 ? 1 : 0;
        var result = (a + r + cy) & 0xFF;
        regF = (result == 0 ? FLAG_Z : 0)
             | (result < a ? FLAG_CY : 0)
             | ((result & 0x0F) < (a & 0x0F) ? FLAG_H : 0);
        regA = result;
    }

    function subA(r) {
        var a = regA & 0xFF;
        var result = (a - r) & 0xFF;
        regF = FLAG_N
             | (result == 0 ? FLAG_Z : 0)
             | (result > a ? FLAG_CY : 0)
             | ((result & 0x0F) > (a & 0x0F) ? FLAG_H : 0);
        regA = result;
    }

    function sbcA(r) {
        var a = regA & 0xFF;
        var cy = (regF & FLAG_CY) != 0 ? 1 : 0;
        var result = (a - r - cy) & 0xFF;
        regF = FLAG_N
             | (result == 0 ? FLAG_Z : 0)
             | (result > a ? FLAG_CY : 0)
             | ((result & 0x0F) > (a & 0x0F) ? FLAG_H : 0);
        regA = result;
    }

    function andA(r) {
        regA = (regA & r) & 0xFF;
        regF = (regA == 0 ? FLAG_Z : 0) | FLAG_H;
    }

    function xorA(r) {
        regA = (regA ^ r) & 0xFF;
        regF = regA == 0 ? FLAG_Z : 0;
    }

    function orA(r) {
        regA = (regA | r) & 0xFF;
        regF = regA == 0 ? FLAG_Z : 0;
    }

    function cpA(r) {
        var a = regA & 0xFF;
        var result = (a - r) & 0xFF;
        regF = FLAG_N
             | (result == 0 ? FLAG_Z : 0)
             | (result > a ? FLAG_CY : 0)
             | ((result & 0x0F) > (a & 0x0F) ? FLAG_H : 0);
    }

    function addHL(rr) {
        var hl = regHL();
        var result = (hl + rr) & 0xFFFF;
        var hiHL = (hl >> 8) & 0xFF;
        var hiR  = (result >> 8) & 0xFF;
        regF = (regF & FLAG_Z)
             | (hiR < hiHL ? FLAG_CY : 0)
             | ((hiR & 0x0F) < (hiHL & 0x0F) ? FLAG_H : 0);
        setHL(result);
    }

    // ── INC/DEC flag helpers ───────────────────────────────────────────────
    function incFlags(old, newVal) {
        return ((newVal == 0 ? FLAG_Z : 0))
             | ((newVal & 0x0F) < (old & 0x0F) ? FLAG_H : 0);
    }

    function decFlags(old, newVal) {
        return FLAG_N
             | (newVal == 0 ? FLAG_Z : 0)
             | ((newVal & 0x0F) > (old & 0x0F) ? FLAG_H : 0);
    }

    // ── 16-bit read helper ─────────────────────────────────────────────────
    function readWord(addr) {
        var lo = _mem.readByte(addr) & 0xFF;
        var hi = _mem.readByte((addr + 1) & 0xFFFF) & 0xFF;
        return (hi << 8) | lo;
    }
}
