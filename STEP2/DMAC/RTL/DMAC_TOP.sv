module DMAC_TOP
(
    input   wire                clk,
    input   wire                rst_n,

    input   wire                psel_i,
    input   wire                penable_i,
    input   wire    [11:0]      paddr_i,
    input   wire                pwrite_i,
    input   wire    [31:0]      pwdata_i,
    output  wire                pready_o,
    output  wire    [31:0]      prdata_o,
    output  wire                pslverr_o,

    output  wire    [3:0]       awid_o,
    output  wire    [31:0]      awaddr_o,
    output  wire    [3:0]       awlen_o,
    output  wire    [2:0]       awsize_o,
    output  wire    [1:0]       awburst_o,
    output  wire                awvalid_o,
    input   wire                awready_i,

    output  wire    [3:0]       wid_o,
    output  wire    [31:0]      wdata_o,
    output  wire    [3:0]       wstrb_o,
    output  wire                wlast_o,
    output  wire                wvalid_o,
    input   wire                wready_i,

    input   wire    [3:0]       bid_i,
    input   wire    [1:0]       bresp_i,
    input   wire                bvalid_i,
    output  wire                bready_o,

    output  wire    [3:0]       arid_o,
    output  wire    [31:0]      araddr_o,
    output  wire    [3:0]       arlen_o,
    output  wire    [2:0]       arsize_o,
    output  wire    [1:0]       arburst_o,
    output  wire                arvalid_o,
    input   wire                arready_i,

    input   wire    [3:0]       rid_i,
    input   wire    [31:0]      rdata_i,
    input   wire    [1:0]       rresp_i,
    input   wire                rlast_i,
    input   wire                rvalid_i,
    output  wire                rready_o
);

    localparam N_CH = 4;

    wire    [31:0]  src_addr_vec[N_CH];
    wire    [31:0]  dst_addr_vec[N_CH];
    wire    [15:0]  byte_len_vec[N_CH];
    wire            start_vec[N_CH];
    wire            done_vec[N_CH];

    wire    [31:0]  araddr_vec[N_CH];
    wire    [3:0]   arlen_vec[N_CH];
    wire            arvalid_vec[N_CH];
    wire            arready_vec[N_CH];

    wire    [31:0]  meta_awaddr_vec[N_CH];
    wire    [3:0]   meta_awlen_vec[N_CH];
    wire            meta_awvalid_vec[N_CH];

    wire            bready_vec[N_CH];

    wire            aw_fifo_full;
    wire            data_fifo_full;
    wire            shared_fifo_full;

    assign shared_fifo_full = aw_fifo_full | data_fifo_full;

    assign pslverr_o = 1'b0;

    DMAC_CFG u_cfg (
        .clk(clk), .rst_n(rst_n),
        .psel_i(psel_i), .penable_i(penable_i), .paddr_i(paddr_i),
        .pwrite_i(pwrite_i), .pwdata_i(pwdata_i),
        .pready_o(pready_o), .prdata_o(prdata_o),

        .ch0_src_addr_o(src_addr_vec[0]), .ch0_dst_addr_o(dst_addr_vec[0]),
        .ch0_byte_len_o(byte_len_vec[0]), .ch0_start_o(start_vec[0]), .ch0_done_i(done_vec[0]),
        .ch1_src_addr_o(src_addr_vec[1]), .ch1_dst_addr_o(dst_addr_vec[1]),
        .ch1_byte_len_o(byte_len_vec[1]), .ch1_start_o(start_vec[1]), .ch1_done_i(done_vec[1]),
        .ch2_src_addr_o(src_addr_vec[2]), .ch2_dst_addr_o(dst_addr_vec[2]),
        .ch2_byte_len_o(byte_len_vec[2]), .ch2_start_o(start_vec[2]), .ch2_done_i(done_vec[2]),
        .ch3_src_addr_o(src_addr_vec[3]), .ch3_dst_addr_o(dst_addr_vec[3]),
        .ch3_byte_len_o(byte_len_vec[3]), .ch3_start_o(start_vec[3]), .ch3_done_i(done_vec[3])
    );

    genvar ch;
    generate
        for (ch=0; ch<N_CH; ch++) begin: channel
            DMAC_INITIATOR u_initiator (
                .clk            (clk),
                .rst_n          (rst_n),
                .src_addr_i     (src_addr_vec[ch]),
                .dst_addr_i     (dst_addr_vec[ch]),
                .byte_len_i     (byte_len_vec[ch]),
                .start_i        (start_vec[ch]),
                .done_o         (done_vec[ch]),
                .araddr_o       (araddr_vec[ch]),
                .arlen_o        (arlen_vec[ch]),
                .arsize_o       (),
                .arburst_o      (),
                .arvalid_o      (arvalid_vec[ch]),
                .arready_i      (arready_vec[ch]),
                .bvalid_i       (bvalid_i && (bid_i == ch[3:0])),
                .bready_o       (bready_vec[ch]),
                .fifo_full_i    (shared_fifo_full),
                .meta_awaddr_o  (meta_awaddr_vec[ch]),
                .meta_awlen_o   (meta_awlen_vec[ch]),
                .meta_awvalid_o (meta_awvalid_vec[ch])
            );
        end
    endgenerate

    DMAC_ARBITER #(
        .N_MASTER(N_CH),
        .DATA_SIZE($bits(arid_o) + $bits(araddr_o) + $bits(arlen_o) + $bits(arsize_o) + $bits(arburst_o))
    ) u_ar_arbiter (
        .clk(clk), .rst_n(rst_n),
        .src_valid_i (arvalid_vec),
        .src_ready_o (arready_vec),
        .src_data_i  ({
            {4'd0, araddr_vec[0], arlen_vec[0], 3'b010, 2'b01},
            {4'd1, araddr_vec[1], arlen_vec[1], 3'b010, 2'b01},
            {4'd2, araddr_vec[2], arlen_vec[2], 3'b010, 2'b01},
            {4'd3, araddr_vec[3], arlen_vec[3], 3'b010, 2'b01}
        }),
        .dst_valid_o (arvalid_o),
        .dst_ready_i (arready_i),
        .dst_data_o  ({arid_o, araddr_o, arlen_o, arsize_o, arburst_o})
    );

    reg     [39:0]  muxed_aw_data;
    reg             muxed_aw_wren;

    always_comb begin
        muxed_aw_data = 40'd0;
        muxed_aw_wren = 1'b0;

        if (arready_vec[0]) begin
            muxed_aw_data = {4'd0, meta_awaddr_vec[0], meta_awlen_vec[0]};
            muxed_aw_wren = 1'b1;
        end
        else if (arready_vec[1]) begin
            muxed_aw_data = {4'd1, meta_awaddr_vec[1], meta_awlen_vec[1]};
            muxed_aw_wren = 1'b1;
        end
        else if (arready_vec[2]) begin
            muxed_aw_data = {4'd2, meta_awaddr_vec[2], meta_awlen_vec[2]};
            muxed_aw_wren = 1'b1;
        end
        else if (arready_vec[3]) begin
            muxed_aw_data = {4'd3, meta_awaddr_vec[3], meta_awlen_vec[3]};
            muxed_aw_wren = 1'b1;
        end
    end

    wire    [39:0]  fifo_aw_rdata;
    wire            fifo_aw_empty;

    DMAC_FIFO #(.DATA_WIDTH(40), .DEPTH_LG2(4)) u_aw_fifo (
        .clk        (clk),
        .rst_n      (rst_n),
        .wren_i     (muxed_aw_wren),
        .wdata_i    (muxed_aw_data),
        .full_o     (aw_fifo_full),
        .rden_i     (awready_i && awvalid_o),
        .rdata_o    (fifo_aw_rdata),
        .empty_o    (fifo_aw_empty)
    );

    assign awvalid_o = !fifo_aw_empty;
    assign {awid_o, awaddr_o, awlen_o} = fifo_aw_rdata;
    assign awsize_o  = 3'b010;
    assign awburst_o = 2'b01;

    wire    [36:0]  fifo_data_rdata;
    wire            fifo_data_empty;

    DMAC_FIFO #(.DATA_WIDTH(37), .DEPTH_LG2(4)) u_data_fifo (
        .clk        (clk),
        .rst_n      (rst_n),
        .wren_i     (rvalid_i && rready_o),
        .wdata_i    ({rid_i, rlast_i, rdata_i}),
        .full_o     (data_fifo_full),
        .rden_i     (wready_i && wvalid_o),
        .rdata_o    (fifo_data_rdata),
        .empty_o    (fifo_data_empty)
    );

    assign rready_o = !data_fifo_full;

    assign wvalid_o = !fifo_data_empty;
    assign {wid_o, wlast_o, wdata_o} = fifo_data_rdata;
    assign wstrb_o  = 4'b1111;

    assign bready_o = (bid_i == 4'd0) ? bready_vec[0] :
                      (bid_i == 4'd1) ? bready_vec[1] :
                      (bid_i == 4'd2) ? bready_vec[2] :
                                        bready_vec[3];

endmodule
