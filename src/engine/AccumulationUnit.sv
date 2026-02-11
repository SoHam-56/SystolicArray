`timescale 1ns / 100ps

module AccumulationUnit #(
    parameter P = 8,
    parameter N = 4,
    parameter DATA_WIDTH = 32,
    parameter MATRIX_WIDTH = 32,
    parameter TILE_ROW_OFFSET = 0,
    parameter TILE_COL_OFFSET = 0
) (
    input logic clk_i,
    rstn_i,
    start_i,

    input  logic [P-1:0][DATA_WIDTH-1:0] tile_data_i,
    input  logic [P-1:0]                 tile_valid_i,
    output logic [P-1:0]                 tile_ren_o,
    output logic [P-1:0][          31:0] tile_addr_o,

    output logic                  write_en_o,
    output logic [          31:0] write_addr_o,
    output logic [DATA_WIDTH-1:0] write_data_o,

    output logic done_o
);
  localparam PIXELS = N * N;

  logic [DATA_WIDTH-1:0] acc, op_b;
  integer p_idx, k_idx;

  typedef enum logic [2:0] {
    RIDLE,
    REQ_TILE,
    WAIT_VAL,
    ADD_TRIG,
    ADD_WAIT,
    NEXT_K,
    SAVE_RES,
    RDONE
  } rstate_t;
  rstate_t r_curr, r_next;

  logic add_pulse, add_done;
  logic [DATA_WIDTH-1:0] add_res;

  fp32Adder adder (
      .clk_i(clk_i),
      .rstn_i(rstn_i),
      .valid_i(add_pulse),
      .A(acc),
      .B(op_b),
      .result_o(add_res),
      .done_o(add_done),
      .overflow_o(),
      .underflow_o(),
      .invalid_o()
  );

  logic c_clr_vars, c_inc_k, c_inc_pix;
  logic c_latch_b, c_upd_acc, c_global_we;

  logic [31:0] global_addr;
  logic [31:0] local_row, local_col;

  always_comb begin
    local_row   = p_idx / N;
    local_col   = p_idx % N;
    global_addr = ((TILE_ROW_OFFSET + local_row) * MATRIX_WIDTH) + (TILE_COL_OFFSET + local_col);
  end

  always_comb begin
    r_next = r_curr;
    tile_ren_o = 0;
    tile_addr_o = '{default: 0};
    add_pulse = 0;
    done_o = 0;

    write_en_o = 0;
    write_addr_o = global_addr;
    write_data_o = acc;

    c_clr_vars = 0;
    c_inc_k = 0;
    c_inc_pix = 0;
    c_latch_b = 0;
    c_upd_acc = 0;

    tile_addr_o[k_idx] = p_idx;

    case (r_curr)
      RIDLE: begin
        if (start_i) begin
          c_clr_vars = 1;
          r_next = REQ_TILE;
        end
      end
      REQ_TILE: begin
        tile_ren_o[k_idx] = 1;
        r_next = WAIT_VAL;
      end
      WAIT_VAL: begin
        if (tile_valid_i[k_idx]) begin
          c_latch_b = 1;
          r_next = ADD_TRIG;
        end
      end
      ADD_TRIG: begin
        add_pulse = 1;
        r_next = ADD_WAIT;
      end
      ADD_WAIT: begin
        if (add_done) begin
          c_upd_acc = 1;
          r_next = NEXT_K;
        end
      end
      NEXT_K: begin
        if (k_idx < P - 1) begin
          c_inc_k = 1;
          r_next  = REQ_TILE;
        end else begin
          r_next = SAVE_RES;
        end
      end
      SAVE_RES: begin
        write_en_o = 1;
        if (p_idx < PIXELS - 1) begin
          c_inc_pix = 1;
          r_next = REQ_TILE;
        end else begin
          r_next = RDONE;
        end
      end
      RDONE:   done_o = 1;
      default: r_next = RIDLE;
    endcase
  end

  always_ff @(posedge clk_i or negedge rstn_i) begin
    if (!rstn_i) begin
      r_curr <= RIDLE;
      p_idx <= 0;
      k_idx <= 0;
      acc <= 0;
      op_b <= 0;
    end else begin
      r_curr <= r_next;
      if (c_clr_vars) begin
        p_idx <= 0;
        k_idx <= 0;
        acc   <= 0;
      end
      if (c_inc_k) k_idx <= k_idx + 1;
      if (c_inc_pix) begin
        p_idx <= p_idx + 1;
        k_idx <= 0;
        acc   <= 0;
      end
      if (c_latch_b) op_b <= tile_data_i[k_idx];
      if (c_upd_acc) acc <= add_res;
    end
  end

endmodule
