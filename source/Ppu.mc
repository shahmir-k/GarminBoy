using Toybox.System as Sys;

// PPU — DMG-only scanline renderer.
// Renders directly into a 160×144 palette-index framebuffer.
// No 256×256 background buffer (the tinygb approach) — tiles are looked up
// on demand per-pixel to stay within the Garmin heap budget.

class Ppu {
    // LCD control registers
    var lcdc as Number = 0x91;
    var stat as Number = 0x80;
    var scy  as Number = 0;
    var scx  as Number = 0;
    var ly   as Number = 0;
    var lyc  as Number = 0;
    var bgp  as Number = 0xFC;
    var obp0 as Number = 0xFF;
    var obp1 as Number = 0xFF;
    var wy   as Number = 0;
    var wx   as Number = 0;
    var dma  as Number = 0;

    // 160×144 framebuffer, each byte is a DMG palette index 0–3
    var framebuffer as ByteArray;

    var _frameReady     as Boolean = false;
    var _cycles         as Number  = 0;
    var _lineRendered   as Boolean = false;
    var _winLineCounter as Number  = 0;

    // DMG green palette (24-bit RGB for Garmin DC)
    var palette as Array = [0xC4CFA1, 0x8B956D, 0x4D533C, 0x1F1F1F];

    var _mem        as Memory;
    var _interrupts as Interrupts;

    function initialize(mem as Memory, interrupts as Interrupts) {
        _mem        = mem;
        _interrupts = interrupts;
        framebuffer = new [160 * 144]b;
    }

    function start() as Void {
        lcdc = 0x91;
        stat = 0x80;
        ly   = 0;
        lyc  = 0;
        bgp  = 0xFC;
        obp0 = 0xFF;
        obp1 = 0xFF;
        scy  = 0;
        scx  = 0;
        wy   = 0;
        wx   = 0;
        dma  = 0;
        _cycles         = 0;
        _lineRendered   = false;
        _winLineCounter = 0;
        _frameReady     = false;
    }

    // -------------------------------------------------------------------------
    // Register I/O
    // -------------------------------------------------------------------------

    function readReg(addr as Number) as Number {
        switch (addr) {
            case 0xFF40: return lcdc;
            case 0xFF41: return stat | 0x80;
            case 0xFF42: return scy;
            case 0xFF43: return scx;
            case 0xFF44: return ly;
            case 0xFF45: return lyc;
            case 0xFF46: return dma;
            case 0xFF47: return bgp;
            case 0xFF48: return obp0;
            case 0xFF49: return obp1;
            case 0xFF4A: return wy;
            case 0xFF4B: return wx;
        }
        return 0xFF;
    }

    function writeReg(addr as Number, val as Number) as Void {
        switch (addr) {
            case 0xFF40: lcdc = val; break;
            case 0xFF41: stat = (stat & 0x07) | (val & 0x78); break;
            case 0xFF42: scy  = val; break;
            case 0xFF43: scx  = val; break;
            case 0xFF44: break;     // LY is read-only
            case 0xFF45: lyc  = val; break;
            case 0xFF46:
                dma = val;
                executeDma();
                break;
            case 0xFF47: bgp  = val; break;
            case 0xFF48: obp0 = val; break;
            case 0xFF49: obp1 = val; break;
            case 0xFF4A: wy   = val; break;
            case 0xFF4B: wx   = val; break;
        }
    }

    function executeDma() as Void {
        var srcBase = (dma << 8) & 0xFFFF;
        for (var i = 0; i < 160; i++) {
            _mem.oam[i] = _mem.readByte(srcBase + i) & 0xFF;
        }
    }

    // -------------------------------------------------------------------------
    // PPU state machine — call once per CPU step with the T-state count
    // -------------------------------------------------------------------------

