# GarminBoy Implementation Plan

## Architecture Summary

Every C source file in tinygb becomes one Monkey C class. No raw pointers, no unions, no function pointers. All memory is `ByteArray`. Opcode dispatch is a `switch` statement. The game loop is a `Timer.repeat(16)` callback.

### Memory Budget

| Block | Size | Notes |
|---|---|---|
| ROM (Tetris, MBC0) | 32 KB | ByteArray from Rez resource |
| VRAM | 8 KB | ByteArray in Memory class |
| WRAM | 8 KB | ByteArray in Memory class |
| HRAM | 127 bytes | ByteArray in Memory class |
| OAM | 160 bytes | ByteArray in Memory class |
| Framebuffer (160×144, palette indices) | 23 KB | ByteArray in Ppu class |
| **Total** | **~72 KB** | Well within 1MB heap |

Key redesign from tinygb: the framebuffer stores **palette indices (0–3)**, not ARGB values. Color expansion happens only at blit time in `onUpdate()`. The 256×256 background buffer used by tinygb (`display.c:172`) is eliminated entirely.

---

## File Structure

```
GarminBoy/
  manifest.xml
  monkey.jungle
  source/
    GarminBoyApp.mc       — AppBase, constructs Emulator
    GarminBoyView.mc      — onUpdate(), blits framebuffer to DC
    GarminBoyDelegate.mc  — onKey(), maps Garmin buttons to GB joypad
    Emulator.mc           — coordinator, owns the Timer.repeat loop
    Rom.mc                — loads ByteArray from chunked Rez string resources
    Memory.mc             — 64KB address space router
    Cpu.mc                — LR35902, switch-based dispatch
    Ppu.mc                — scanline renderer, direct tile lookup
    Timer_.mc             — DIV/TIMA/TMA
    Interrupts.mc         — IF/IE registers
    Joypad.mc             — button state register
    Sound.mc              — register stub, no audio output
  resources/
    resources.xml         — declares 8×4KB ROM chunk strings
    rom/
      tetris.bin          — Tetris ROM binary
```

---

## Phase 1 — Project Scaffold

**Files:** `manifest.xml`, `monkey.jungle`, `GarminBoyApp.mc`

Declare the app as type `"watchapp"` (not widget or watchface) in `manifest.xml` — this is required for unrestricted physical button access on the Fenix 7x Pro. `GarminBoyApp.onStart()` constructs the `Emulator`; `getInitialView()` returns `[view, delegate]`.

```xml
<!-- manifest.xml (excerpt) -->
<iq:application type="watchapp" minSdkVersion="3.2.0" targetSdkVersion="4.2.4">
  <iq:products>
    <iq:product id="fenix7xpro"/>
  </iq:products>
</iq:application>
```

```monkeyc
// GarminBoyApp.mc
class GarminBoyApp extends Application.AppBase {
    var _emulator as Emulator;

    function initialize() {
        AppBase.initialize();
    }

    function onStart(state as Dictionary?) as Void {
        _emulator = new Emulator();
        _emulator.init();
    }

    function getInitialView() as [Views] or [Views, InputDelegates] {
        var view = new GarminBoyView(_emulator);
        var delegate = new GarminBoyDelegate(_emulator.getJoypad());
        return [view, delegate];
    }
}
```

**Gotcha:** Construct the `Emulator` in `onStart()`, not `initialize()`. ByteArray allocations must happen after the app sandbox is fully initialized.

---

## Phase 2 — ROM Loading

**Reference:** `core/memory.c:31-146`, `platform/sdl/main.c:199-224`
**Files:** `resources/resources.xml`, `resources/rom/tetris.bin`, `Rom.mc`

Connect IQ has no generic binary Rez type. The approach: split the 32KB Tetris ROM into **8 chunks of 4KB each**, each encoded as a Latin-1 `<string>` resource in `resources.xml`. `Rom.mc` concatenates them into a single 32KB `ByteArray` at startup.

```xml
<!-- resources/resources.xml -->
<resources>
  <string id="RomChunk0">...(4096 Latin-1 chars)...</string>
  <string id="RomChunk1">...</string>
  <!-- 8 chunks total -->
  <string id="RomChunk7">...</string>
</resources>
```

