# Galvantronix, DLSU, and me!

A multi-application VGA graphics chip built in Verilog for [Tiny Tapeout](https://tinytapeout.com), running at 640×480 @ 60Hz on a 25.175 MHz pixel clock. Three distinct graphical applications are multiplexed into a single 1×1 logic tile — switchable via physical input pins. All graphics are rendered purely combinatorially; no external RAM or ROM is used.

**Author:** Chico Andre G. Olaguer  
**Discord:** amorcogitatio  
**Top Module:** `tt_um_AlephNaNsea_decentvgachipIEEEIESIPSPH`

---

## Applications

### 🛡️ DLSU Animo Shield + Galvantronix Background *(Default — all mode pins LOW)*
The default scene combines two layers. The foreground renders the letters **DLSU** in bright green using bounding-box algebra, with a 6-pixel dark green drop shadow. A white outer diamond border and a pulsing inner diamond are drawn using Manhattan distance from screen center (320, 240), with the inner pulse driven by `frame_counter` for a smooth breathing effect. The background features scrolling horizontal and vertical circuit traces and via pads that pan diagonally over time, evoking a live PCB aesthetic.

### 🌀 Hilbert Curve Generator *(`ui_in[0]` HIGH, `ui_in[5]` LOW)*
A recursive fractal renderer that draws Order-1 through Order-5 Hilbert space-filling curves on a 16×16 cell grid centered in a 256×256 pixel area. The core is a fully unrolled, multiplierless function that maps any `(x, y)` cell coordinate to its Hilbert sequence number using cascaded XOR-based quadrant transformations — no multiplier, no ROM. An animation timer advances each frame to reveal cells in order, creating a draw-in effect. The system cycles automatically through all five orders with a 60-frame pause between each. Colors shift using the upper bits of the sequence number and `frame_counter`.

### 🧩 Hardware Logic Maze *(`ui_in[5]` HIGH)*
A fully playable 2D maze game on a 20×15 grid where each cell is 32×32 pixels. The wall map is stored as 20-bit row literals in a combinatorial `case` function, synthesized as a logic ROM. Player movement is debounced at the frame boundary using rising-edge detection on `ui_in[4:1]`, and the candidate position is validated against the wall ROM before the player registers update. Reaching the target at grid position (9, 7) triggers a 3-second flashing victory animation before the maze resets.

---

## Hardware Required

- A **VGA PMOD** (TinyVGA-compatible, 2 bits per channel) connected to `uo_out`
- A VGA monitor capable of **640×480 @ 60Hz**
- A **DIP Switch PMOD** or push-button array connected to `ui_in`

---

## Pin Reference

| Pin | Function |
|-----|----------|
| `ui_in[0]` | Hilbert Curve mode (only active when `ui_in[5]` is LOW) |
| `ui_in[1]` | D-Pad Up (Maze) |
| `ui_in[2]` | D-Pad Down (Maze) |
| `ui_in[3]` | D-Pad Left (Maze) |
| `ui_in[4]` | D-Pad Right (Maze) |
| `ui_in[5]` | Maze mode (takes priority over all other modes) |
| `ui_in[6]` | Unused |
| `ui_in[7]` | Unused |
| `uo_out[0]` | R1 — VGA Red MSB |
| `uo_out[1]` | G1 — VGA Green MSB |
| `uo_out[2]` | B1 — VGA Blue MSB |
| `uo_out[3]` | VSync |
| `uo_out[4]` | R0 — VGA Red LSB |
| `uo_out[5]` | G0 — VGA Green LSB |
| `uo_out[6]` | B0 — VGA Blue LSB |
| `uo_out[7]` | HSync |

**Mode priority:** `ui_in[5]` (Maze) overrides `ui_in[0]` (Hilbert). If both are LOW, the DLSU Shield is shown.

---

## What is Tiny Tapeout?

Tiny Tapeout is an educational project that makes it easier and cheaper than ever to get your digital designs manufactured on a real chip. Learn more at [https://tinytapeout.com](https://tinytapeout.com).

## Resources

- [FAQ](https://tinytapeout.com/faq/)
- [Digital design lessons](https://tinytapeout.com/digital_design/)
- [Learn how semiconductors work](https://tinytapeout.com/siliwiz/)
- [Join the community](https://tinytapeout.com/discord)
- [Build your design locally](https://www.tinytapeout.com/guides/local-hardening/)
