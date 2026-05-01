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
    wire _unused_ok = &{ena, ui_in[7:6], uio_in};

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
    // 2. APP 1: HARDWARE LOGIC MAZE (Optimized ROM Usage)
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

    // ROM INSTANCE 1: For VGA Rendering
    wire maze_wall = is_wall_at(gx, gy);

    reg [3:0] btn_state, btn_prev;
    always @(posedge clk) begin
        if (reset) begin btn_state <= 0; btn_prev <= 0; end 
        else if (frame_tick) begin btn_state <= ui_in[4:1]; btn_prev <= btn_state; end
    end

    wire move_up    = btn_state[0] & ~btn_prev[0]; wire move_down  = btn_state[1] & ~btn_prev[1];
    wire move_left  = btn_state[2] & ~btn_prev[2]; wire move_right = btn_state[3] & ~btn_prev[3];

    reg maze_state; reg [4:0] px, py; reg [7:0] win_timer;

    // --- OPTIMIZATION: Condense 4 ROM instances into 1 by pre-calculating the target ---
    wire move_any = move_up | move_down | move_left | move_right;
    wire [4:0] try_x = move_up ? px : (move_down ? px : (move_left ? px - 1 : (move_right ? px + 1 : px)));
    wire [4:0] try_y = move_up ? py - 1 : (move_down ? py + 1 : py);
    
    // ROM INSTANCE 2: Single lookup for movement collision
    wire valid_move = !is_wall_at(try_x, try_y);

    always @(posedge clk) begin
        if (reset) begin
            maze_state <= 0; px <= 5'd1; py <= 5'd1; win_timer <= 0;
        end else if (app_maze) begin 
            if (maze_state == 0) begin
                if (px == 5'd9 && py == 5'd7) begin maze_state <= 1; win_timer <= 0; end 
                else if (frame_tick && move_any && valid_move) begin
                    // Only apply if the pre-calculated target is free
                    px <= try_x;
                    py <= try_y;
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
    // 3. APP 2: TRUE HILBERT CURVE (Optimized Shifter)
    // =========================================================
    reg [2:0] cur_order; reg [9:0] anim_timer; reg [5:0] pause_timer;
    
    // --- OPTIMIZATION: Replaced expensive Barrel Shifter with simple LUT ---
    reg [9:0] max_d;
    always @(*) begin
        case(cur_order)
            1: max_d = 10'd3;
            2: max_d = 10'd15;
            3: max_d = 10'd63;
            4: max_d = 10'd255;
            5: max_d = 10'd1023;
            default: max_d = 10'd3;
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
            cx2 = (ry3 == 0) ? (rx3 ? ~hy[2:0] : hy[2:0]) : hx[2:0];
            cy2 = (ry3 == 0) ? (rx3 ? ~hx[2:0] : hx[2:0]) : hy[2:0];
            
            rx2 = cx2[2]; ry2 = cy2[2]; d2 = {rx2, rx2^ry2};
            cx1 = (ry2 == 0) ? (rx2 ? ~cy2[1:0] : cy2[1:0]) : cx2[1:0];
            cy1 = (ry2 == 0) ? (rx2 ? ~cx2[1:0] : cx2[1:0]) : cy2[1:0];
            
            rx1 = cx1[1]; ry1 = cy1[1]; d1 = {rx1, rx1^ry1};
            cx0 = (ry1 == 0) ? (rx1 ? ~cy1[0] : cy1[0]) : cx1[0];
            cy0 = (ry1 == 0) ? (rx1 ? ~cx1[0] : cx1[0]) : cy1[0];
            
            rx0 = cx0[0]; ry0 = cy0[0]; d0 = {rx0, rx0^ry0};
            hilbert_d = {d3, d2, d1, d0};
        end
    endfunction

    wire in_hilbert_bounds = (h_cnt >= 192 && h_cnt < 448) && (v_cnt >= 112 && v_cnt < 368);
    wire [7:0] local_x = h_cnt[7:0] - 8'd192; 
    wire [7:0] local_y = v_cnt[7:0] - 8'd112;
    wire [3:0] cell_x = local_x[7:4]; wire [3:0] cell_y = local_y[7:4];
    wire [3:0] sub_x  = local_x[3:0]; wire [3:0] sub_y  = local_y[3:0];

    wire [7:0] d_curr = hilbert_d(cell_x, cell_y);
    reg  [3:0] nx, ny; reg valid_neighbor;

    always @(*) begin
        valid_neighbor = 1'b1;
        if (sub_x > 9)      begin nx = cell_x + 1; ny = cell_y; if (cell_x == 15) valid_neighbor = 1'b0; end
        else if (sub_x < 6) begin nx = cell_x - 1; ny = cell_y; if (cell_x == 0)  valid_neighbor = 1'b0; end
        else if (sub_y > 9) begin nx = cell_x; ny = cell_y + 1; if (cell_y == 15) valid_neighbor = 1'b0; end
        else if (sub_y < 6) begin nx = cell_x; ny = cell_y - 1; if (cell_y == 0)  valid_neighbor = 1'b0; end
        else                begin nx = cell_x; ny = cell_y; end
    end

    wire [7:0] d_neighbor = hilbert_d(nx, ny);
    wire is_center = (sub_x >= 6 && sub_x <= 9) && (sub_y >= 6 && sub_y <= 9);
    wire is_arm    = !is_center;
    wire connected = (d_neighbor == d_curr + 1) || (d_curr == d_neighbor + 1);
    wire [7:0] active_d = (anim_timer > 255) ? 255 : anim_timer[7:0];
    wire draw_hilbert = in_hilbert_bounds && (d_curr <= active_d) &&
                        (is_center || (is_arm && valid_neighbor && connected && d_neighbor <= active_d));

    wire [1:0] hilbert_r = (d_curr[5:4] + frame_cnt[6:5]);
    wire [1:0] hilbert_g = (d_curr[6:5] + frame_cnt[5:4]);
    wire [1:0] hilbert_b = 2'b11; 

    // =========================================================
    // 4. SHARED DESMOS ENGINE (Math + Coordinate Origins)
    // =========================================================
    wire signed [10:0] cx = $signed({1'b0, h_cnt}) - 320;
    wire signed [10:0] cy = $signed({1'b0, v_cnt}) - 240;

    wire [9:0] abs_x = (cx[10]) ? -cx[9:0] : cx[9:0];
    wire [9:0] abs_y = (cy[10]) ? -cy[9:0] : cy[9:0];

    // =========================================================
    // 5. DEFAULT APP: GALVANTRONIX SHIELD & CIRCUIT MOTIF
    // =========================================================
    wire [4:0] pan_x = h_cnt[4:0] - frame_cnt[6:2]; 
    wire [4:0] pan_y = v_cnt[4:0] - frame_cnt[6:2]; 
    
    wire trace_h = (pan_y == 0) && (h_cnt[6] ^ v_cnt[7]); 
    wire trace_v = (pan_x == 0) && (v_cnt[6] ^ h_cnt[7]);
    wire via_pad = (pan_x < 4) && (pan_y < 4) && (h_cnt[7] ^ v_cnt[7]);
    wire art_circuit = trace_h || trace_v || via_pad;

    wire outer_shield = (abs_x + abs_y > 160) && (abs_x + abs_y < 164);
    wire [6:0] pulse = frame_cnt[7] ? ~frame_cnt[6:0] : frame_cnt[6:0];
    wire [9:0] p_add = {3'b0, pulse};
    wire inner_pulse = (abs_x + abs_y > 10'd80 + p_add) && (abs_x + abs_y < 10'd84 + p_add);

    wire letter_D = (cx > -110 && cx < -70 && abs_y < 40) && !(cx > -100 && cx < -80 && abs_y < 20);
    wire letter_L = (cx > -50  && cx < -10 && abs_y < 40) && !(cx > -30  && cx < -10 && cy < 20);
    wire letter_S = (cx > 10   && cx < 50  && abs_y < 40) && !(cx > 30   && cx < 50  && cy > -20 && cy < 0) && !(cx > 10 && cx < 30 && cy > 0 && cy < 20);
    wire letter_U = (cx > 70   && cx < 110 && abs_y < 40) && !(cx > 80   && cx < 100 && cy < 20);
    wire art_draw_dlsu = letter_D || letter_L || letter_S || letter_U;

    wire signed [10:0] sx = cx - 11'sd6; wire signed [10:0] sy = cy - 11'sd6; 
    wire [9:0] abs_sy = (sy[10]) ? -sy[9:0] : sy[9:0];
    wire shadow_D = (sx > -110 && sx < -70 && abs_sy < 40) && !(sx > -100 && sx < -80 && abs_sy < 20);
    wire shadow_L = (sx > -50  && sx < -10 && abs_sy < 40) && !(sx > -30  && sx < -10 && sy < 20);
    wire shadow_S = (sx > 10   && sx < 50  && abs_sy < 40) && !(sx > 30   && sx < 50  && sy > -20 && sy < 0) && !(sx > 10 && sx < 30 && sy > 0 && sy < 20);
    wire shadow_U = (sx > 70   && sx < 110 && abs_sy < 40) && !(sx > 80   && sx < 100 && sy < 20);
    wire art_draw_shadow = (shadow_D || shadow_L || shadow_S || shadow_U) && !art_draw_dlsu;

    // =========================================================
    // 6. SHARED TEXT ENGINE
    // =========================================================
    wire [5:0] txt_row = v_cnt[9:4]; 
    wire [5:0] txt_col = h_cnt[9:4]; 
    wire [2:0] txt_px  = h_cnt[3:1]; 
    wire [2:0] txt_py  = v_cnt[3:1];

    reg [7:0] txt_char;
    always @(*) begin
        txt_char = 8'h20;
        if (!app_maze && !app_hilb) begin
            case (txt_row)
                6'd01: case(txt_col) 14:txt_char="G"; 15:txt_char="a"; 16:txt_char="l"; 17:txt_char="v"; 18:txt_char="a"; 19:txt_char="n"; 20:txt_char="t"; 21:txt_char="r"; 22:txt_char="o"; 23:txt_char="n"; 24:txt_char="i"; 25:txt_char="x"; default:; endcase
                6'd03: case(txt_col) 11:txt_char="C"; 12:txt_char="r"; 13:txt_char="a"; 14:txt_char="n"; 15:txt_char="k"; 17:txt_char="u"; 18:txt_char="p"; 20:txt_char="t"; 21:txt_char="h"; 22:txt_char="e"; 24:txt_char="p"; 25:txt_char="o"; 26:txt_char="w"; 27:txt_char="e"; 28:txt_char="r"; default:; endcase
                6'd26: case(txt_col) 5:txt_char="M"; 6:txt_char="a"; 7:txt_char="d"; 8:txt_char="e"; 10:txt_char="b"; 11:txt_char="y"; 13:txt_char="C"; 14:txt_char="h"; 15:txt_char="i"; 16:txt_char="c"; 17:txt_char="o"; 19:txt_char="A"; 20:txt_char="n"; 21:txt_char="d"; 22:txt_char="r"; 23:txt_char="e"; 25:txt_char="G"; 26:txt_char="."; 28:txt_char="O"; 29:txt_char="l"; 30:txt_char="a"; 31:txt_char="g"; 32:txt_char="u"; 33:txt_char="e"; 34:txt_char="r"; default:; endcase
                6'd28: case(txt_col) 11:txt_char="B"; 12:txt_char="S"; 13:txt_char="M"; 14:txt_char="S"; 16:txt_char="E"; 17:txt_char="C"; 18:txt_char="E"; 20:txt_char="B"; 21:txt_char="a"; 22:txt_char="t"; 23:txt_char="c"; 24:txt_char="h"; 26:txt_char="1"; 27:txt_char="2"; 28:txt_char="2"; default:; endcase
                default: ; 
            endcase
        end
    end

    reg [7:0] txt_font;
    always @(*) begin
        case(txt_char)
            "A": case(txt_py) 0:txt_font=8'h18; 1:txt_font=8'h3C; 2:txt_font=8'h66; 3:txt_font=8'h66; 4:txt_font=8'h7E; 5:txt_font=8'h66; 6:txt_font=8'h66; default:txt_font=0; endcase
            "B": case(txt_py) 0:txt_font=8'hFC; 1:txt_font=8'h66; 2:txt_font=8'h66; 3:txt_font=8'h7C; 4:txt_font=8'h66; 5:txt_font=8'h66; 6:txt_font=8'hFC; default:txt_font=0; endcase
            "C": case(txt_py) 0:txt_font=8'h3C; 1:txt_font=8'h66; 2:txt_font=8'h60; 3:txt_font=8'h60; 4:txt_font=8'h60; 5:txt_font=8'h66; 6:txt_font=8'h3C; default:txt_font=0; endcase
            "E": case(txt_py) 0:txt_font=8'hFE; 1:txt_font=8'h62; 2:txt_font=8'h68; 3:txt_font=8'h78; 4:txt_font=8'h68; 5:txt_font=8'h62; 6:txt_font=8'hFE; default:txt_font=0; endcase
            "G": case(txt_py) 0:txt_font=8'h3C; 1:txt_font=8'h66; 2:txt_font=8'h60; 3:txt_font=8'h6E; 4:txt_font=8'h66; 5:txt_font=8'h66; 6:txt_font=8'h3E; default:txt_font=0; endcase
            "M": case(txt_py) 0:txt_font=8'hC6; 1:txt_font=8'hEE; 2:txt_font=8'hFE; 3:txt_font=8'hF6; 4:txt_font=8'hC6; 5:txt_font=8'hC6; 6:txt_font=8'hC6; default:txt_font=0; endcase
            "O": case(txt_py) 0:txt_font=8'h3C; 1:txt_font=8'h66; 2:txt_font=8'h66; 3:txt_font=8'h66; 4:txt_font=8'h66; 5:txt_font=8'h66; 6:txt_font=8'h3C; default:txt_font=0; endcase
            "S": case(txt_py) 0:txt_font=8'h3E; 1:txt_font=8'h60; 2:txt_font=8'h60; 3:txt_font=8'h3C; 4:txt_font=8'h06; 5:txt_font=8'h06; 6:txt_font=8'h7C; default:txt_font=0; endcase
            "a": case(txt_py) 2:txt_font=8'h3C; 3:txt_font=8'h06; 4:txt_font=8'h3E; 5:txt_font=8'h66; 6:txt_font=8'h3E; default:txt_font=0; endcase
            "b": case(txt_py) 0:txt_font=8'h60; 1:txt_font=8'h60; 2:txt_font=8'h7C; 3:txt_font=8'h66; 4:txt_font=8'h66; 5:txt_font=8'h66; 6:txt_font=8'h7C; default:txt_font=0; endcase
            "c": case(txt_py) 2:txt_font=8'h3C; 3:txt_font=8'h66; 4:txt_font=8'h60; 5:txt_font=8'h66; 6:txt_font=8'h3C; default:txt_font=0; endcase
            "d": case(txt_py) 0:txt_font=8'h06; 1:txt_font=8'h06; 2:txt_font=8'h3E; 3:txt_font=8'h66; 4:txt_font=8'h66; 5:txt_font=8'h66; 6:txt_font=8'h3E; default:txt_font=0; endcase
            "e": case(txt_py) 2:txt_font=8'h3C; 3:txt_font=8'h66; 4:txt_font=8'h7E; 5:txt_font=8'h60; 6:txt_font=8'h3C; default:txt_font=0; endcase
            "g": case(txt_py) 2:txt_font=8'h3E; 3:txt_font=8'h66; 4:txt_font=8'h66; 5:txt_font=8'h3E; 6:txt_font=8'h06; 7:txt_font=8'h3C; default:txt_font=0; endcase
            "h": case(txt_py) 0:txt_font=8'h60; 1:txt_font=8'h60; 2:txt_font=8'h7C; 3:txt_font=8'h66; 4:txt_font=8'h66; 5:txt_font=8'h66; 6:txt_font=8'hE6; default:txt_font=0; endcase
            "i": case(txt_py) 0:txt_font=8'h18; 2:txt_font=8'h38; 3:txt_font=8'h18; 4:txt_font=8'h18; 5:txt_font=8'h18; 6:txt_font=8'h3C; default:txt_font=0; endcase
            "k": case(txt_py) 0:txt_font=8'h60; 1:txt_font=8'h60; 2:txt_font=8'h66; 3:txt_font=8'h6C; 4:txt_font=8'h78; 5:txt_font=8'h6C; 6:txt_font=8'h66; default:txt_font=0; endcase
            "l": case(txt_py) 0:txt_font=8'h38; 1:txt_font=8'h18; 2:txt_font=8'h18; 3:txt_font=8'h18; 4:txt_font=8'h18; 5:txt_font=8'h18; 6:txt_font=8'h3C; default:txt_font=0; endcase
            "n": case(txt_py) 2:txt_font=8'h7C; 3:txt_font=8'h66; 4:txt_font=8'h66; 5:txt_font=8'h66; 6:txt_font=8'hE6; default:txt_font=0; endcase
            "o": case(txt_py) 2:txt_font=8'h3C; 3:txt_font=8'h66; 4:txt_font=8'h66; 5:txt_font=8'h66; 6:txt_font=8'h3C; default:txt_font=0; endcase
            "p": case(txt_py) 2:txt_font=8'h7C; 3:txt_font=8'h66; 4:txt_font=8'h66; 5:txt_font=8'h7C; 6:txt_font=8'h60; 7:txt_font=8'h60; default:txt_font=0; endcase
            "r": case(txt_py) 2:txt_font=8'h5C; 3:txt_font=8'h66; 4:txt_font=8'h60; 5:txt_font=8'h60; 6:txt_font=8'hF0; default:txt_font=0; endcase
            "t": case(txt_py) 0:txt_font=8'h30; 1:txt_font=8'h30; 2:txt_font=8'hFC; 3:txt_font=8'h30; 4:txt_font=8'h30; 5:txt_font=8'h34; 6:txt_font=8'h18; default:txt_font=0; endcase
            "u": case(txt_py) 2:txt_font=8'h66; 3:txt_font=8'h66; 4:txt_font=8'h66; 5:txt_font=8'h66; 6:txt_font=8'h3A; default:txt_font=0; endcase
            "v": case(txt_py) 2:txt_font=8'h66; 3:txt_font=8'h66; 4:txt_font=8'h66; 5:txt_font=8'h3C; 6:txt_font=8'h18; default:txt_font=0; endcase
            "w": case(txt_py) 2:txt_font=8'hC6; 3:txt_font=8'hC6; 4:txt_font=8'hD6; 5:txt_font=8'hFE; 6:txt_font=8'h6C; default:txt_font=0; endcase
            "x": case(txt_py) 2:txt_font=8'h66; 3:txt_font=8'h3C; 4:txt_font=8'h18; 5:txt_font=8'h3C; 6:txt_font=8'h66; default:txt_font=0; endcase
            "y": case(txt_py) 2:txt_font=8'h66; 3:txt_font=8'h66; 4:txt_font=8'h66; 5:txt_font=8'h3E; 6:txt_font=8'h06; 7:txt_font=8'h3C; default:txt_font=0; endcase
            "1": case(txt_py) 0:txt_font=8'h18; 1:txt_font=8'h38; 2:txt_font=8'h78; 3:txt_font=8'h18; 4:txt_font=8'h18; 5:txt_font=8'h18; 6:txt_font=8'h7E; default:txt_font=0; endcase
            "2": case(txt_py) 0:txt_font=8'h3C; 1:txt_font=8'h66; 2:txt_font=8'h06; 3:txt_font=8'h0C; 4:txt_font=8'h18; 5:txt_font=8'h30; 6:txt_font=8'h7E; default:txt_font=0; endcase
            ".": case(txt_py) 5:txt_font=8'h18; 6:txt_font=8'h18; default:txt_font=0; endcase
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
            // -----------------------------------------------------
            // RENDER: MAZE GAME
            // -----------------------------------------------------
            if (maze_draw_text) begin
                r = maze_flash ? 3 : 0; g = 3; b = maze_flash ? 3 : 0; 
            end else if (is_player) begin
                r = maze_flash ? 3 : 0; g = 3; b = 3;
            end else if (is_target) begin
                r = 3; g = 3; b = 3; 
            end else if (maze_wall) begin
                if (maze_flash) begin r = 3; g = 3; b = 0; end
                else if (brick_hi) begin r = 0; g = 3; b = 0; end
                else if (brick_lo) begin r = 0; g = 1; b = 0; end
                else begin r = 0; g = 2; b = 0; end
            end else begin
                r = 0; g = 0; b = 0; 
            end
        end else if (app_hilb) begin
            // -----------------------------------------------------
            // RENDER: HILBERT CURVE
            // -----------------------------------------------------
            if (draw_hilbert) begin
                r = hilbert_r; g = hilbert_g; b = hilbert_b;
            end else begin
                r = 0; g = 0; b = 0;
            end
        end else begin
            // -----------------------------------------------------
            // RENDER: GALVANTRONIX SHIELD / CIRCUIT MOTIF (Default)
            // -----------------------------------------------------
            if (draw_text) begin
                if (txt_row == 1) begin 
                    r = 0; g = 1; b = 3; 
                end else if (txt_row == 3) begin 
                    r = 0; g = 3; b = 3; 
                end else if (txt_row > 20) begin 
                    r = 3; g = 3; b = 3; 
                end else begin
                    r = 3; g = 3; b = 3; 
                end
            end else if (art_draw_dlsu) begin 
                r = 0; g = 3; b = 0; 
            end else if (art_draw_shadow) begin 
                r = 0; g = 1; b = 0; 
            end else if (outer_shield) begin 
                r = 3; g = 3; b = 3; 
            end else if (inner_pulse) begin 
                r = 1; g = 3; b = 1; 
            end else if (art_circuit) begin 
                r = 0; g = 1; b = 0; 
            end else begin 
                r = 0; g = 0; b = 0; 
            end
        end
    end

    assign uo_out = {hsync, b[0], g[0], r[0], vsync, b[1], g[1], r[1]};

endmodule