```monkeyc
// Rom.mc
class Rom {
    var data as ByteArray;

    function initialize() {
        data = new [32768]b;
        var chunkIds = [
            Rez.Strings.RomChunk0, Rez.Strings.RomChunk1,
            Rez.Strings.RomChunk2, Rez.Strings.RomChunk3,
            Rez.Strings.RomChunk4, Rez.Strings.RomChunk5,
            Rez.Strings.RomChunk6, Rez.Strings.RomChunk7
        ];
        var offset = 0;
        for (var i = 0; i < 8; i++) {
            var s = WatchUi.loadResource(chunkIds[i]) as String;
            var bytes = s.toUtf8Array();
            for (var j = 0; j < bytes.size(); j++) {
                data[offset + j] = bytes[j] & 0xFF;
            }
            offset += 4096;
        }
    }
}
```

**Gotcha:** Latin-1 encoding must be used when generating the resource strings — UTF-8 will corrupt bytes above 0x7F. A build-time script must convert `tetris.bin` to Latin-1 encoded `<string>` chunks. Always mask `& 0xFF` when reading back from ByteArray (values ≥ 0x80 come back as negative integers in Monkey C).

---

## Phase 3 — Memory Map

**Reference:** `core/memory.c` (entire file)
**Files:** `Memory.mc`

Central class that all subsystems call. Owns ByteArrays for VRAM, WRAM, HRAM, OAM. Holds a reference to the ROM ByteArray. I/O registers are owned by their respective subsystem classes.

```monkeyc
// Memory.mc
class Memory {
    var rom  as ByteArray;          // 32768 bytes, reference from Rom
    var vram as ByteArray;          // new [8192]b   0x8000-0x9FFF
    var wram as ByteArray;          // new [8192]b   0xC000-0xDFFF
    var hram as ByteArray;          // new [127]b    0xFF80-0xFFFE
    var oam  as ByteArray;          // new [160]b    0xFE00-0xFE9F
    var ie   as Number = 0;         // 0xFFFF interrupt enable

    var _ppu        as Ppu;
    var _timer      as GbTimer;
    var _joypad     as Joypad;
    var _sound      as Sound;
    var _interrupts as Interrupts;

    function readByte(addr as Number) as Number {
        addr = addr & 0xFFFF;
        if      (addr <= 0x7FFF) { return rom[addr] & 0xFF; }
        else if (addr <= 0x9FFF) { return vram[addr - 0x8000] & 0xFF; }
        else if (addr <= 0xBFFF) { return 0xFF; }                          // no cart RAM
        else if (addr <= 0xDFFF) { return wram[addr - 0xC000] & 0xFF; }
        else if (addr <= 0xFDFF) { return wram[(addr - 0xE000) & 0x1FFF] & 0xFF; } // echo
        else if (addr <= 0xFE9F) { return oam[addr - 0xFE00] & 0xFF; }
        else if (addr <= 0xFEFF) { return 0xFF; }                          // unusable
        else if (addr <= 0xFF7F) { return readIo(addr); }
        else if (addr <= 0xFFFE) { return hram[addr - 0xFF80] & 0xFF; }
        else                     { return ie & 0xFF; }
    }

    function writeByte(addr as Number, val as Number) as Void {
        addr = addr & 0xFFFF;
        val  = val  & 0xFF;
        if      (addr <= 0x7FFF) { /* ROM: MBC0 ignore writes */ }
        else if (addr <= 0x9FFF) { vram[addr - 0x8000] = val; }
        else if (addr <= 0xBFFF) { /* no cart RAM */ }
        else if (addr <= 0xDFFF) { wram[addr - 0xC000] = val; }
        else if (addr <= 0xFDFF) { wram[(addr - 0xE000) & 0x1FFF] = val; }
        else if (addr <= 0xFE9F) { oam[addr - 0xFE00] = val; }
        else if (addr <= 0xFEFF) { /* unusable */ }
        else if (addr <= 0xFF7F) { writeIo(addr, val); }
        else if (addr <= 0xFFFE) { hram[addr - 0xFF80] = val; }
        else                     { ie = val; }
    }

    function readWord(addr as Number) as Number {
        return (readByte(addr + 1) << 8) | readByte(addr);
    }

    function writeWord(addr as Number, val as Number) as Void {
        writeByte(addr,     val & 0xFF);
        writeByte(addr + 1, (val >> 8) & 0xFF);
    }
}
```

