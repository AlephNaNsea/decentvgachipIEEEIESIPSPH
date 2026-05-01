<!---

This file is used to generate your project datasheet. Please fill in the information below and delete any unused
sections.

You can also include images in this folder and reference them in the markdown. Each image must be less than
512 kb in size, and the combined size of all images must be less than 1 MB.
-->

## How it works

This project is a multi-application graphical system built in Verilog, designed to run directly on hardware via VGA at 640x480 resolution (60Hz). It features a dedicated multiplexer that reads physical input switches to select between four distinct graphical applications synthesized into a single logic tile:

1.  **Hardware Logic Maze (`ui_in[5]`):** A fully playable, combinatorial 2D maze game where the player navigates a fixed 20x15 grid (rendered as 32x32 pixel blocks) using external D-Pad inputs. It includes collision detection and a pulsing victory animation upon reaching the target.
2.  **True Hilbert Curve Generator (`ui_in[0]`):** A recursive fractal rendering engine. Using a highly optimized, multiplierless 1D-to-2D boolean mapping sequence, it draws a continuous, space-filling Order-4 Hilbert Curve.
3.  **High-Res Galvantronix Logo (`ui_in[6]`):** A purely mathematical vector rendering engine. It uses intersecting geometric bounds and Manhattan distance calculations to draw a complex, animated cybernetic logo in real-time, utilizing symmetry constraints rather than memory-heavy lookup tables.
4.  **DLSU Animo Shield (Default):** A dynamic, pulsing geometric shield featuring the acronym "DLSU", retro drop shadows, and scrolling background grid lines.

## How to test

To test the project, you must connect the VGA output pins to a monitor and use the input pins to toggle the active application and control the maze. 

**Application Selection:**
Ensure only one mode toggle is HIGH at a time to view that specific application. If all mode toggles are LOW, the system defaults to the DLSU Shield.
*   Set `ui_in[6]` HIGH to launch the **Galvantronix Logo**.
*   Set `ui_in[5]` HIGH to launch the **Maze Game**.
*   Set `ui_in[0]` HIGH to launch the **Hilbert Curve**.
*   Set all to LOW to view the **DLSU Shield**.

**Playing the Maze Game (Requires `ui_in[5]` to be HIGH):**
Use the following pins as a directional pad to navigate the cyan square to the white target block. The inputs are debounced and respond to rising edges.
*   Toggle `ui_in[1]` HIGH to move **Up**.
*   Toggle `ui_in[2]` HIGH to move **Down**.
*   Toggle `ui_in[3]` HIGH to move **Left**.
*   Toggle `ui_in[4]` HIGH to move **Right**.

## External hardware

To run this visualizer, you will need the following hardware attached to the Tiny Tapeout carrier board:
*   A **VGA PMOD** connected to the dedicated output pins (`uo_out`).
*   A standard VGA cable and a monitor capable of displaying a 640x480 signal at 60Hz.
*   A **DIP Switch PMOD** or a custom push-button array connected to the input pins (`ui_in`) to toggle between the display modes and navigate the maze.