    function cycle(tStates as Number) as Void {
        if ((lcdc & 0x80) == 0) {
            ly = 0;
            _cycles = 0;
            stat = stat & 0xFC;
            return;
        }

        _cycles += tStates;

        if (ly >= 144) {
            // Mode 1 — VBlank
            if (_cycles >= 456) {
                _cycles -= 456;
                ly++;
                if (ly >= 154) {
                    ly = 0;
                    _winLineCounter = 0;
                    setMode(2);
                    checkLyc();
                    if ((stat & 0x20) != 0) {
                        _interrupts.request(Interrupts.INT_STAT);
                    }
                } else {
                    checkLyc();
                }
            }
        } else {
            var mode = stat & 0x03;

            if (_cycles <= 80) {
                if (mode != 2) {
                    setMode(2);
                }
            } else if (_cycles <= 252) {
                if (mode != 3) {
                    setMode(3);
                }
                if (!_lineRendered) {
                    renderLine();
                    _lineRendered = true;
                }
            } else if (_cycles < 456) {
                if (mode != 0) {
                    setMode(0);
                    if ((stat & 0x08) != 0) {
                        _interrupts.request(Interrupts.INT_STAT);
                    }
                }
            }

            if (_cycles >= 456) {
                _cycles -= 456;
                ly++;
                _lineRendered = false;

                if (ly == 144) {
                    setMode(1);
                    _interrupts.request(Interrupts.INT_VBLANK);
                    if ((stat & 0x10) != 0) {
                        _interrupts.request(Interrupts.INT_STAT);
                    }
                    _frameReady = true;
                } else if (ly < 144) {
                    setMode(2);
                    if ((stat & 0x20) != 0) {
                        _interrupts.request(Interrupts.INT_STAT);
                    }
                }
                checkLyc();
            }
        }
    }

    function setMode(mode as Number) as Void {
        stat = (stat & 0xFC) | (mode & 0x03);
    }

    function checkLyc() as Void {
        if (ly == lyc) {
            stat |= 0x04;
            if ((stat & 0x40) != 0) {
                _interrupts.request(Interrupts.INT_STAT);
            }
        } else {
            stat &= ~0x04;
        }
    }

    // -------------------------------------------------------------------------
    // Scanline rendering
    // -------------------------------------------------------------------------

    function renderLine() as Void {
        if (ly >= 144) { return; }
        var lineBase = ly * 160;

        // Clear line to palette 0
        for (var x = 0; x < 160; x++) {
            framebuffer[lineBase + x] = 0;
        }

        if ((lcdc & 0x80) == 0) { return; }

        // BG layer
        if ((lcdc & 0x01) != 0) {
            renderBgLine(lineBase);
        }

        // Window layer
        if ((lcdc & 0x20) != 0 && wy <= ly) {
            renderWindowLine(lineBase);
        }

        // Sprite layer
        if ((lcdc & 0x02) != 0) {
            renderSpriteLine(lineBase);
        }
    }

    function renderBgLine(lineBase as Number) as Void {
        var mapBase = ((lcdc & 0x08) != 0) ? 0x1C00 : 0x1800;
        var signedAddr = ((lcdc & 0x10) == 0);

        var bgY = (ly + scy) & 0xFF;
        var tileRow = (bgY >> 3) & 0x1F;
        var pixelRowInTile = bgY & 7;

        for (var screenX = 0; screenX < 160; screenX++) {
            var bgX = (screenX + scx) & 0xFF;
            var tileCol = (bgX >> 3) & 0x1F;
            var pixelCol = bgX & 7;

            var mapIdx = mapBase + (tileRow * 32) + tileCol;
            var tileIndex = _mem.vram[mapIdx] & 0xFF;

            var tileDataAddr;
            if (signedAddr) {
                var si = tileIndex;
                if ((si & 0x80) != 0) { si = si - 256; }
                tileDataAddr = 0x1000 + (si * 16);
            } else {
                tileDataAddr = tileIndex * 16;
            }

            var rowAddr = tileDataAddr + (pixelRowInTile * 2);
            if (rowAddr < 0 || rowAddr + 1 >= 8192) {
                framebuffer[lineBase + screenX] = 0;
                continue;
            }
            var lo = _mem.vram[rowAddr]     & 0xFF;
            var hi = _mem.vram[rowAddr + 1] & 0xFF;

            var bit = 7 - pixelCol;
            var colorIdx = (((hi >> bit) & 1) << 1) | ((lo >> bit) & 1);
            framebuffer[lineBase + screenX] = (bgp >> (colorIdx * 2)) & 3;
        }
    }