`readIo()` / `writeIo()` dispatch to `_ppu`, `_timer`, `_joypad`, `_sound`, `_interrupts` by address range, mirroring tinygb's `read_io()` / `write_io()`. OAM DMA (write to `0xFF46`) triggers a 160-byte copy inside `writeIo()`.

**Gotcha:** Never name the timer class `Timer` — it collides with `Toybox.Timer`. Use `GbTimer` throughout.

---

## Phase 4 — CPU

**Reference:** `core/cpu.c` (entire file), `include/tinygb.h` (cpu_t struct, flag constants)
**Files:** `Cpu.mc`

### Register Layout

```monkeyc
class Cpu {
    // 8-bit registers (stored flat; pairs assembled via bit ops)
    var regA as Number = 0;
    var regF as Number = 0;   // flags in bits 7,6,5,4 only — low nibble always 0
    var regB as Number = 0;
    var regC as Number = 0;
    var regD as Number = 0;
    var regE as Number = 0;
    var regH as Number = 0;
    var regL as Number = 0;

    var sp      as Number  = 0;
    var pc      as Number  = 0;
    var ime     as Number  = 0;
    var halted  as Boolean = false;

    const FLAG_Z  = 0x80;
    const FLAG_N  = 0x40;
    const FLAG_H  = 0x20;
    const FLAG_CY = 0x10;

    var _mem        as Memory;
    var _interrupts as Interrupts;
}
```

### Initialization (from `cpu_start()`)

```monkeyc
function start() as Void {
    regA = 0x01; regF = 0xB0;
    regB = 0x00; regC = 0x13;
    regD = 0x00; regE = 0xD8;
    regH = 0x01; regL = 0x4D;
    sp = 0xFFFE;
    pc = 0x0100;
    ime = 0;
    halted = false;
}
```

### Opcode Dispatch

The 256-entry function pointer table in tinygb (`cpu.c:41-42`) becomes a `switch` in `step()`. Returns cycles consumed.

```monkeyc
function step() as Number {
    handleInterrupts();
    if (halted) { return 4; }

    var opcode = _mem.readByte(pc) & 0xFF;
    pc = (pc + 1) & 0xFFFF;

    switch (opcode) {
        case 0x00: return op_NOP();
        case 0x01: return op_LD_BC_nn();
        // ... all 256 cases ...
        case 0xCB: return stepCB();
        default:
            halted = true;
            return 4;
    }
}
```

`stepCB()` reads the next byte and dispatches a second switch for the 0xCB-prefix instructions (`ex_opcodes[]` in tinygb).

### 16-bit Register Access Pattern

Monkey C has no unions. All 16-bit register access uses explicit bit operations:

```monkeyc
// Read HL as 16-bit
function regHL() as Number { return ((regH & 0xFF) << 8) | (regL & 0xFF); }

// Write HL from 16-bit
function setHL(val as Number) as Void {
    regH = (val >> 8) & 0xFF;
    regL = val & 0xFF;
}
```

Same pattern for BC, DE, AF.

### Helper Methods

```monkeyc
function push16(val as Number) as Void {
    sp = (sp - 1) & 0xFFFF;
    _mem.writeByte(sp, (val >> 8) & 0xFF);
    sp = (sp - 1) & 0xFFFF;
    _mem.writeByte(sp, val & 0xFF);
}

function pop16() as Number {
    var lo = _mem.readByte(sp) & 0xFF;
    sp = (sp + 1) & 0xFFFF;
    var hi = _mem.readByte(sp) & 0xFF;
    sp = (sp + 1) & 0xFFFF;
    return (hi << 8) | lo;
}
```

### Interrupt Handling (from `cpu_cycle():169-197`)

