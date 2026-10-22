`timescale 1ns / 1ps

// =============================================================================
// Feature Extraction Module (FIXED to match Python Reference - Output Q4.12)
// =============================================================================
module feature_extraction #(
    parameter DATA_IN_WIDTH  = 8,
    parameter DATA_OUT_WIDTH = 16,
    parameter NUM_SAMPLES    = 512,
    parameter FS             = 360 // Tần số lấy mẫu 360Hz
) (
    input  wire                              clk,
    input  wire                              rst_n,
    input  wire                              start_compute,
    input  wire [15:0]                       ppg_threshold,
    input  wire                              read_enable,
    output reg  [8:0]                        sample_addr,
    input  wire signed [DATA_IN_WIDTH-1:0]   sample_in,

    // Feature Output (12 features x 16-bit, chuẩn hóa toàn bộ ở định dạng Q4.12)
    output reg  signed [DATA_OUT_WIDTH-1:0] f_rms,        // Q4.12
    output reg  signed [DATA_OUT_WIDTH-1:0] f_var,        // Q4.12
    output reg  signed [DATA_OUT_WIDTH-1:0] f_peak,       // Q4.12
    output reg  signed [DATA_OUT_WIDTH-1:0] f_zc,         // Q4.12
    output reg  signed [DATA_OUT_WIDTH-1:0] f_ptp,        // Q4.12
    output reg  signed [DATA_OUT_WIDTH-1:0] f_crest,      // Q4.12 (Clipped at 15.0 = 61440)
    output reg  signed [DATA_OUT_WIDTH-1:0] f_half_ratio, // Q4.12
    output reg  signed [DATA_OUT_WIDTH-1:0] f_max,         // Q4.12 (Signed [-8.0, +7.999])
    output reg  signed [DATA_OUT_WIDTH-1:0] f_rr,          // Q4.12 (Seconds)
    output reg  signed [DATA_OUT_WIDTH-1:0] f_rr_prev,     // Q4.12 (Seconds)
    output reg  signed [DATA_OUT_WIDTH-1:0] f_rr_ratio,    // Q4.12
    output reg  signed [DATA_OUT_WIDTH-1:0] f_rr_diff,     // Q4.12 (Seconds, Signed)
    output reg                               feature_valid,
    output reg                               overflow
);

    // =============================================================================
    // 64-bit Integer Square Root Function (Combinational Non-Restoring)
    // Tính toán floor(sqrt(x)) cho đầu vào tới 64-bit, trả về căn bậc hai 32-bit
    // =============================================================================
    function [31:0] isqrt_64;
        input [63:0] x;
        reg [63:0] a;
        reg [31:0] q;
        reg [34:0] r;
        reg [33:0] test;
        integer i;
        begin
            a = x;
            q = 32'd0;
            r = 35'd0;
            for (i = 0; i < 32; i = i + 1) begin
                r = (r << 2) | a[63:62];
                a = a << 2;
                test = {q, 2'b01};
                if (r >= test) begin
                    r = r - test;
                    q = {q[30:0], 1'b1};
                end else begin
                    q = {q[30:0], 1'b0};
                end
            end
            isqrt_64 = q;
        end
    endfunction

    // =============================================================================
    // FSM States
    // =============================================================================
    localparam S_IDLE        = 4'd0;
    localparam S_ACCUMULATE  = 4'd1;
    localparam S_CALC_BASE   = 4'd2;
    localparam S_CALC_VAR    = 4'd3;
    localparam S_CALC_RMS    = 4'd4;
    localparam S_CALC_ADV    = 4'd5;
    localparam S_DONE        = 4'd6;

    reg [3:0] state;

    reg [9:0]         sample_cnt;
    reg signed [31:0] sum;
    reg signed [63:0] sum_square;
    reg signed [63:0] sum_sq_h1;
    reg signed [63:0] sum_sq_h2;

    reg signed [7:0]  max_reg;
    reg signed [7:0]  min_reg;
    reg [7:0]         peak_abs_reg; // Trị tuyệt đối lớn nhất

    reg [15:0]        zc_cnt;
    reg [1:0]         prev_sign;    // Mã hóa dấu: 2'b01 (>0), 2'b10 (<0), 2'b00 (==0)

    // RR Detection
    reg [15:0]        rr_timer;
    reg [15:0]        rr_current;
    reg [15:0]        rr_previous;
    reg               first_peak_found;
    reg signed [7:0]  sample_delayed;

    // Thanh ghi lưu trung gian cho RMS nửa cửa sổ
    reg [31:0]        rms_h1_q;
    reg [31:0]        rms_h2_q;

    // Helper wires
    wire [7:0]        abs_sample = (sample_in[7]) ? (~sample_in + 8'd1) : sample_in;
    wire signed [31:0] sample_sq = $signed(sample_in) * $signed(sample_in);
    wire [1:0]        curr_sign  = ($signed(sample_in) > 0) ? 2'b01 : 
                                   (($signed(sample_in) < 0) ? 2'b10 : 2'b00);

    // Tính phương sai Var_Q4.12 = (sum_sq << 3) - ((sum^2) >> 6)
    wire signed [63:0] sum_64    = $signed(sum);
    wire signed [63:0] var_term1 = sum_square <<< 3;
    wire signed [63:0] var_term2 = (sum_64 * sum_64) >>> 6;
    wire signed [63:0] var_diff  = (var_term1 > var_term2) ? (var_term1 - var_term2) : 64'sd0;

    // Tính căn RMS dạng Q4.12: sqrt(sum_sq / 512) * 4096 = sqrt(sum_sq * 2^15)
    wire [31:0] rms_full = isqrt_64(sum_square << 15);
    wire [31:0] h1_full  = isqrt_64(sum_sq_h1 << 16);
    wire [31:0] h2_full  = isqrt_64(sum_sq_h2 << 16);

    // Biến tạm tính toán
    reg [63:0]        crest_calc;
    reg [63:0]        ratio_calc;
    reg [63:0]        rr_calc;
    reg [63:0]        rr_prev_calc;
    reg [63:0]        rr_ratio_calc;
    reg signed [31:0] rr_diff_samples;
    reg signed [31:0] rr_diff_calc;
    reg signed [31:0] max_calc;
    reg [31:0]        peak_calc;
    reg [31:0]        ptp_calc;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state          <= S_IDLE;
            feature_valid  <= 1'b0;
            overflow       <= 1'b0;
            sample_addr    <= 9'd0;
            sample_cnt     <= 10'd0;
            sum            <= 32'sd0;
            sum_square     <= 64'sd0;
            sum_sq_h1      <= 64'sd0;
            sum_sq_h2      <= 64'sd0;
            max_reg        <= -8'sd128;
            min_reg        <= 8'sd127;
            peak_abs_reg   <= 8'd0;
            zc_cnt         <= 16'd0;
            prev_sign      <= 2'b00;
            rr_timer         <= 16'd0;
            rr_current       <= 16'd0;
            rr_previous      <= 16'd0;
            first_peak_found <= 1'b0;
            sample_delayed   <= 8'sd0;
            rms_h1_q       <= 32'd0;
            rms_h2_q       <= 32'd0;
            f_rms          <= 16'sd0;
            f_var          <= 16'sd0;
            f_peak         <= 16'sd0;
            f_zc           <= 16'sd0;
            f_ptp          <= 16'sd0;
            f_crest        <= 16'sd0;
            f_half_ratio   <= 16'sd0;
            f_max          <= 16'sd0;
            f_rr           <= 16'sd0;
            f_rr_prev      <= 16'sd0;
            f_rr_ratio     <= 16'sd0;
            f_rr_diff      <= 16'sd0;
        end else begin
            case (state)
                S_IDLE: begin
                    feature_valid <= 1'b0;
                    sample_addr   <= 9'd0;
                    sample_cnt    <= 10'd0;
                    if (start_compute) begin
                        state          <= S_ACCUMULATE;
                        overflow       <= 1'b0;
                        sum            <= 32'sd0;
                        sum_square     <= 64'sd0;
                        sum_sq_h1      <= 64'sd0;
                        sum_sq_h2      <= 64'sd0;
                        max_reg        <= -8'sd128;
                        min_reg        <= 8'sd127;
                        peak_abs_reg   <= 8'd0;
                        zc_cnt           <= 16'd0;
                        prev_sign        <= 2'b00;
                        rr_timer         <= 16'd0;
                        first_peak_found <= 1'b0;
                        sample_delayed   <= 8'sd0;
                    end
                end

                S_ACCUMULATE: begin
                    // 1. Tích lũy tổng và tổng bình phương
                    sum        <= sum + $signed(sample_in);
                    sum_square <= sum_square + sample_sq;

                    if (sample_cnt < 256)
                        sum_sq_h1 <= sum_sq_h1 + sample_sq;
                    else
                        sum_sq_h2 <= sum_sq_h2 + sample_sq;

                    // 2. Cập nhật Max, Min và Peak trị tuyệt đối
                    if (abs_sample > peak_abs_reg)
                        peak_abs_reg <= abs_sample;
                    if ($signed(sample_in) > max_reg)
                        max_reg <= $signed(sample_in);
                    if ($signed(sample_in) < min_reg)
                        min_reg <= $signed(sample_in);

                    // 3. Đếm Zero Crossing tương đương np.diff(np.sign(x)) != 0 trong Python
                    // Theo dõi 3 trạng thái (>0, <0, ==0)
                    if (sample_cnt > 0 && (curr_sign != prev_sign))
                        zc_cnt <= zc_cnt + 16'd1;
                    prev_sign <= curr_sign;

                    // 4. Phát hiện nhịp tim / RR peak (khoảng cách giữa 2 đỉnh liên tiếp thực sự)
                    if ($signed(sample_delayed) > $signed(ppg_threshold[7:0]) &&
                        $signed(sample_in) < $signed(sample_delayed) &&
                        rr_timer > 16'd50) begin
                        if (!first_peak_found) begin
                            // Đỉnh R đầu tiên trong cửa sổ: làm mốc bắt đầu đếm RR
                            first_peak_found <= 1'b1;
                            rr_timer         <= 16'd0;
                        end else begin
                            // Đỉnh R tiếp theo: timer đo chính xác khoảng cách giữa 2 đỉnh R liên tiếp
                            rr_previous <= (rr_current > 16'd0) ? rr_current : rr_timer;
                            rr_current  <= rr_timer;
                            rr_timer    <= 16'd0;
                        end
                    end else begin
                        rr_timer <= rr_timer + 16'd1;
                    end
                    sample_delayed <= sample_in;

                    // 5. Điều khiển địa chỉ mẫu và chuyển trạng thái
                    sample_cnt <= sample_cnt + 10'd1;
                    if (sample_cnt == NUM_SAMPLES - 1) begin
                        sample_addr <= 9'd0;
                        state       <= S_CALC_BASE;
                    end else begin
                        sample_addr <= sample_cnt[8:0] + 9'd1;
                    end
                end

                S_CALC_BASE: begin
                    // f_max: Chuẩn hóa Q4.12 có dấu: max_reg * 4096 (bão hòa [-8.0, +7.999])
                    max_calc = $signed(max_reg) <<< 12;
                    if (max_calc > 32'sd32767) begin
                        f_max    <= 16'sh7FFF;
                        overflow <= 1'b1;
                    end else if (max_calc < -32'sd32768) begin
                        f_max    <= -16'sh8000;
                        overflow <= 1'b1;
                    end else begin
                        f_max    <= max_calc[15:0];
                    end

                    // f_peak: Chuẩn hóa Q4.12: peak_abs_reg * 4096 (Clipped 15.0 = 61440)
                    peak_calc = {24'd0, peak_abs_reg} << 12;
                    if (peak_calc > 32'd61440) begin
                        f_peak   <= 16'd61440;
                        overflow <= 1'b1;
                    end else begin
                        f_peak   <= peak_calc[15:0];
                    end

                    // f_ptp: Chuẩn hóa Q4.12: (max - min) * 4096 (Clipped 15.0 = 61440)
                    ptp_calc = ($signed(max_reg) - $signed(min_reg)) <<< 12;
                    if (ptp_calc > 32'd61440) begin
                        f_ptp    <= 16'd61440;
                        overflow <= 1'b1;
                    end else begin
                        f_ptp    <= ptp_calc[15:0];
                    end

                    // f_zc: Chuẩn hóa Q4.12: zc_cnt / 512 * 4096 = zc_cnt * 8
                    f_zc <= zc_cnt <<< 3;

                    state <= S_CALC_VAR;
                end

                S_CALC_VAR: begin
                    // f_var: Chuẩn hóa Q4.12 chính xác: Var = E[x^2] - (E[x])^2
                    // Var_Q4.12 = (sum_square << 3) - ((sum^2) >> 6)
                    if (var_diff > 64'd61440) begin
                        f_var    <= 16'd61440;
                        overflow <= 1'b1;
                    end else begin
                        f_var    <= var_diff[15:0];
                    end

                    state <= S_CALC_RMS;
                end

                S_CALC_RMS: begin
                    // f_rms: Chuẩn hóa Q4.12: sqrt(sum_square / 512) * 4096 = isqrt(sum_square * 2^15)
                    if (rms_full > 32'd61440) begin
                        f_rms    <= 16'd61440;
                        overflow <= 1'b1;
                    end else begin
                        f_rms    <= rms_full[15:0];
                    end

                    // Lưu RMS của nửa đầu và nửa sau ở dạng Q4.12
                    rms_h1_q <= h1_full;
                    rms_h2_q <= h2_full;

                    state <= S_CALC_ADV;
                end

                S_CALC_ADV: begin
                    // 1. Crest Factor (Q4.12): (peak / rms) * 4096 = (peak_abs_reg << 24) / f_rms
                    if (f_rms > 0) begin
                        crest_calc = ({32'd0, peak_abs_reg} << 24) / {48'd0, f_rms[15:0]};
                        if (crest_calc > 64'd61440) begin
                            f_crest  <= 16'd61440;
                            overflow <= 1'b1;
                        end else begin
                            f_crest  <= crest_calc[15:0];
                        end
                    end else begin
                        f_crest <= 16'd0;
                    end

                    // 2. Half Ratio (Q4.12): (rms_h1 / rms_h2) * 4096 = (rms_h1_q << 12) / rms_h2_q
                    if (rms_h2_q > 0) begin
                        ratio_calc = ({32'd0, rms_h1_q[15:0]} << 12) / {32'd0, rms_h2_q};
                        if (ratio_calc > 64'd61440) begin
                            f_half_ratio <= 16'd61440;
                            overflow     <= 1'b1;
                        end else begin
                            f_half_ratio <= ratio_calc[15:0];
                        end
                    end else begin
                        f_half_ratio <= 16'd0;
                    end

                    // 3. RR to Seconds in Q4.12: (rr_current * 4096) / FS
                    rr_calc = ({32'd0, rr_current} << 12) / FS;
                    if (rr_calc > 64'd61440) begin
                        f_rr     <= 16'd61440;
                        overflow <= 1'b1;
                    end else begin
                        f_rr     <= rr_calc[15:0];
                    end

                    rr_prev_calc = ({32'd0, ((rr_previous > 16'd0) ? rr_previous : rr_current)} << 12) / FS;
                    if (rr_prev_calc > 64'd61440) begin
                        f_rr_prev <= 16'd61440;
                        overflow  <= 1'b1;
                    end else begin
                        f_rr_prev <= rr_prev_calc[15:0];
                    end

                    // 4. RR Ratio in Q4.12: (rr_current / rr_previous) * 4096
                    if (rr_previous > 0 || rr_current > 0) begin
                        rr_ratio_calc = ({32'd0, rr_current} << 12) / {48'd0, ((rr_previous > 16'd0) ? rr_previous : rr_current)};
                        if (rr_ratio_calc > 64'd61440) begin
                            f_rr_ratio <= 16'd61440;
                            overflow   <= 1'b1;
                        end else begin
                            f_rr_ratio <= rr_ratio_calc[15:0];
                        end
                    end else begin
                        f_rr_ratio <= 16'd4096; // 1.0 in Q4.12
                    end

                    // 5. RR Difference in Q4.12 (Signed): (rr_current - rr_previous) * 4096 / FS
                    rr_diff_samples = $signed({1'b0, rr_current}) - $signed({1'b0, ((rr_previous > 16'd0) ? rr_previous : rr_current)});
                    rr_diff_calc    = (rr_diff_samples * 32'sd4096) / $signed(FS);
                    if (rr_diff_calc > 32'sd32767) begin
                        f_rr_diff <= 16'sh7FFF;
                        overflow  <= 1'b1;
                    end else if (rr_diff_calc < -32'sd32768) begin
                        f_rr_diff <= -16'sh8000;
                        overflow  <= 1'b1;
                    end else begin
                        f_rr_diff <= rr_diff_calc[15:0];
                    end

                    state <= S_DONE;
                end

                S_DONE: begin
                    feature_valid <= 1'b1;
                    state         <= S_IDLE;
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