    function renderWindowLine(lineBase as Number) as Void {
        var mapBase = ((lcdc & 0x40) != 0) ? 0x1C00 : 0x1800;
        var signedAddr = ((lcdc & 0x10) == 0);
        var wxScreen = wx - 7;

        var winY = _winLineCounter;
        var tileRow = (winY >> 3) & 0x1F;
        var pixelRowInTile = winY & 7;

        var startX = (wxScreen < 0) ? 0 : wxScreen;

        for (var screenX = startX; screenX < 160; screenX++) {
            var winX = screenX - wxScreen;
            if (winX < 0) { continue; }
            var tileCol = (winX >> 3) & 0x1F;
            var pixelCol = winX & 7;

            var mapIdx = mapBase + (tileRow * 32) + tileCol;
            var tileIndex = _mem.vram[mapIdx] & 0xFF;

            var tileDataAddr;
            if (signedAddr) {
                var si = tileIndex;
                if ((si & 0x80) != 0) { si = si - 256; }
                tileDataAddr = 0x1000 + (si * 16);
            } else {
                tileDataAddr = tileIndex * 16;
            }

            var rowAddr = tileDataAddr + (pixelRowInTile * 2);
            if (rowAddr < 0 || rowAddr + 1 >= 8192) { continue; }
            var lo = _mem.vram[rowAddr]     & 0xFF;
            var hi = _mem.vram[rowAddr + 1] & 0xFF;

            var bit = 7 - pixelCol;
            var colorIdx = (((hi >> bit) & 1) << 1) | ((lo >> bit) & 1);
            framebuffer[lineBase + screenX] = (bgp >> (colorIdx * 2)) & 3;
        }

        _winLineCounter++;
    }

    function renderSpriteLine(lineBase as Number) as Void {
        var spriteHeight = ((lcdc & 0x04) != 0) ? 16 : 8;

        // Iterate OAM in reverse so lower-index sprites have priority
        var rendered = 0;
        for (var i = 39; i >= 0; i--) {
            var oamBase = i * 4;
            var sprY   = (_mem.oam[oamBase]     & 0xFF) - 16;
            var sprX   = (_mem.oam[oamBase + 1] & 0xFF) - 8;
            var tile   = _mem.oam[oamBase + 2]  & 0xFF;
            var attrs  = _mem.oam[oamBase + 3]  & 0xFF;

            if (ly < sprY || ly >= sprY + spriteHeight) { continue; }

            rendered++;
            if (rendered > 10) { break; } // max 10 sprites per line

            var flipY = (attrs & 0x40) != 0;
            var flipX = (attrs & 0x20) != 0;
            var paletteReg = ((attrs & 0x10) != 0) ? obp1 : obp0;
            var bgPriority = (attrs & 0x80) != 0;

            var rowInSprite = ly - sprY;
            if (flipY) { rowInSprite = (spriteHeight - 1) - rowInSprite; }

            var tileAddr;
            if (spriteHeight == 16) {
                var t = tile & 0xFE;
                if (rowInSprite >= 8) {
                    t = tile | 0x01;
                    rowInSprite -= 8;
                }
                tileAddr = t * 16;
            } else {
                tileAddr = tile * 16;
            }

            var rowAddr = tileAddr + (rowInSprite * 2);
            if (rowAddr < 0 || rowAddr + 1 >= 8192) { continue; }
            var lo = _mem.vram[rowAddr]     & 0xFF;
            var hi = _mem.vram[rowAddr + 1] & 0xFF;

            for (var px = 0; px < 8; px++) {
                var screenX = sprX + px;
                if (screenX < 0 || screenX >= 160) { continue; }

                var bit = flipX ? px : (7 - px);
                var colorIdx = (((hi >> bit) & 1) << 1) | ((lo >> bit) & 1);
                if (colorIdx == 0) { continue; } // transparent

                var paletteColor = (paletteReg >> (colorIdx * 2)) & 3;

                if (bgPriority && framebuffer[lineBase + screenX] != 0) { continue; }

                framebuffer[lineBase + screenX] = paletteColor;
            }
        }
    }
}