```monkeyc
function handleInterrupts() as Void {
    var pending = _interrupts.io_if & _interrupts.io_ie & 0x1F;
    if (ime != 0 && pending != 0) {
        for (var i = 0; i <= 4; i++) {
            if ((pending & (1 << i)) != 0) {
                _interrupts.io_if &= ~(1 << i);
                ime = 0;
                halted = false;
                push16(pc);
                pc = (i << 3) + 0x40;
                return;
            }
        }
    }
    if (halted && pending != 0) {
        halted = false;
    }
}
```

### Tetris Opcode Priority List

Implement these first — they cover ~95% of what Tetris executes before the title screen:

`NOP`, `LD r,n`, `LD r,r`, `LD r,(HL)`, `LD (HL),r`, `LD rr,nn`, `LD (nn),SP`, `LD A,(nn)`, `LD (nn),A`, `LDH`, `INC/DEC r`, `INC/DEC rr`, `ADD/SUB/SBC/ADC/AND/OR/XOR/CP`, `JP nn`, `JP cc,nn`, `JR e`, `JR cc,e`, `CALL nn`, `RET`, `RETI`, `PUSH/POP`, `DI/EI`, `HALT`, `RST`, `DAA`, `CPL`, `SCF/CCF`, `RLCA/RRCA/RLA/RRA`, and all CB-prefix bit ops (`BIT`, `RES`, `SET`, `RL`, `RR`, `SLA`, `SRA`, `SRL`, `SWAP`).

**Gotchas:**
- Monkey C integers are 32-bit signed and never wrap — all arithmetic must be explicitly masked: `(a + b) & 0xFF` for 8-bit, `& 0xFFFF` for 16-bit.
- The F register's low nibble is always zero — mask on any write: `regF = val & 0xF0`.
- Monkey C `switch` does not fall through between cases (unlike C). Each case must be self-contained.
- Half-carry flag: `((a & 0xF) + (b & 0xF)) > 0xF` for addition, `((a & 0xF) - (b & 0xF)) < 0` for subtraction.

---

## Phase 5 — Timer and Interrupts

**Reference:** `core/timer.c`, `core/interrupts.c`, `include/ioports.h`
**Files:** `Interrupts.mc`, `Timer_.mc` → rename to `GbTimer.mc`

### Interrupts.mc

```monkeyc
class Interrupts {
    var io_if as Number = 0;   // 0xFF0F
    var io_ie as Number = 0;   // 0xFFFF

    const INT_VBLANK = 0x01;
    const INT_STAT   = 0x02;
    const INT_TIMER  = 0x04;
    const INT_SERIAL = 0x08;
    const INT_JOYPAD = 0x10;

    function request(bit as Number) as Void { io_if |= bit; }
    function read()  as Number { return io_if | 0xE0; }
    function write(val as Number) as Void { io_if = val & 0xFF; }
}
```

### GbTimer.mc

TIMA frequency thresholds (in CPU machine cycles, where each `cpu.step()` returns machine cycles):

| TAC[1:0] | Frequency | Cycles/tick |
|---|---|---|
| 00 | 4096 Hz | 512 |
| 01 | 262144 Hz | 8 |
| 10 | 65536 Hz | 32 |
| 11 | 16384 Hz | 128 |

DIV increments every 256 machine cycles. When TIMA overflows, reload from TMA and request `INT_TIMER`.

---

## Phase 6 — PPU (Scanline Renderer)

**Reference:** `core/display.c` — state machine and register logic only. The `render_line()` + `plot_bg_tile()` rendering approach is NOT used.
**Files:** `Ppu.mc`

### Why tinygb's renderer cannot be used

tinygb allocates a 256×256 ARGB framebuffer (`display.c:172`: `background_buffer = calloc(256*256, 4)` = 262KB) and renders all background tiles into it, then copies the SCX/SCY viewport. This requires 262KB just for the background buffer — too expensive for the Garmin heap.

### GarminBoy's approach: direct scanline rendering

For each pixel at `(screenX, LY)`, compute the tile index and pixel position on the fly from VRAM:

```monkeyc
// Ppu.mc (renderBgLine excerpt)
function renderBgLine(lineBase as Number) as Void {
    var mapBase = ((lcdc & 0x08) != 0) ? 0x1C00 : 0x1800;
    var signedAddressing = ((lcdc & 0x10) == 0);
    var bgY = (ly + scy) & 0xFF;
    var tileRow = bgY >> 3;
    var pixelRowInTile = bgY & 7;

    for (var screenX = 0; screenX < 160; screenX++) {
        var bgX = (screenX + scx) & 0xFF;
        var tileCol = bgX >> 3;
        var pixelColInTile = bgX & 7;

        var tileIndex = _mem.vram[mapBase + (tileRow * 32) + tileCol] & 0xFF;

        var tileDataAddr;
        if (signedAddressing) {
            var si = tileIndex; if ((si & 0x80) != 0) { si -= 256; }
            tileDataAddr = 0x1000 + (si * 16);
        } else {
            tileDataAddr = tileIndex * 16;
        }

        var rowAddr = tileDataAddr + (pixelRowInTile * 2);
        var lo = _mem.vram[rowAddr]     & 0xFF;
        var hi = _mem.vram[rowAddr + 1] & 0xFF;

        var bit = 7 - pixelColInTile;
        var colorIdx = (((hi >> bit) & 1) << 1) | ((lo >> bit) & 1);
        var paletteColor = (bgp >> (colorIdx * 2)) & 3;

        framebuffer[lineBase + screenX] = paletteColor;
    }
}
```

### PPU State

```monkeyc
class Ppu {
    var lcdc as Number = 0x91;
    var stat as Number = 0;
    var scy  as Number = 0;
    var scx  as Number = 0;
    var ly   as Number = 0;
    var lyc  as Number = 0;
    var bgp  as Number = 0xFC;
    var obp0 as Number = 0xFF;
    var obp1 as Number = 0xFF;
    var wy   as Number = 0;
    var wx   as Number = 0;

    var framebuffer as ByteArray;   // new [23040]b — palette indices, not colors
    var _frameReady as Boolean = false;
    var _cycles     as Number  = 0;
    var _lineRendered as Boolean = false;
    var _windowLineCounter as Number = 0;

    var palette as Array = [0xC4CFA1, 0x8B956D, 0x4D533C, 0x1F1F1F];

    var _mem        as Memory;
    var _interrupts as Interrupts;
}
```

### Rendering Layers (per scanline)

1. **BG layer** — `renderBgLine()` as above (LCDC bit 0 enables)
2. **Window layer** — `renderWindowLine()` if LCDC bit 5 set and `wy <= ly`. Uses its own internal line counter `_windowLineCounter` (reset at VBlank, not per-scanline).
3. **Sprite layer** — `renderSpriteLine()` if LCDC bit 1 set. Iterate all 40 OAM entries, render sprites whose Y range covers `ly`. Respect flip flags, OBP0/OBP1 palette, and priority bit.

### Mode State Machine (`display_cycle()` port)

Modes per scanline (456 cycles total per line):
- **Mode 2 (OAM scan):** cycles 0–79
- **Mode 3 (drawing):** cycles 80–251 — `renderLine()` fires once here
- **Mode 0 (HBlank):** cycles 252–455
- **Mode 1 (VBlank):** lines 144–153, 456 cycles each

At line 144: request `INT_VBLANK`, set `_frameReady = true`, reset `_windowLineCounter`.

### OAM DMA

When write to `0xFF46` occurs (handled in `Memory.writeIo()`): set `_ppu.dma` to the value. On the next `ppu.cycle()` call, perform the 160-byte copy from `(dma << 8)` into `_mem.oam[]`.

**Gotchas:**
- `_windowLineCounter` resets at frame boundary (VBlank start), not per-line.
- VRAM access during mode 3 should be blocked per spec; for v1 skip this restriction.
- Sprite priority: sprites with lower OAM index win ties. Iterate OAM in reverse order so index 0 overwrites last.
- The inner `renderBgLine()` pixel loop is the hottest path in the entire emulator. No method calls inside it.

---

## Phase 7 — Joypad

**Reference:** `core/joypad.c` (entire file)
**Files:** `Joypad.mc`, `GarminBoyDelegate.mc`

### Button Mapping — Fenix 7x Pro

