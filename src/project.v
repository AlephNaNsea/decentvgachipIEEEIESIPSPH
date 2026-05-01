`default_nettype none

module tt_um_AlephNaNsea_decentvgachipIEEEIESIPSPH (
    input  wire [7:0] ui_in,    // [7:1]:Unused, [0]:Toggle (0=DLSU Shield, 1=Galvantronix)
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
    wire _unused_ok = &{ena, ui_in[7:1], uio_in};

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
    
    // Truncated to 8 bits to resolve the UNUSEDSIGNAL warning
    wire [7:0] frame_cnt = frame_counter[7:0]; 

    // Unified Mode Mux
    wire app_galv = ui_in[0];

    // =========================================================
    // 2. SHARED DESMOS ENGINE (Math + Coordinate Origins)
    // =========================================================
    wire signed [10:0] cx = $signed({1'b0, h_cnt}) - 320;
    wire signed [10:0] cy = $signed({1'b0, v_cnt}) - 240;
    
    // SAFE Absolute Values (Prevents signed-bit expansion bugs)
    wire [9:0] abs_x = (cx[10]) ? -cx[9:0] : cx[9:0];
    wire [9:0] abs_y = (cy[10]) ? -cy[9:0] : cy[9:0];

    // =========================================================
    // 3. APP 1: DLSU SHIELD (Default)
    // =========================================================
    // Explicit padding to prevent WIDTHEXPAND warning
    wire [5:0] pan_x = h_cnt[5:0] - frame_cnt[7:2]; 
    wire [5:0] pan_y = v_cnt[5:0] - frame_cnt[7:2]; 
    wire art_grid_lines = (pan_x == 0) || (pan_y == 0);
    wire art_axes = (abs_x < 2) || (abs_y < 2);

    wire outer_shield = (abs_x + abs_y > 160) && (abs_x + abs_y < 164);
    wire [6:0] pulse = frame_cnt[7] ? ~frame_cnt[6:0] : frame_cnt[6:0];
    wire [9:0] p_add = {3'b0, pulse};
    
    // Adjusted width to target the 169% requirement
    wire wider_blunt_diamond = (abs_x < 10'd169 && abs_y < 10'd80) && (abs_x + abs_y < 10'd200);

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
    // 4. APP 2: GALVANTRONIX HIGH-RES LOGO
    // =========================================================
    // Padded math variables for strict matching (Verilator WIDTHEXPAND fix)
    wire signed [13:0] cy_14 = $signed({{3{cy[10]}}, cy});
    wire signed [13:0] ax_14 = $signed({4'b0, abs_x});
    wire signed [14:0] cy_15 = $signed({{4{cy[10]}}, cy});
    wire signed [14:0] ax_15 = $signed({5'b0, abs_x});

    // Tightened Octagons (Eyes)
    wire [10:0] edx = (abs_x > 120) ? (abs_x - 10'd120) : (10'd120 - abs_x);
    wire [10:0] edy = (cy > -40) ? (cy + 10'd40) : -(cy + 10'd40);
    wire eye_outer = (edx < 45) && (edy < 45) && (edx + edy < 60);
    wire eye_inner = (edx < 37) && (edy < 37) && (edx + edy < 50);
    wire eye_slit  = eye_inner && (edy < 4) && (edx < 25);
    wire draw_eyes = (eye_outer && !eye_inner) || eye_slit;

    // Core Pentagon & Inner Lines
    wire signed [13:0] p_top_val = 3*cy_14 - 2*ax_14 + 14'sd270;
    wire [13:0] p_top = (p_top_val < 0) ? -p_top_val : p_top_val;
    wire p_top_line = (p_top < 16) && (abs_x <= 60) && (cy <= -50);

    wire signed [13:0] p_side_val = cy_14 + 4*ax_14 - 14'sd190;
    wire [13:0] p_side = (p_side_val < 0) ? -p_side_val : p_side_val;
    wire p_side_line = (p_side < 18) && (cy >= -50) && (cy <= 30);

    wire [10:0] p_bot = (cy > 30) ? (cy - 10'd30) : (10'd30 - cy);
    wire p_bot_line = (p_bot < 4) && (abs_x <= 40);

    wire core_sq = (abs_x < 22 && cy > -32 && cy < 7) && !(abs_x < 16 && cy > -26 && cy < 1);

    wire signed [13:0] inner1_val = 5*ax_14 + 7*cy_14 + 14'sd50;
    wire [13:0] inner1 = (inner1_val < 0) ? -inner1_val : inner1_val;
    wire draw_inner1 = (inner1 < 30) && (abs_x >= 22) && (abs_x <= 60) && (cy <= -25);

    wire signed [13:0] inner2_val = 4*ax_14 - 3*cy_14 - 14'sd70;
    wire [13:0] inner2 = (inner2_val < 0) ? -inner2_val : inner2_val;
    wire draw_inner2 = (inner2 < 20) && (abs_x >= 22) && (abs_x <= 40) && (cy >= 5);
    wire draw_inner3 = (abs_x < 4) && (cy > -90) && (cy < -32);

    wire draw_core = p_top_line || p_side_line || p_bot_line || core_sq || draw_inner1 || draw_inner2 || draw_inner3;

    // Striped Mouth
    wire mouth_area = (cy > 50 && cy < 110) && (cy_14 + 4*ax_14 < 14'sd170);
    wire mouth_outline = (cy >= 46 && cy <= 114) && (cy_14 + 4*ax_14 < 14'sd178) && !mouth_area;
    wire mouth_stripes = mouth_area && (cy[4:3] == 2'b00); 
    wire draw_mouth = mouth_outline || mouth_stripes;

    // Outer Frame (Strictly Bounded)
    wire signed [14:0] l1_val_s = 2*ax_15 + 15*cy_15 + 15'sd1800;
    wire [14:0] l1_val = (l1_val_s < 0) ? -l1_val_s : l1_val_s;
    wire l1 = (l1_val < 60) && (abs_x <= 150) && (cy <= -120);

    wire signed [14:0] l2_val_s = 8*ax_15 - 7*cy_15 - 15'sd2180;
    wire [14:0] l2_val = (l2_val_s < 0) ? -l2_val_s : l2_val_s;
    wire l2 = (l2_val < 45) && (abs_x >= 150) && (cy <= -60);

    wire signed [14:0] l3_val_s = 12*ax_15 + 7*cy_15 - 15'sd2220;
    wire [14:0] l3_val = (l3_val_s < 0) ? -l3_val_s : l3_val_s;
    wire l3 = (l3_val < 60) && (abs_x >= 150) && (cy > -60);

    wire [10:0] l4_val = (cy > 60) ? (cy - 10'd60) : (10'd60 - cy);
    wire l4 = (l4_val < 4) && (abs_x >= 100 && abs_x <= 150);

    wire signed [14:0] l5_val_s = 2*ax_15 + cy_15 - 15'sd260;
    wire [14:0] l5_val = (l5_val_s < 0) ? -l5_val_s : l5_val_s;
    wire l5 = (l5_val < 10) && (abs_x >= 60 && abs_x < 100);

    wire [10:0] l6_val = (cy > 140) ? (cy - 10'd140) : (10'd140 - cy);
    wire l6 = (l6_val < 4) && (abs_x <= 60);

    wire draw_frame = l1 || l2 || l3 || l4 || l5 || l6;

    // Cyber Nodes
    wire [4:0] pulse_r = 5'd6 + {3'b0, frame_cnt[4:3]}; 
    wire [10:0] pr_11 = {6'b0, pulse_r};
    wire [10:0] cy_120 = (cy > -120) ? (cy + 10'd120) : -(cy + 10'd120);
    wire [10:0] ax_150 = (abs_x > 150) ? (abs_x - 10'd150) : (10'd150 - abs_x);
    wire [10:0] cy_140 = (cy > -140) ? (cy + 10'd140) : -(cy + 10'd140);
    wire [10:0] ax_220 = (abs_x > 220) ? (abs_x - 10'd220) : (10'd220 - abs_x);
    wire [10:0] cy_60  = (cy > -60)  ? (cy + 10'd60)  : -(cy + 10'd60);
    wire [10:0] cyp_60 = (cy > 60)   ? (cy - 10'd60)  : (10'd60 - cy);
    wire [10:0] ax_100 = (abs_x > 100) ? (abs_x - 10'd100) : (10'd100 - abs_x);
    wire [10:0] ax_60  = (abs_x > 60)  ? (abs_x - 10'd60)  : (10'd60 - abs_x);
    wire [10:0] cyp_140= (cy > 140)  ? (cy - 10'd140) : (10'd140 - cy);
    
    wire draw_nodes = ((abs_x + cy_120) < pr_11) || ((ax_150 + cy_140) < pr_11) ||
                      ((ax_220 + cy_60) < pr_11) || ((ax_150 + cyp_60) < pr_11) ||
                      ((ax_100 + cyp_60) < pr_11) || ((ax_60 + cyp_140) < pr_11);

    wire draw_vector_logo = draw_eyes || draw_core || draw_mouth || draw_frame || draw_nodes;

    // =========================================================
    // 5. SHARED TEXT ENGINE
    // =========================================================
    wire [5:0] txt_row = v_cnt[9:4]; 
    wire [5:0] txt_col = h_cnt[9:4]; 
    wire [2:0] txt_px  = h_cnt[3:1]; 
    wire [2:0] txt_py  = v_cnt[3:1];
    
    reg [7:0] txt_char;
    always @(*) begin
        txt_char = 8'h20;
        if (app_galv) begin
            if (txt_row == 6'd26) begin
                case(txt_col) 14:txt_char="G"; 15:txt_char="a"; 16:txt_char="l"; 17:txt_char="v"; 18:txt_char="a"; 19:txt_char="n"; 20:txt_char="t"; 21:txt_char="r"; 22:txt_char="o"; 23:txt_char="n"; 24:txt_char="i"; 25:txt_char="x"; default:; endcase
            end
        end else begin
            case (txt_row)
                6'd01: case(txt_col) 13:txt_char="A"; 14:txt_char="n"; 15:txt_char="i"; 16:txt_char="m"; 17:txt_char="o"; 19:txt_char="L"; 20:txt_char="a"; 22:txt_char="S"; 23:txt_char="a"; 24:txt_char="l"; 25:txt_char="l"; 26:txt_char="e"; default:; endcase
                6'd02: begin
                    if (txt_col == 10) txt_char = "{"; 
                    else if (txt_col >= 11 && txt_col <= 28) txt_char = "-";
                    else if (txt_col == 29) txt_char = ">";
                end
                6'd26: case(txt_col) 5:txt_char="M"; 6:txt_char="a"; 7:txt_char="d"; 8:txt_char="e"; 10:txt_char="b"; 11:txt_char="y"; 13:txt_char="C"; 14:txt_char="h"; 15:txt_char="i"; 16:txt_char="c"; 17:txt_char="o"; 19:txt_char="A"; 20:txt_char="n"; 21:txt_char="d"; 22:txt_char="r"; 23:txt_char="e"; 25:txt_char="G"; 26:txt_char="."; 28:txt_char="O"; 29:txt_char="l"; 30:txt_char="a"; 31:txt_char="g"; 32:txt_char="u"; 33:txt_char="e"; 34:txt_char="r"; default:; endcase
                6'd28: case(txt_col) 11:txt_char="B"; 12:txt_char="S"; 13:txt_char="M"; 14:txt_char="S"; 16:txt_char="E"; 17:txt_char="C"; 18:txt_char="E"; 20:txt_char="B"; 21:txt_char="a"; 22:txt_char="t"; 23:txt_char="c"; 24:txt_char="h"; 26:txt_char="1"; 27:txt_char="2"; 28:txt_char="2"; default:; endcase
                default: ; // Satisfy CASEINCOMPLETE warning
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
            "L": case(txt_py) 0:txt_font=8'h60; 1:txt_font=8'h60; 2:txt_font=8'h60; 3:txt_font=8'h60; 4:txt_font=8'h60; 5:txt_font=8'h60; 6:txt_font=8'hFE; default:txt_font=0; endcase
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
            "l": case(txt_py) 0:txt_font=8'h38; 1:txt_font=8'h18; 2:txt_font=8'h18; 3:txt_font=8'h18; 4:txt_font=8'h18; 5:txt_font=8'h18; 6:txt_font=8'h3C; default:txt_font=0; endcase
            "m": case(txt_py) 2:txt_font=8'hEC; 3:txt_font=8'hFE; 4:txt_font=8'hF6; 5:txt_font=8'hD6; 6:txt_font=8'hC6; default:txt_font=0; endcase
            "n": case(txt_py) 2:txt_font=8'h7C; 3:txt_font=8'h66; 4:txt_font=8'h66; 5:txt_font=8'h66; 6:txt_font=8'hE6; default:txt_font=0; endcase
            "o": case(txt_py) 2:txt_font=8'h3C; 3:txt_font=8'h66; 4:txt_font=8'h66; 5:txt_font=8'h66; 6:txt_font=8'h3C; default:txt_font=0; endcase
            "r": case(txt_py) 2:txt_font=8'h5C; 3:txt_font=8'h66; 4:txt_font=8'h60; 5:txt_font=8'h60; 6:txt_font=8'hF0; default:txt_font=0; endcase
            "t": case(txt_py) 0:txt_font=8'h30; 1:txt_font=8'h30; 2:txt_font=8'hFC; 3:txt_font=8'h30; 4:txt_font=8'h30; 5:txt_font=8'h34; 6:txt_font=8'h18; default:txt_font=0; endcase
            "u": case(txt_py) 2:txt_font=8'h66; 3:txt_font=8'h66; 4:txt_font=8'h66; 5:txt_font=8'h66; 6:txt_font=8'h3A; default:txt_font=0; endcase
            "v": case(txt_py) 2:txt_font=8'h66; 3:txt_font=8'h66; 4:txt_font=8'h66; 5:txt_font=8'h3C; 6:txt_font=8'h18; default:txt_font=0; endcase
            "y": case(txt_py) 2:txt_font=8'h66; 3:txt_font=8'h66; 4:txt_font=8'h66; 5:txt_font=8'h3E; 6:txt_font=8'h06; 7:txt_font=8'h3C; default:txt_font=0; endcase
            "x": case(txt_py) 2:txt_font=8'h66; 3:txt_font=8'h3C; 4:txt_font=8'h18; 5:txt_font=8'h3C; 6:txt_font=8'h66; default:txt_font=0; endcase
            "1": case(txt_py) 0:txt_font=8'h18; 1:txt_font=8'h38; 2:txt_font=8'h78; 3:txt_font=8'h18; 4:txt_font=8'h18; 5:txt_font=8'h18; 6:txt_font=8'h7E; default:txt_font=0; endcase
            "2": case(txt_py) 0:txt_font=8'h3C; 1:txt_font=8'h66; 2:txt_font=8'h06; 3:txt_font=8'h0C; 4:txt_font=8'h18; 5:txt_font=8'h30; 6:txt_font=8'h7E; default:txt_font=0; endcase
            ".": case(txt_py) 5:txt_font=8'h18; 6:txt_font=8'h18; default:txt_font=0; endcase
            "{": case(txt_py) 1:txt_font=8'h82; 2:txt_font=8'h44; 3:txt_font=8'hFF; 4:txt_font=8'hFF; 5:txt_font=8'h44; 6:txt_font=8'h82; default:txt_font=0; endcase
            "-": case(txt_py) 3:txt_font=8'hFF; 4:txt_font=8'hFF; default:txt_font=0; endcase
            ">": case(txt_py) 1:txt_font=8'hC0; 2:txt_font=8'hF0; 3:txt_font=8'hFC; 4:txt_font=8'hFC; 5:txt_font=8'hF0; 6:txt_font=8'hC0; default:txt_font=0; endcase
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
        end else if (app_galv) begin
            // -----------------------------------------------------
            // RENDER: GALVANTRONIX
            // -----------------------------------------------------
            if (draw_vector_logo || draw_text) begin r = 0; g = 2; b = 3; end 
            else begin r = 0; g = 0; b = 0; end
        end else begin
            // -----------------------------------------------------
            // RENDER: DLSU SHIELD (Default mode)
            // -----------------------------------------------------
            if (draw_text) begin
                if (txt_row < 3) begin r = 3; g = 3; b = 3; end 
                else begin r = 0; g = 3; b = 0; end
            end else if (art_draw_dlsu) begin 
                r = 0; g = 3; b = 0; 
            end else if (art_draw_shadow) begin 
                r = 0; g = 1; b = 0; 
            end else if (outer_shield) begin 
                r = 3; g = 3; b = 3; 
            end else if (wider_blunt_diamond) begin 
                r = 3; g = 3; b = 3; 
            end else if (art_axes) begin 
                r = 0; g = 2; b = 0; 
            end else if (art_grid_lines) begin 
                r = 0; g = 1; b = 0; 
            end else begin 
                r = 0; g = 0; b = 0; 
            end
        end
    end

    assign uo_out = {hsync, b[0], g[0], r[0], vsync, b[1], g[1], r[1]};

endmodule
