// Copyright (c) 2021 Sungkyunkwan University
//
// Authors:
// - Jungrae Kim <dale40@skku.edu>

module DMAC_ARBITER
#(
    N_MASTER                    = 4,
    DATA_SIZE                   = 32
)
(
    input   wire                clk,
    input   wire                rst_n,  // _n means active low

    // configuration registers
    input   wire                src_valid_i[N_MASTER],
    output  reg                 src_ready_o[N_MASTER],
    input   wire    [DATA_SIZE-1:0]     src_data_i[N_MASTER],

    output  reg                 dst_valid_o,
    input   wire                dst_ready_i,
    output  reg     [DATA_SIZE-1:0] dst_data_o
);

    reg [1:0]   grant_idx;
    reg [1:0]   rr_ptr;
    reg [1:0]   grant_idx_n;

    wire [3:0]  req = { src_valid_i[3],
                        src_valid_i[2],
                        src_valid_i[1],
                        src_valid_i[0] };

    always_comb begin
        grant_idx_n = grant_idx;

        if (|req) begin
            case (rr_ptr)
                2'd0: begin
                    if      (req[0]) grant_idx_n = 2'd0;
                    else if (req[1]) grant_idx_n = 2'd1;
                    else if (req[2]) grant_idx_n = 2'd2;
                    else if (req[3]) grant_idx_n = 2'd3;
                end
                2'd1: begin
                    if      (req[1]) grant_idx_n = 2'd1;
                    else if (req[2]) grant_idx_n = 2'd2;
                    else if (req[3]) grant_idx_n = 2'd3;
                    else if (req[0]) grant_idx_n = 2'd0;
                end
                2'd2: begin
                    if      (req[2]) grant_idx_n = 2'd2;
                    else if (req[3]) grant_idx_n = 2'd3;
                    else if (req[0]) grant_idx_n = 2'd0;
                    else if (req[1]) grant_idx_n = 2'd1;
                end
                2'd3: begin
                    if      (req[3]) grant_idx_n = 2'd3;
                    else if (req[0]) grant_idx_n = 2'd0;
                    else if (req[1]) grant_idx_n = 2'd1;
                    else if (req[2]) grant_idx_n = 2'd2;
                end
                default: begin
                    grant_idx_n = 2'd0;
                end
            endcase
        end
    end

    always_comb begin
        dst_valid_o       = 1'b0;
        dst_data_o        = {DATA_SIZE{1'b0}};
        src_ready_o[0]    = 1'b0;
        src_ready_o[1]    = 1'b0;
        src_ready_o[2]    = 1'b0;
        src_ready_o[3]    = 1'b0;

        if (src_valid_i[grant_idx_n]) begin
            dst_valid_o                 = 1'b1;
            dst_data_o                  = src_data_i[grant_idx_n];
            src_ready_o[grant_idx_n]    = dst_ready_i;
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            grant_idx   <= 2'd0;
            rr_ptr      <= 2'd0;
        end
        else begin
            grant_idx   <= grant_idx_n;

            if (dst_valid_o && dst_ready_i) begin
                rr_ptr <= grant_idx_n + 2'd1;
            end
        end
    end// TODO: implement your arbiter here

endmodule