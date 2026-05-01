`default_nettype none

module tt_um_AlephNaNsea_decentvgachipIEEEIESIPSPH (
    input  wire [7:0] ui_in,    // Unused
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
    wire _unused_ok = &{ena, ui_in, uio_in}; // ui_in[0] no longer needed for toggle

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

    // =========================================================
    // 2. SHARED DESMOS ENGINE (Math + Coordinate Origins)
    // =========================================================
    wire signed [10:0] cx = $signed({1'b0, h_cnt}) - 320;
    wire signed [10:0] cy = $signed({1'b0, v_cnt}) - 240;
    
    wire [9:0] abs_x = (cx[10]) ? -cx[9:0] : cx[9:0];
    wire [9:0] abs_y = (cy[10]) ? -cy[9:0] : cy[9:0];

    // =========================================================
    // 3. BACKGROUND: SCROLLING CIRCUIT BOARD MOTIF
    // =========================================================
    wire [5:0] pan_x = h_cnt[5:0] - frame_cnt[7:2]; 
    wire [5:0] pan_y = v_cnt[5:0] - frame_cnt[7:2]; 
    
    // Instead of a solid grid, we use XOR logic to create broken traces and vias (solder pads)
    wire trace_h = (pan_y[4:0] == 0) && (h_cnt[6] ^ v_cnt[7]); 
    wire trace_v = (pan_x[4:0] == 0) && (v_cnt[6] ^ h_cnt[7]);
    wire via_pad = (pan_x[4:0] < 4) && (pan_y[4:0] < 4) && (h_cnt[7] ^ v_cnt[7]);
    
    wire art_circuit = trace_h || trace_v || via_pad;

    // =========================================================
    // 4. FOREGROUND: DLSU SHIELD
    // =========================================================
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
    // 5. TEXT ENGINE
    // =========================================================
    wire [5:0] txt_row = v_cnt[9:4]; 
    wire [5:0] txt_col = h_cnt[9:4]; 
    wire [2:0] txt_px  = h_cnt[3:1]; 
    wire [2:0] txt_py  = v_cnt[3:1];
    
    reg [7:0] txt_char;
    always @(*) begin
        txt_char = 8'h20; // Space
        case (txt_row)
            // Title
            6'd01: case(txt_col) 14:txt_char="G"; 15:txt_char="a"; 16:txt_char="l"; 17:txt_char="v"; 18:txt_char="a"; 19:txt_char="n"; 20:txt_char="t"; 21:txt_char="r"; 22:txt_char="o"; 23:txt_char="n"; 24:txt_char="i"; 25:txt_char="x"; default:; endcase
            // Motto
            6'd03: case(txt_col) 11:txt_char="C"; 12:txt_char="r"; 13:txt_char="a"; 14:txt_char="n"; 15:txt_char="k"; 17:txt_char="u"; 18:txt_char="p"; 20:txt_char="t"; 21:txt_char="h"; 22:txt_char="e"; 24:txt_char="p"; 25:txt_char="o"; 26:txt_char="w"; 27:txt_char="e"; 28:txt_char="r"; default:; endcase
            // Credits
            6'd26: case(txt_col) 5:txt_char="M"; 6:txt_char="a"; 7:txt_char="d"; 8:txt_char="e"; 10:txt_char="b"; 11:txt_char="y"; 13:txt_char="C"; 14:txt_char="h"; 15:txt_char="i"; 16:txt_char="c"; 17:txt_char="o"; 19:txt_char="A"; 20:txt_char="n"; 21:txt_char="d"; 22:txt_char="r"; 23:txt_char="e"; 25:txt_char="G"; 26:txt_char="."; 28:txt_char="O"; 29:txt_char="l"; 30:txt_char="a"; 31:txt_char="g"; 32:txt_char="u"; 33:txt_char="e"; 34:txt_char="r"; default:; endcase
            6'd28: case(txt_col) 11:txt_char="B"; 12:txt_char="S"; 13:txt_char="M"; 14:txt_char="S"; 16:txt_char="E"; 17:txt_char="C"; 18:txt_char="E"; 20:txt_char="B"; 21:txt_char="a"; 22:txt_char="t"; 23:txt_char="c"; 24:txt_char="h"; 26:txt_char="1"; 27:txt_char="2"; 28:txt_char="2"; default:; endcase
            default: ; 
        endcase
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
    // 6. TOP-LEVEL COLOR MULTIPLEXER
    // =========================================================
    reg [1:0] r, g, b;

    always @(*) begin
        if (!display_on) begin
            r = 0; g = 0; b = 0;
        end else if (draw_text) begin
            // Text Coloring Logic
            if (txt_row == 1) begin 
                r = 0; g = 1; b = 3; // Galvantronix (Bright Blue)
            end else if (txt_row == 3) begin 
                r = 0; g = 3; b = 3; // Crank up the power (Cyan)
            end else if (txt_row > 20) begin 
                r = 3; g = 3; b = 3; // Credits (White)
            end else begin
                r = 3; g = 3; b = 3; // Fallback
            end
        end else if (art_draw_dlsu) begin 
            r = 0; g = 3; b = 0; // Shield fill
        end else if (art_draw_shadow) begin 
            r = 0; g = 1; b = 0; // Shield shadow
        end else if (outer_shield) begin 
            r = 3; g = 3; b = 3; // Outer ring
        end else if (inner_pulse) begin 
            r = 1; g = 3; b = 1; // Pulsing ring
        end else if (art_circuit) begin 
            r = 0; g = 1; b = 0; // Circuit traces background (Dark Green)
        end else begin 
            r = 0; g = 0; b = 0; // Black space
        end
    end

    assign uo_out = {hsync, b[0], g[0], r[0], vsync, b[1], g[1], r[1]};

endmodule
