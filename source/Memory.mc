using Toybox.System as Sys;

class Memory {
    var rom ;
    var vram;
    var wram;
    var hram;
    var oam ;

    var _interrupts;
    var _ppu       ;
    var _gbTimer   ;
    var _joypad    ;
    var _sound     ;

    function initialize(romData, interrupts) {
        rom  = romData;
        vram = new [8192]b;
        wram = new [8192]b;
        hram = new [127]b;
        oam  = new [160]b;
        _interrupts = interrupts;
    }

    function setPpu(ppu)        { _ppu = ppu; }
    function setTimer(t)    { _gbTimer = t; }
    function setJoypad(j)    { _joypad = j; }
    function setSound(s)      { _sound = s; }

    function readByte(addr) {
        addr = addr & 0xFFFF;
        if (addr <= 0x7FFF) {
            return rom[addr] & 0xFF;
        } else if (addr <= 0x9FFF) {
            return vram[addr - 0x8000] & 0xFF;
        } else if (addr <= 0xBFFF) {
            return 0xFF;
        } else if (addr <= 0xDFFF) {
            return wram[addr - 0xC000] & 0xFF;
        } else if (addr <= 0xFDFF) {
            return wram[(addr - 0xE000) & 0x1FFF] & 0xFF;
        } else if (addr <= 0xFE9F) {
            return oam[addr - 0xFE00] & 0xFF;
        } else if (addr <= 0xFEFF) {
            return 0xFF;
        } else if (addr <= 0xFF7F) {
            return readIo(addr);
        } else if (addr <= 0xFFFE) {
            return hram[addr - 0xFF80] & 0xFF;
        } else {
            return _interrupts.ieRead() & 0xFF;
        }
    }

    function writeByte(addr, val) {
        addr = addr & 0xFFFF;
        val  = val  & 0xFF;
        if (addr <= 0x7FFF) {
            // MBC0: ROM writes are ignored
        } else if (addr <= 0x9FFF) {
            vram[addr - 0x8000] = val;
        } else if (addr <= 0xBFFF) {
            // no cart RAM
        } else if (addr <= 0xDFFF) {
            wram[addr - 0xC000] = val;
        } else if (addr <= 0xFDFF) {
            wram[(addr - 0xE000) & 0x1FFF] = val;
        } else if (addr <= 0xFE9F) {
            oam[addr - 0xFE00] = val;
        } else if (addr <= 0xFEFF) {
            // unusable
        } else if (addr <= 0xFF7F) {
            writeIo(addr, val);
        } else if (addr <= 0xFFFE) {
            hram[addr - 0xFF80] = val;
        } else {
            _interrupts.ieWrite(val);
        }
    }

    function readWord(addr) {
        return readByte(addr) | (readByte((addr + 1) & 0xFFFF) << 8);
    }

    function writeWord(addr, val) {
        writeByte(addr,               val & 0xFF);
        writeByte((addr + 1) & 0xFFFF, (val >> 8) & 0xFF);
    }

    function readIo(addr) {
        if (addr == 0xFF00) {
            return _joypad.read();
        } else if (addr >= 0xFF04 && addr <= 0xFF07) {
            return _gbTimer.read(addr);
        } else if (addr == 0xFF0F) {
            return _interrupts.ifRead();
        } else if (addr >= 0xFF10 && addr <= 0xFF3F) {
            return _sound.read(addr);
        } else if (addr == 0xFF40 || addr == 0xFF41 || addr == 0xFF42 ||
                   addr == 0xFF43 || addr == 0xFF44 || addr == 0xFF45 ||
                   addr == 0xFF46 || addr == 0xFF47 || addr == 0xFF48 ||
                   addr == 0xFF49 || addr == 0xFF4A || addr == 0xFF4B) {
            return _ppu.readReg(addr);
        }
        return 0xFF;
    }

    function writeIo(addr, val) {
        if (addr == 0xFF00) {
            _joypad.write(val);
        } else if (addr == 0xFF01 || addr == 0xFF02) {
            // serial — ignore
        } else if (addr >= 0xFF04 && addr <= 0xFF07) {
            _gbTimer.write(addr, val);
        } else if (addr == 0xFF0F) {
            _interrupts.ifWrite(val);
        } else if (addr >= 0xFF10 && addr <= 0xFF3F) {
            _sound.write(addr, val);
        } else if (addr == 0xFF40 || addr == 0xFF41 || addr == 0xFF42 ||
                   addr == 0xFF43 || addr == 0xFF44 || addr == 0xFF45 ||
                   addr == 0xFF46 || addr == 0xFF47 || addr == 0xFF48 ||
                   addr == 0xFF49 || addr == 0xFF4A || addr == 0xFF4B) {
            _ppu.writeReg(addr, val);
        }
        // all other I/O ports silently ignored
    }
}
