`default_nettype none

module tt_um_AlephNaNsea_decentvgachipIEEEIESIPSPH (
    input  wire [7:0] ui_in,    // [7:6]:Unused, [5]:Maze, [4:1]:D-Pad, [0]:Hilbert
    output wire [7:0] uo_out,   // VGA out: {hsync, B0, G0, R0, vsync, B1, G1, R1}
    input  wire [7:0] uio_in,   
    output wire [7:0] uio_out,  
    output wire [7:0] uio_oe,   
    input  wire       ena,      
    input  wire       clk,      // 25 MHz
    input  wire       rst_n     
);

    // =========================================================
    // 1. HOUSEKEEPING & SHARED VGA TIMING
    // =========================================================
    assign uio_out = 8'b0;
    assign uio_oe  = 8'b0;
    wire reset = ~rst_n;
    wire [1:0] unused_ui = ui_in[7:6];
    wire _unused_ok = &{1'b0, ena, unused_ui, uio_in, 1'b0};

    reg [9:0] h_cnt;
    reg [9:0] v_cnt;

    always @(posedge clk) begin
        if (reset) begin h_cnt <= 0; v_cnt <= 0; end
        else begin
            if (h_cnt == 799) begin
                h_cnt <= 0;
                v_cnt <= (v_cnt == 524) ? 0 : v_cnt + 1;
            end else h_cnt <= h_cnt + 1;
        end
    end

    wire hsync = ~(h_cnt >= 656 && h_cnt < 752);
    wire vsync = ~(v_cnt >= 490 && v_cnt < 492);
    wire display_on = (h_cnt < 640) && (v_cnt < 480);
    wire frame_tick = (h_cnt == 799 && v_cnt == 524);

    reg [11:0] frame_counter;
    always @(posedge clk) begin
        if (reset) frame_counter <= 0;
        else if (frame_tick) frame_counter <= frame_counter + 1;
    end
    
    wire [7:0] frame_cnt = frame_counter[7:0]; 

    // Unified Mode Mux
    wire app_maze   = ui_in[5];
    wire app_hilb   = !ui_in[5] && ui_in[0];

    // =========================================================
    // 2. APP 1: HARDWARE LOGIC MAZE (Time-Multiplexed ROM)
    // =========================================================
    wire [4:0] gx = h_cnt[9:5];
    wire [4:0] gy = v_cnt[9:5];

    function is_wall_at;
        input [4:0] grid_x; input [4:0] grid_y; reg [19:0] r;
        begin
            case(grid_y)
                0:  r = 20'b1111_1111_1111_1111_1111; 1:  r = 20'b1000_0000_0000_0000_0001; 
                2:  r = 20'b1011_1110_1011_1110_1101; 3:  r = 20'b1010_0000_1000_0010_0101;
                4:  r = 20'b1010_1111_1110_1110_0101; 5:  r = 20'b1010_1000_0010_0000_0001; 
                6:  r = 20'b1010_1011_0011_1111_1101; 7:  r = 20'b1000_0010_0000_0000_0001; 
                8:  r = 20'b1111_1011_1111_1011_1101; 9:  r = 20'b1000_0000_0010_0010_0001;
                10: r = 20'b1011_1111_1011_1010_1101; 11: r = 20'b1010_0000_1000_0010_0101;
                12: r = 20'b1010_1111_1111_1110_0101; 13: r = 20'b1000_0000_0000_0000_0001;
                14: r = 20'b1111_1111_1111_1111_1111; default: r = 20'hFFFFF;
            endcase
            is_wall_at = (grid_x < 20 && grid_y < 15) ? r[19 - grid_x] : 1'b1;
        end
    endfunction

    reg [3:0] btn_state, btn_prev;
    always @(posedge clk) begin
        if (reset) begin btn_state <= 0; btn_prev <= 0; end 
        else if (frame_tick) begin btn_state <= ui_in[4:1]; btn_prev <= btn_state; end
    end

    wire move_up    = btn_state[0] & ~btn_prev[0]; wire move_down  = btn_state[1] & ~btn_prev[1];
    wire move_left  = btn_state[2] & ~btn_prev[2]; wire move_right = btn_state[3] & ~btn_prev[3];

    reg maze_state; reg [4:0] px, py; reg [7:0] win_timer;
    wire move_any = move_up | move_down | move_left | move_right;
    wire [4:0] try_x = move_up ? px : (move_down ? px : (move_left ? px - 1 : (move_right ? px + 1 : px)));
    wire [4:0] try_y = move_up ? py - 1 : (move_down ? py + 1 : py);
    
    // --- OPTIMIZATION: Time-multiplex the single ROM so graphics and logic share it ---
    wire [4:0] rom_qx = frame_tick ? try_x : gx;
    wire [4:0] rom_qy = frame_tick ? try_y : gy;
    wire wall_lookup = is_wall_at(rom_qx, rom_qy);
    
    wire maze_wall = wall_lookup;      // Read during display_on
    wire valid_move = !wall_lookup;    // Evaluated precisely on frame_tick

    always @(posedge clk) begin
        if (reset) begin
            maze_state <= 0; px <= 5'd1; py <= 5'd1; win_timer <= 0;
        end else if (app_maze) begin 
            if (maze_state == 0) begin
                if (px == 5'd9 && py == 5'd7) begin maze_state <= 1; win_timer <= 0; end 
                else if (frame_tick && move_any && valid_move) begin
                    px <= try_x; py <= try_y;
                end
            end else begin
                if (frame_tick) begin
                    if (win_timer == 8'd180) begin maze_state <= 0; px <= 5'd1; py <= 5'd1; end 
                    else win_timer <= win_timer + 1;
                end
            end
        end
    end

    wire [2:0] px_text = h_cnt[4:2]; wire [2:0] py_text = v_cnt[4:2];
    reg [7:0] maze_font_row;
    always @(*) begin
        maze_font_row = 8'h00;
        if (gx == 8) case(py_text) 0:maze_font_row=8'hF8; 1:maze_font_row=8'h6C; 2:maze_font_row=8'h66; 3:maze_font_row=8'h66; 4:maze_font_row=8'h66; 5:maze_font_row=8'h6C; 6:maze_font_row=8'hF8; default:maze_font_row=8'h00; endcase
        else if (gx == 9) case(py_text) 0:maze_font_row=8'h60; 1:maze_font_row=8'h60; 2:maze_font_row=8'h60; 3:maze_font_row=8'h60; 4:maze_font_row=8'h60; 5:maze_font_row=8'h60; 6:maze_font_row=8'hFE; default:maze_font_row=8'h00; endcase
        else if (gx == 10) case(py_text) 0:maze_font_row=8'h3C; 1:maze_font_row=8'h66; 2:maze_font_row=8'h60; 3:maze_font_row=8'h3C; 4:maze_font_row=8'h06; 5:maze_font_row=8'h66; 6:maze_font_row=8'h3C; default:maze_font_row=8'h00; endcase
        else if (gx == 11) case(py_text) 0:maze_font_row=8'h66; 1:maze_font_row=8'h66; 2:maze_font_row=8'h66; 3:maze_font_row=8'h66; 4:maze_font_row=8'h66; 5:maze_font_row=8'h66; 6:maze_font_row=8'h3C; default:maze_font_row=8'h00; endcase
    end

    wire maze_draw_text = (gy == 0) && maze_font_row[7 - px_text] && (gx >= 8 && gx <= 11);
    wire [4:0] px_mod = h_cnt[4:0]; wire [4:0] py_mod = v_cnt[4:0];
    wire in_padding = (px_mod >= 8 && px_mod < 24) && (py_mod >= 8 && py_mod < 24);
    wire is_player = (gx == px && gy == py) && in_padding;
    wire is_target = (gx == 5'd9 && gy == 5'd7) && in_padding;
    wire brick_hi = (px_mod == 0) || (py_mod == 0);
    wire brick_lo = (px_mod == 31) || (py_mod == 31);
    wire maze_flash = (maze_state == 1) && win_timer[4];

    // =========================================================
    // 3. APP 2: TRUE HILBERT CURVE (Extreme Optimization)
    // =========================================================
    reg [2:0] cur_order; reg [9:0] anim_timer; reg [5:0] pause_timer;
    
    reg [9:0] max_d;
    always @(*) begin
        case(cur_order)
            1: max_d = 10'd3; 2: max_d = 10'd15; 3: max_d = 10'd63;
            4: max_d = 10'd255; 5: max_d = 10'd1023; default: max_d = 10'd3;
        endcase
    end

    always @(posedge clk) begin
        if (reset) begin
            cur_order <= 1; anim_timer <= 0; pause_timer <= 0;
        end else if (frame_tick && app_hilb) begin
            if (anim_timer > max_d) begin
                if (pause_timer < 60) pause_timer <= pause_timer + 1; 
                else begin
                    pause_timer <= 0; anim_timer <= 0;
                    if (cur_order == 5) cur_order <= 1; 
                    else cur_order <= cur_order + 1;    
                end
            end else begin
                if      (cur_order <= 2) anim_timer <= anim_timer + 1;
                else if (cur_order == 3) anim_timer <= anim_timer + 2;
                else if (cur_order == 4) anim_timer <= anim_timer + 4;
                else                     anim_timer <= anim_timer + 8;
            end
        end
    end

    function [7:0] hilbert_d;
        input [3:0] hx; input [3:0] hy;
        reg rx3, ry3, rx2, ry2, rx1, ry1, rx0, ry0;
        reg [1:0] d3, d2, d1, d0; reg [2:0] cx2, cy2; reg [1:0] cx1, cy1; reg [0:0] cx0, cy0;
        begin
            rx3 = hx[3]; ry3 = hy[3]; d3 = {rx3, rx3^ry3};
            cx2 = (ry3 == 0) ? (rx3 ? ~hy[2:0] : hy[2:0]) : hx[2:0]; cy2 = (ry3 == 0) ? (rx3 ? ~hx[2:0] : hx[2:0]) : hy[2:0];
            rx2 = cx2[2]; ry2 = cy2[2]; d2 = {rx2, rx2^ry2};
            cx1 = (ry2 == 0) ? (rx2 ? ~cy2[1:0] : cy2[1:0]) : cx2[1:0]; cy1 = (ry2 == 0) ? (rx2 ? ~cx2[1:0] : cx2[1:0]) : cy2[1:0];
            rx1 = cx1[1]; ry1 = cy1[1]; d1 = {rx1, rx1^ry1};
            cx0 = (ry1 == 0) ? (rx1 ? ~cy1[0] : cy1[0]) : cx1[0]; cy0 = (ry1 == 0) ? (rx1 ? ~cx1[0] : cx1[0]) : cy1[0];
            rx0 = cx0[0]; ry0 = cy0[0]; d0 = {rx0, rx0^ry0};
            hilbert_d = {d3, d2, d1, d0};
        end
    endfunction

    wire in_hilbert_bounds = (h_cnt >= 192 && h_cnt < 448) && (v_cnt >= 112 && v_cnt < 368);
    wire [7:0] local_x = h_cnt[7:0] - 8'd192; wire [7:0] local_y = v_cnt[7:0] - 8'd112;
    wire [3:0] cell_x = local_x[7:4]; wire [3:0] cell_y = local_y[7:4];
    wire [3:0] sub_x  = local_x[3:0]; wire [3:0] sub_y  = local_y[3:0];

    // Compute the sequence number for the current cell only
    wire [7:0] d_curr = hilbert_d(cell_x, cell_y);

    // --- OPTIMIZATION: Cut the neighbor logic and draw floating blocks to save routing area ---
    wire [7:0] active_d = (|anim_timer[9:8]) ? 8'hFF : anim_timer[7:0]; 
    wire is_cell_body = (sub_x >= 3 && sub_x <= 12) && (sub_y >= 3 && sub_y <= 12);
    wire draw_hilbert = in_hilbert_bounds && (d_curr <= active_d) && is_cell_body;

    wire [1:0] hilbert_r = (d_curr[5:4] + frame_cnt[6:5]);
    wire [1:0] hilbert_g = (d_curr[6:5] + frame_cnt[5:4]);
    wire [1:0] hilbert_b = 2'b11;

    // =========================================================
    // 4. OPTIMIZED SHIELD ENGINE (No Signed Math)
    // =========================================================
    // Calculate absolute distance from center (320, 240) without 11-bit signed variables
    wire [9:0] abs_x = (h_cnt >= 320) ? (h_cnt - 320) : (320 - h_cnt);
    wire [9:0] abs_y = (v_cnt >= 240) ? (v_cnt - 240) : (240 - v_cnt);
    wire [10:0] abs_sum = abs_x + abs_y;

    wire outer_shield = (abs_sum > 160) && (abs_sum < 164);
    wire [6:0] pulse = frame_cnt[7] ? ~frame_cnt[6:0] : frame_cnt[6:0];
    wire [9:0] p_add = {3'b0, pulse};
    wire inner_pulse = (abs_sum > 10'd80 + p_add) && (abs_sum < 10'd84 + p_add);

    // =========================================================
    // 5. DEFAULT APP: GALVANTRONIX SHIELD & CIRCUIT MOTIF
    // =========================================================
    wire [4:0] pan_x = h_cnt[4:0] - frame_cnt[6:2]; 
    wire [4:0] pan_y = v_cnt[4:0] - frame_cnt[6:2]; 
    wire trace_h = (pan_y == 0) && (h_cnt[6] ^ v_cnt[7]); 
    wire trace_v = (pan_x == 0) && (v_cnt[6] ^ h_cnt[7]);
    wire via_pad = (pan_x < 4) && (pan_y < 4) && (h_cnt[7] ^ v_cnt[7]);
    wire art_circuit = trace_h || trace_v || via_pad;

    // --- OPTIMIZATION: Pre-solved Algebra. Raw screen coordinates mapped directly to bounding boxes ---
    wire letter_D = (h_cnt > 210 && h_cnt < 250 && v_cnt > 200 && v_cnt < 280) && !(h_cnt > 220 && h_cnt < 240 && v_cnt > 220 && v_cnt < 260);
    wire shadow_D = (h_cnt > 216 && h_cnt < 256 && v_cnt > 206 && v_cnt < 286) && !(h_cnt > 226 && h_cnt < 246 && v_cnt > 226 && v_cnt < 266);
    
    wire letter_L = (h_cnt > 270 && h_cnt < 310 && v_cnt > 200 && v_cnt < 280) && !(h_cnt > 290 && h_cnt < 310 && v_cnt < 260);
    wire shadow_L = (h_cnt > 276 && h_cnt < 316 && v_cnt > 206 && v_cnt < 286) && !(h_cnt > 296 && h_cnt < 316 && v_cnt < 266);
    
    wire letter_S = (h_cnt > 330 && h_cnt < 370 && v_cnt > 200 && v_cnt < 280) && !(h_cnt > 350 && h_cnt < 370 && v_cnt > 220 && v_cnt < 240) && !(h_cnt > 330 && h_cnt < 350 && v_cnt > 240 && v_cnt < 260);
    wire shadow_S = (h_cnt > 336 && h_cnt < 376 && v_cnt > 206 && v_cnt < 286) && !(h_cnt > 356 && h_cnt < 376 && v_cnt > 226 && v_cnt < 246) && !(h_cnt > 336 && h_cnt < 356 && v_cnt > 246 && v_cnt < 266);
    
    wire letter_U = (h_cnt > 390 && h_cnt < 430 && v_cnt > 200 && v_cnt < 280) && !(h_cnt > 400 && h_cnt < 420 && v_cnt < 260);
    wire shadow_U = (h_cnt > 396 && h_cnt < 436 && v_cnt > 206 && v_cnt < 286) && !(h_cnt > 406 && h_cnt < 426 && v_cnt < 266);

    wire art_draw_dlsu = letter_D || letter_L || letter_S || letter_U;
    wire art_draw_shadow = (shadow_D || shadow_L || shadow_S || shadow_U) && !art_draw_dlsu;

    // =========================================================
    // 6. SHARED TEXT ENGINE (Dense 5-Bit Map Optimization)
    // =========================================================
    wire [5:0] txt_row = v_cnt[9:4]; wire [5:0] txt_col = h_cnt[9:4]; 
    wire [2:0] txt_px  = h_cnt[3:1]; wire [2:0] txt_py  = v_cnt[3:1];

    reg [4:0] txt_idx;
    always @(*) begin
        txt_idx = 0;
        if (!app_maze && !app_hilb) begin
            case (txt_row)
                6'd01: case(txt_col) 
                    14:txt_idx=1; 15:txt_idx=2; 16:txt_idx=3; 17:txt_idx=4; 18:txt_idx=2; 19:txt_idx=5; 
                    20:txt_idx=6; 21:txt_idx=7; 22:txt_idx=8; 23:txt_idx=5; 24:txt_idx=9; 25:txt_idx=10; default:; 
                endcase
                6'd03: case(txt_col) 
                    11:txt_idx=11; 12:txt_idx=7; 13:txt_idx=2; 14:txt_idx=5; 15:txt_idx=12; 
                    17:txt_idx=13; 18:txt_idx=14; 20:txt_idx=6; 21:txt_idx=15; 22:txt_idx=16; 
                    24:txt_idx=14; 25:txt_idx=8; 26:txt_idx=17; 27:txt_idx=16; 28:txt_idx=7; default:; 
                endcase
                6'd26: case(txt_col) 
                    5:txt_idx=18; 6:txt_idx=2; 7:txt_idx=19; 8:txt_idx=16; 10:txt_idx=20; 11:txt_idx=21; 
                    13:txt_idx=11; 14:txt_idx=15; 15:txt_idx=9; 16:txt_idx=22; 17:txt_idx=8; 19:txt_idx=23; 
                    20:txt_idx=5; 21:txt_idx=19; 22:txt_idx=7; 23:txt_idx=16; 25:txt_idx=1; 26:txt_idx=24; 
                    28:txt_idx=25; 29:txt_idx=3; 30:txt_idx=2; 31:txt_idx=26; 32:txt_idx=13; 33:txt_idx=16; 34:txt_idx=7; default:; 
                endcase
                6'd28: case(txt_col) 
                    11:txt_idx=27; 12:txt_idx=28; 13:txt_idx=18; 14:txt_idx=28; 16:txt_idx=29; 17:txt_idx=11; 
                    18:txt_idx=29; 20:txt_idx=27; 21:txt_idx=2; 22:txt_idx=6; 23:txt_idx=22; 24:txt_idx=15; 
                    26:txt_idx=30; 27:txt_idx=31; 28:txt_idx=31; default:; 
                endcase
                default: ; 
            endcase
        end
    end

    reg [7:0] txt_font;
    always @(*) begin
        case(txt_idx)
            1: case(txt_py) 0:txt_font=8'h3C; 1:txt_font=8'h66; 2:txt_font=8'h60; 3:txt_font=8'h6E; 4:txt_font=8'h66; 5:txt_font=8'h66; 6:txt_font=8'h3E; default:txt_font=0; endcase
            2: case(txt_py) 2:txt_font=8'h3C; 3:txt_font=8'h06; 4:txt_font=8'h3E; 5:txt_font=8'h66; 6:txt_font=8'h3E; default:txt_font=0; endcase
            3: case(txt_py) 0:txt_font=8'h38; 1:txt_font=8'h18; 2:txt_font=8'h18; 3:txt_font=8'h18; 4:txt_font=8'h18; 5:txt_font=8'h18; 6:txt_font=8'h3C; default:txt_font=0; endcase
            4: case(txt_py) 2:txt_font=8'h66; 3:txt_font=8'h66; 4:txt_font=8'h66; 5:txt_font=8'h3C; 6:txt_font=8'h18; default:txt_font=0; endcase
            5: case(txt_py) 2:txt_font=8'h7C; 3:txt_font=8'h66; 4:txt_font=8'h66; 5:txt_font=8'h66; 6:txt_font=8'hE6; default:txt_font=0; endcase
            6: case(txt_py) 0:txt_font=8'h30; 1:txt_font=8'h30; 2:txt_font=8'hFC; 3:txt_font=8'h30; 4:txt_font=8'h30; 5:txt_font=8'h34; 6:txt_font=8'h18; default:txt_font=0; endcase
            7: case(txt_py) 2:txt_font=8'h5C; 3:txt_font=8'h66; 4:txt_font=8'h60; 5:txt_font=8'h60; 6:txt_font=8'hF0; default:txt_font=0; endcase
            8: case(txt_py) 2:txt_font=8'h3C; 3:txt_font=8'h66; 4:txt_font=8'h66; 5:txt_font=8'h66; 6:txt_font=8'h3C; default:txt_font=0; endcase
            9: case(txt_py) 0:txt_font=8'h18; 2:txt_font=8'h38; 3:txt_font=8'h18; 4:txt_font=8'h18; 5:txt_font=8'h18; 6:txt_font=8'h3C; default:txt_font=0; endcase
            10: case(txt_py) 2:txt_font=8'h66; 3:txt_font=8'h3C; 4:txt_font=8'h18; 5:txt_font=8'h3C; 6:txt_font=8'h66; default:txt_font=0; endcase
            11: case(txt_py) 0:txt_font=8'h3C; 1:txt_font=8'h66; 2:txt_font=8'h60; 3:txt_font=8'h60; 4:txt_font=8'h60; 5:txt_font=8'h66; 6:txt_font=8'h3C; default:txt_font=0; endcase
            12: case(txt_py) 0:txt_font=8'h60; 1:txt_font=8'h60; 2:txt_font=8'h66; 3:txt_font=8'h6C; 4:txt_font=8'h78; 5:txt_font=8'h6C; 6:txt_font=8'h66; default:txt_font=0; endcase
            13: case(txt_py) 2:txt_font=8'h66; 3:txt_font=8'h66; 4:txt_font=8'h66; 5:txt_font=8'h66; 6:txt_font=8'h3A; default:txt_font=0; endcase
            14: case(txt_py) 2:txt_font=8'h7C; 3:txt_font=8'h66; 4:txt_font=8'h66; 5:txt_font=8'h7C; 6:txt_font=8'h60; 7:txt_font=8'h60; default:txt_font=0; endcase
            15: case(txt_py) 0:txt_font=8'h60; 1:txt_font=8'h60; 2:txt_font=8'h7C; 3:txt_font=8'h66; 4:txt_font=8'h66; 5:txt_font=8'h66; 6:txt_font=8'hE6; default:txt_font=0; endcase
            16: case(txt_py) 2:txt_font=8'h3C; 3:txt_font=8'h66; 4:txt_font=8'h7E; 5:txt_font=8'h60; 6:txt_font=8'h3C; default:txt_font=0; endcase
            17: case(txt_py) 2:txt_font=8'hC6; 3:txt_font=8'hC6; 4:txt_font=8'hD6; 5:txt_font=8'hFE; 6:txt_font=8'h6C; default:txt_font=0; endcase
            18: case(txt_py) 0:txt_font=8'hC6; 1:txt_font=8'hEE; 2:txt_font=8'hFE; 3:txt_font=8'hF6; 4:txt_font=8'hC6; 5:txt_font=8'hC6; 6:txt_font=8'hC6; default:txt_font=0; endcase
            19: case(txt_py) 0:txt_font=8'h06; 1:txt_font=8'h06; 2:txt_font=8'h3E; 3:txt_font=8'h66; 4:txt_font=8'h66; 5:txt_font=8'h66; 6:txt_font=8'h3E; default:txt_font=0; endcase
            20: case(txt_py) 0:txt_font=8'h60; 1:txt_font=8'h60; 2:txt_font=8'h7C; 3:txt_font=8'h66; 4:txt_font=8'h66; 5:txt_font=8'h66; 6:txt_font=8'h7C; default:txt_font=0; endcase
            21: case(txt_py) 2:txt_font=8'h66; 3:txt_font=8'h66; 4:txt_font=8'h66; 5:txt_font=8'h3E; 6:txt_font=8'h06; 7:txt_font=8'h3C; default:txt_font=0; endcase
            22: case(txt_py) 2:txt_font=8'h3C; 3:txt_font=8'h66; 4:txt_font=8'h60; 5:txt_font=8'h66; 6:txt_font=8'h3C; default:txt_font=0; endcase
            23: case(txt_py) 0:txt_font=8'h18; 1:txt_font=8'h3C; 2:txt_font=8'h66; 3:txt_font=8'h66; 4:txt_font=8'h7E; 5:txt_font=8'h66; 6:txt_font=8'h66; default:txt_font=0; endcase
            24: case(txt_py) 5:txt_font=8'h18; 6:txt_font=8'h18; default:txt_font=0; endcase
            25: case(txt_py) 0:txt_font=8'h3C; 1:txt_font=8'h66; 2:txt_font=8'h66; 3:txt_font=8'h66; 4:txt_font=8'h66; 5:txt_font=8'h66; 6:txt_font=8'h3C; default:txt_font=0; endcase
            26: case(txt_py) 2:txt_font=8'h3E; 3:txt_font=8'h66; 4:txt_font=8'h66; 5:txt_font=8'h3E; 6:txt_font=8'h06; 7:txt_font=8'h3C; default:txt_font=0; endcase
            27: case(txt_py) 0:txt_font=8'hFC; 1:txt_font=8'h66; 2:txt_font=8'h66; 3:txt_font=8'h7C; 4:txt_font=8'h66; 5:txt_font=8'h66; 6:txt_font=8'hFC; default:txt_font=0; endcase
            28: case(txt_py) 0:txt_font=8'h3E; 1:txt_font=8'h60; 2:txt_font=8'h60; 3:txt_font=8'h3C; 4:txt_font=8'h06; 5:txt_font=8'h06; 6:txt_font=8'h7C; default:txt_font=0; endcase
            29: case(txt_py) 0:txt_font=8'hFE; 1:txt_font=8'h62; 2:txt_font=8'h68; 3:txt_font=8'h78; 4:txt_font=8'h68; 5:txt_font=8'h62; 6:txt_font=8'hFE; default:txt_font=0; endcase
            30: case(txt_py) 0:txt_font=8'h18; 1:txt_font=8'h38; 2:txt_font=8'h78; 3:txt_font=8'h18; 4:txt_font=8'h18; 5:txt_font=8'h18; 6:txt_font=8'h7E; default:txt_font=0; endcase
            31: case(txt_py) 0:txt_font=8'h3C; 1:txt_font=8'h66; 2:txt_font=8'h06; 3:txt_font=8'h0C; 4:txt_font=8'h18; 5:txt_font=8'h30; 6:txt_font=8'h7E; default:txt_font=0; endcase
            default: txt_font = 8'h00;
        endcase
    end
    wire draw_text = txt_font[7 - txt_px];

    // =========================================================
    // 7. TOP-LEVEL COLOR MULTIPLEXER
    // =========================================================
    reg [1:0] r, g, b;

    always @(*) begin
        if (!display_on) begin
            r = 0; g = 0; b = 0;
        end else if (app_maze) begin
            if (maze_draw_text) begin r = maze_flash ? 3 : 0; g = 3; b = maze_flash ? 3 : 0; end 
            else if (is_player) begin r = maze_flash ? 3 : 0; g = 3; b = 3; end 
            else if (is_target) begin r = 3; g = 3; b = 3; end 
            else if (maze_wall) begin
                if (maze_flash)      begin r = 3; g = 3; b = 0; end
                else if (brick_hi)   begin r = 0; g = 3; b = 0; end
                else if (brick_lo)   begin r = 0; g = 1; b = 0; end
                else                 begin r = 0; g = 2; b = 0; end
            end else begin
                r = 0; g = 0; b = 0; 
            end
        end else if (app_hilb) begin
            if (draw_hilbert) begin r = hilbert_r; g = hilbert_g; b = hilbert_b; end 
            else begin r = 0; g = 0; b = 0; end
        end else begin
            if (draw_text) begin
                if (txt_row == 1)      begin r = 0; g = 1; b = 3; end 
                else if (txt_row == 3) begin r = 0; g = 3; b = 3; end 
                else                   begin r = 3; g = 3; b = 3; end
            end else if (art_draw_dlsu)   begin r = 0; g = 3; b = 0; end 
            else if (art_draw_shadow) begin r = 0; g = 1; b = 0; end 
            else if (outer_shield)    begin r = 3; g = 3; b = 3; end 
            else if (inner_pulse)     begin r = 1; g = 3; b = 1; end 
            else if (art_circuit)     begin r = 0; g = 1; b = 0; end 
            else                      begin r = 0; g = 0; b = 0; end 
        end
    end

    assign uo_out = {hsync, b[0], g[0], r[0], vsync, b[1], g[1], r[1]};

endmodule