| Garmin Button | Monkey C Constant | GB Button |
|---|---|---|
| UP | `WatchUi.KEY_UP` | D-Pad Up |
| DOWN | `WatchUi.KEY_DOWN` | D-Pad Down |
| START/STOP | `WatchUi.KEY_START` | A |
| LAP/RESET | `WatchUi.KEY_LAP` | B |
| BACK | `WatchUi.KEY_ESC` | Select |
| LIGHT (long press) | `WatchUi.KEY_LIGHT` | Start |

If `KEY_LIGHT` is unavailable in the target SDK, map **long press UP** to Start using `onHold()`.

### Joypad.mc

```monkeyc
class Joypad {
    var pressedKeys as Number = 0;
    var _selection  as Number = 0;
    var _interrupts as Interrupts;

    const BUTTON_A      = 0x01;
    const BUTTON_B      = 0x02;
    const BUTTON_SELECT = 0x04;
    const BUTTON_START  = 0x08;
    const BUTTON_RIGHT  = 0x10;
    const BUTTON_LEFT   = 0x20;
    const BUTTON_UP     = 0x40;
    const BUTTON_DOWN   = 0x80;

    function read() as Number {
        if (_selection == 1) { return (~(pressedKeys >> 4)) & 0x0F; }
        if (_selection == 0) { return (~pressedKeys) & 0x0F; }
        return 0x0F;
    }

    function write(val as Number) as Void {
        val = (~val) & 0x30;
        if      ((val & 0x20) != 0) { _selection = 0; }  // buttons
        else if ((val & 0x10) != 0) { _selection = 1; }  // directions
        else                        { _selection = 2; }
    }

    function keyDown(gbKey as Number) as Void {
        pressedKeys |= gbKey;
        _interrupts.request(Interrupts.INT_JOYPAD);
    }

    function keyUp(gbKey as Number) as Void {
        pressedKeys &= ~gbKey;
    }
}
```

### GarminBoyDelegate.mc

```monkeyc
class GarminBoyDelegate extends WatchUi.InputDelegate {
    var _joypad as Joypad;

    function initialize(joypad as Joypad) {
        InputDelegate.initialize();
        _joypad = joypad;
    }

    function onKey(keyEvent as WatchUi.KeyEvent) as Boolean {
        var key  = keyEvent.getKey();
        var type = keyEvent.getType();
        var isDown = (type == WatchUi.PRESS_TYPE_DOWN);

        var gbKey = 0;
        switch (key) {
            case WatchUi.KEY_UP:    gbKey = Joypad.BUTTON_UP;     break;
            case WatchUi.KEY_DOWN:  gbKey = Joypad.BUTTON_DOWN;   break;
            case WatchUi.KEY_START: gbKey = Joypad.BUTTON_A;      break;
            case WatchUi.KEY_LAP:   gbKey = Joypad.BUTTON_B;      break;
            case WatchUi.KEY_ESC:   gbKey = Joypad.BUTTON_SELECT; break;
            default: return false;
        }

        if (isDown) { _joypad.keyDown(gbKey); }
        else        { _joypad.keyUp(gbKey); }
        return true;
    }
}
```

**Gotcha:** Monkey C is single-threaded — the timer callback and key events are serialized. No locking required.

---

## Phase 8 — Main Loop / Emulator Coordinator

**Files:** `Emulator.mc`

### Cycle Budget

- GB CPU: 4,194,304 cycles/second
- Timer fires every 16ms → ~67,109 cycles per tick (~0.954 frames)
- This slightly underruns one full frame (70,224 cycles) — the timer fires fast enough to compensate

### Emulator.mc

