//
// Copyright (c) 2023 Sungkyunkwan University
//
// Authors:
// - Jungrae Kim <dale40@skku.edu>
module DMAC_INITIATOR
(
    input   wire                clk,
    input   wire                rst_n,

    input   wire    [31:0]      src_addr_i,
    input   wire    [31:0]      dst_addr_i,
    input   wire    [15:0]      byte_len_i,
    input   wire                start_i,
    output  reg                 done_o,

    output  wire    [31:0]      araddr_o,
    output  wire    [3:0]       arlen_o,
    output  wire    [2:0]       arsize_o,
    output  wire    [1:0]       arburst_o,
    output  reg                 arvalid_o,
    input   wire                arready_i,

    input   wire                bvalid_i,
    output  wire                bready_o,

    input   wire                fifo_full_i,
    output  wire    [31:0]      meta_awaddr_o,
    output  wire    [3:0]       meta_awlen_o,
    output  reg                 meta_awvalid_o
);

    localparam  S_IDLE = 2'd0,
                S_RUN  = 2'd1,
                S_WAIT = 2'd2;

    reg [1:0]   state, state_n;

    reg [31:0]  src_addr, src_addr_n;
    reg [31:0]  dst_addr, dst_addr_n;
    reg [15:0]  cnt,      cnt_n;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state    <= S_IDLE;
            src_addr <= 32'd0;
            dst_addr <= 32'd0;
            cnt      <= 16'd0;
        end
        else begin
            state    <= state_n;
            src_addr <= src_addr_n;
            dst_addr <= dst_addr_n;
            cnt      <= cnt_n;
        end
    end

    always_comb begin
        state_n        = state;
        src_addr_n     = src_addr;
        dst_addr_n     = dst_addr;
        cnt_n          = cnt;

        done_o         = (state == S_IDLE) || (state == S_WAIT);
        arvalid_o      = 1'b0;
        meta_awvalid_o = 1'b0;

        case (state)
            S_IDLE: begin
                if (start_i && (byte_len_i != 16'd0)) begin
                    state_n    = S_RUN;
                    src_addr_n = src_addr_i;
                    dst_addr_n = dst_addr_i;
                    cnt_n      = byte_len_i;
                end
            end

            S_RUN: begin
                if (!fifo_full_i) begin
                    arvalid_o      = 1'b1;
                    meta_awvalid_o = 1'b1;

                    if (arready_i) begin
                        src_addr_n = src_addr + 32'd64;
                        dst_addr_n = dst_addr + 32'd64;

                        if (cnt > 16'd64) begin
                            cnt_n   = cnt - 16'd64;
                        end
                        else begin
                            cnt_n   = 16'd0;
                            state_n = S_WAIT;
                        end
                    end
                end
            end

            S_WAIT: begin
                state_n = S_IDLE;
            end

            default: begin
                state_n = S_IDLE;
            end
        endcase
    end

    assign araddr_o      = src_addr;
    assign arlen_o       = (cnt >= 16'd64) ? 4'hF
                                           : (cnt[5:2] - 4'h1);
    assign arsize_o      = 3'b010;
    assign arburst_o     = 2'b01;

    assign meta_awaddr_o = dst_addr;
    assign meta_awlen_o  = arlen_o;

    assign bready_o      = 1'b1;

endmodule