```monkeyc
class Emulator {
    var _mem        as Memory;
    var _cpu        as Cpu;
    var _ppu        as Ppu;
    var _gbTimer    as GbTimer;
    var _joypad     as Joypad;
    var _sound      as Sound;
    var _interrupts as Interrupts;
    var _rom        as Rom;
    var _loop       as Toybox.Timer.Timer;

    const CYCLES_PER_TICK = 67109;

    function initialize() {}

    function init() as Void {
        _interrupts = new Interrupts();
        _rom        = new Rom();
        _mem        = new Memory(_rom.data, _interrupts);
        _ppu        = new Ppu(_mem, _interrupts);
        _gbTimer    = new GbTimer(_interrupts);
        _joypad     = new Joypad(_interrupts);
        _sound      = new Sound();
        _cpu        = new Cpu(_mem, _interrupts);

        _mem.setPpu(_ppu);
        _mem.setTimer(_gbTimer);
        _mem.setJoypad(_joypad);
        _mem.setSound(_sound);

        _cpu.start();
        _ppu.start();
        _gbTimer.start();
        _sound.start();

        _loop = new Toybox.Timer.Timer();
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

    function getJoypad() as Joypad { return _joypad; }
    function getFramebuffer() as ByteArray { return _ppu.framebuffer; }
    function getPalette() as Array { return _ppu.palette; }
}
```

### Sound Stub

```monkeyc
class Sound {
    // Store all NR1x-NR5x and wave RAM registers so ROM writes don't crash.
    // No audio output — Connect IQ has no PCM playback API.
    function start()  as Void { /* initialize registers per tinygb sound_start() */ }
    function read(addr as Number)  as Number { /* return stored register value */ }
    function write(addr as Number, val as Number) as Void { /* store register value */ }
}
```

### Performance Notes

A rough estimate: each `cpu.step()` in Monkey C's bytecode VM on Cortex-M is ~50–100 VM ops. At 67K steps/tick: ~5–7M VM ops per 16ms window. This is at the edge. Mitigation strategies if too slow:

1. **Reduce `CYCLES_PER_TICK`** — emulator runs slower than real time but still playable
2. **Frame skip** — run 2 CPU frames per display update (halves render overhead)
3. **Inline hot paths** — avoid method calls inside `renderBgLine()` pixel loop
4. **Measure first** — profile in simulator before optimizing

**Gotcha:** `Toybox.Timer.Timer.start()` fires on the UI thread. The timer callback, `onUpdate()`, and `onKey()` are all serialized — Monkey C is cooperative single-threaded. This is correct behavior.

---

## Phase 9 — Display Output

**Files:** `GarminBoyView.mc`

### Scaling

Fenix 7x Pro display: 280×280. GB screen: 160×144.

| Option | Scale | Displayed size | Offset |
|---|---|---|---|
| **v1: 1× centered** | 1.0× | 160×144 | (60, 68) |
| v2: fill width | 1.75× | 280×252 | (0, 14) |
| v3: fill height | 1.94× | 311×280 | clips hor. |

Start with 1× (simplest, minimum CPU). Add scaling in a later version.

### GarminBoyView.mc

```monkeyc
class GarminBoyView extends WatchUi.View {
    var _emulator as Emulator;

    const OFFSET_X = 60;   // (280 - 160) / 2
    const OFFSET_Y = 68;   // (280 - 144) / 2

    function initialize(emulator as Emulator) {
        View.initialize();
        _emulator = emulator;
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();

        var fb      = _emulator.getFramebuffer();
        var palette = _emulator.getPalette();

        // Group pixels by color to minimize setColor() calls
        var colorGroups = new Array[4];
        for (var i = 0; i < 4; i++) { colorGroups[i] = [] as Array; }

        for (var y = 0; y < 144; y++) {
            for (var x = 0; x < 160; x++) {
                var idx = fb[y * 160 + x] & 0xFF;
                colorGroups[idx].add([OFFSET_X + x, OFFSET_Y + y]);
            }
        }

        for (var c = 0; c < 4; c++) {
            dc.setColor(palette[c], palette[c]);
            var points = colorGroups[c];
            for (var p = 0; p < points.size(); p++) {
                dc.drawPoint(points[p][0], points[p][1]);
            }
        }
    }
}
```

### BufferedBitmap optimization (SDK 3.2+)

If `drawPoint()` is too slow, use a `BufferedBitmap` with a 4-color palette, paint pixels into its DC off-screen, then blit the whole thing with a single `dc.drawBitmap()`. Measure both in the simulator before committing.

**Gotchas:**
- `dc.setColor(fg, bg)` — `drawPoint()` uses foreground. Both args must be set.
- `WatchUi.requestUpdate()` schedules `onUpdate()` — do NOT call `onUpdate()` directly from the timer callback.
- `onUpdate()` has a watchdog timeout. 23K `drawPoint()` calls should be well within it, but verify in simulator.

---

## Testing Milestones

| # | Milestone | Validates |
|---|---|---|
| 1 | PC advances past `0x0100` in simulator logs | ROM loads, basic CPU dispatch works |
| 2 | WRAM/HRAM round-trip test passes | Memory read/write routing correct |
| 3 | First non-blank frame rendered | PPU produces output, VBlank fires |
| 4 | Nintendo logo scrolls, Tetris title screen appears | BG tile rendering, BGP palette, SCX/SCY, boot timing |
| 5 | Pressing Start enters the game | Joypad registers + INT_JOYPAD dispatch |
| 6 | Pieces fall and move at correct speed | TIMA timer interrupt driving game logic |

---

## Critical Path

```
Phase 1: manifest.xml + monkey.jungle          (~10 min)
  └── Phase 3: Memory.mc                       (2–3 hrs) ← everything depends on this
        ├── Phase 5a: Interrupts.mc            (30 min)
        ├── Phase 2: Rom.mc                    (1–2 hrs) ← get bytes loading first
        ├── Phase 5b: GbTimer.mc               (1 hr)
        ├── Phase 7a: Sound.mc stub            (30 min)
        ├── Phase 4: Cpu.mc                    (1–2 days) ← Tetris opcodes first
        └── Phase 6: Ppu.mc                    (2–3 days) ← BG layer → window → sprites
              └── Phase 8: Emulator.mc         (2 hrs)
                    └── Phase 9: GarminBoyView.mc        (1–2 hrs)
                          └── Phase 7b: GarminBoyDelegate.mc  (1 hr)
```

**Estimated timeline:**
- Milestone 4 (Tetris title screen): 1–2 weeks
- Milestone 6 (fully playable Tetris): 2–3 weeks

---

## Cross-Cutting Monkey C Concerns

### Mandatory arithmetic masking

Monkey C integers are 32-bit signed and never overflow/wrap. Every byte operation must be masked:

```monkeyc
var result = (a + b) & 0xFF;        // 8-bit addition
var result = (a - b) & 0xFF;        // 8-bit subtraction
var result = (a + b) & 0xFFFF;      // 16-bit addition
var byte   = byteArray[i] & 0xFF;   // unsigned read from ByteArray
```

### Class naming conflicts to avoid

| Avoid | Use instead | Conflicts with |
|---|---|---|
| `Timer` | `GbTimer` | `Toybox.Timer` |
| `Graphics` | — | `Toybox.Graphics` |
| `Math` | — | `Toybox.Math` |
| `System` | — | `Toybox.System` |

### Debug logging

```monkeyc
const DEBUG = false;   // set true during development, false for release

// Usage:
if (DEBUG) { Sys.println("PC: " + pc.format("%04X")); }
```

### ByteArray allocation syntax

```monkeyc
var buf = new [32768]b;   // the 'b' suffix is required for ByteArray
var arr = new [10];       // without 'b' — this is an Array, not a ByteArray
```

### Required `using` statements (top of each file)

```monkeyc
using Toybox.Application as Application;
using Toybox.WatchUi     as WatchUi;
using Toybox.Graphics    as Graphics;
using Toybox.Timer       as Timer;
using Toybox.System      as Sys;
using Toybox.Lang        as Lang;
```

---

## Key Reference Files in tinygb

| File | Used for |
|---|---|
| `src/core/cpu.c` | All instruction semantics and cycle counts |
| `src/core/display.c` | PPU state machine, mode timing, sprite logic |
| `src/core/memory.c` | Address space map, I/O register routing |
| `src/core/timer.c` | DIV/TIMA/TMA cycle logic |
| `src/core/interrupts.c` | IF/IE register behavior |
| `src/core/joypad.c` | P1 register read/write logic |
| `src/core/sound.c` | Register list for stub implementation |
| `src/include/tinygb.h` | Struct layouts, constants, initial register values |
| `src/include/ioports.h` | I/O register addresses |
