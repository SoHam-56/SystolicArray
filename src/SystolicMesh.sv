`timescale 1ns / 100ps

module SystolicMesh #(
    parameter MATRIX_SIZE = 32,
    parameter TILE_SIZE   = 4,
    parameter DATA_WIDTH  = 32,
    parameter ROWS_MEM    = "rows.mem",
    parameter COLS_MEM    = "cols.mem"
) (
    input logic clk_i,
    input logic rstn_i,
    input logic start_matrix_mult_i,

    // Global Inputs
    input logic                  north_write_enable_i,
    input logic [DATA_WIDTH-1:0] north_write_data_i,
    input logic                  north_write_reset_i,
    input logic                  west_write_enable_i,
    input logic [DATA_WIDTH-1:0] west_write_data_i,
    input logic                  west_write_reset_i,

    // Global Status
    output logic north_queue_empty_o,
    output logic west_queue_empty_o,
    output logic matrix_mult_complete_o,
    output logic collection_complete_o,
    output logic collection_active_o,

    // Unified Read Interface
    input  logic                  read_enable_i,
    input  logic [          31:0] read_addr_i,
    output logic [DATA_WIDTH-1:0] read_data_o,
    output logic                  read_valid_o
);

  localparam TILES_PER_DIM = MATRIX_SIZE / TILE_SIZE;
  localparam GLOBAL_ELEMENTS = MATRIX_SIZE * MATRIX_SIZE;
  localparam TILE_ELEMENTS = TILE_SIZE * TILE_SIZE;

  // =========================================================================
  // 1. Global Input Buffers (Storage -> always_ff)
  // =========================================================================
  logic [DATA_WIDTH-1:0] mem_A[0:GLOBAL_ELEMENTS-1];
  logic [DATA_WIDTH-1:0] mem_B[0:GLOBAL_ELEMENTS-1];
  logic [$clog2(GLOBAL_ELEMENTS):0] ptr_A, ptr_B;

  always_ff @(posedge clk_i or negedge rstn_i) begin
    if (!rstn_i) begin
      ptr_A <= '0;
      ptr_B <= '0;
    end else begin
      if (west_write_reset_i) ptr_A <= '0;
      if (north_write_reset_i) ptr_B <= '0;
      if (west_write_enable_i) begin
        mem_A[ptr_A] <= west_write_data_i;
        ptr_A <= ptr_A + 1;
      end
      if (north_write_enable_i) begin
        mem_B[ptr_B] <= north_write_data_i;
        ptr_B <= ptr_B + 1;
      end
    end
  end
  assign west_queue_empty_o  = (ptr_A == 0);
  assign north_queue_empty_o = (ptr_B == 0);

  // =========================================================================
  // 2. Main FSM Controller
  // =========================================================================
  typedef enum logic [2:0] {
    IDLE,
    RESET_SEQ,
    BROADCAST,
    FIRE_PULSE,
    WAIT_TILES,
    REDUCE_PULSE,
    WAIT_REDUCE,
    DONE
  } state_t;
  state_t current_state, next_state;

  // FSM Inputs (Status)
  logic loading_done;
  logic all_tiles_collected;
  logic all_reducers_done;

  // FSM Outputs (Control Signals -> Combinational)
  logic ctrl_reset_all, ctrl_load_en, ctrl_fire_pulse, ctrl_reduce_pulse, ctrl_done_signal;

  // Interconnects
  logic [TILES_PER_DIM-1:0][TILES_PER_DIM-1:0][TILES_PER_DIM-1:0] tile_col_done;
  logic [TILES_PER_DIM-1:0][TILES_PER_DIM-1:0][TILES_PER_DIM-1:0] tile_col_active;
  logic [TILES_PER_DIM-1:0][TILES_PER_DIM-1:0] reducer_done;
  integer load_idx;

  assign loading_done = (load_idx >= TILE_ELEMENTS - 1);
  assign all_tiles_collected = &tile_col_done;
  assign all_reducers_done = &reducer_done;

  // --- FSM Combinational (Next State & Outputs) ---
  always_comb begin
    next_state = current_state;
    ctrl_reset_all = 0;
    ctrl_load_en = 0;
    ctrl_fire_pulse = 0;
    ctrl_reduce_pulse = 0;
    ctrl_done_signal = 0;

    case (current_state)
      IDLE:        if (start_matrix_mult_i) next_state = RESET_SEQ;
      RESET_SEQ: begin
        ctrl_reset_all = 1;
        next_state = BROADCAST;
      end
      BROADCAST: begin
        ctrl_load_en = 1;
        if (loading_done) next_state = FIRE_PULSE;
      end
      FIRE_PULSE: begin
        ctrl_fire_pulse = 1;
        next_state = WAIT_TILES;
      end
      WAIT_TILES:  if (all_tiles_collected) next_state = REDUCE_PULSE;
      REDUCE_PULSE: begin
        ctrl_reduce_pulse = 1;
        next_state = WAIT_REDUCE;
      end
      WAIT_REDUCE: if (all_reducers_done) next_state = DONE;
      DONE: begin
        ctrl_done_signal = 1;
        if (start_matrix_mult_i) next_state = RESET_SEQ;
      end
      default:     next_state = IDLE;
    endcase
  end

  // --- FSM Sequential (State & Datapath Registers) ---
  logic [TILES_PER_DIM-1:0][TILES_PER_DIM-1:0] load_we_A, load_we_B;
  logic [TILES_PER_DIM-1:0][TILES_PER_DIM-1:0][DATA_WIDTH-1:0] load_data_A, load_data_B;
  logic tiles_global_start;
  integer i_L, j_L, k_L, sub_r, sub_c, addr_calc;

  always_ff @(posedge clk_i or negedge rstn_i) begin
    if (!rstn_i) begin
      current_state <= IDLE;
      load_idx <= 0;
      load_we_A <= '{default: 0};
      load_we_B <= '{default: 0};
      tiles_global_start <= 0;
      matrix_mult_complete_o <= 0;
    end else begin
      current_state <= next_state;

      // Output Register Updates
      matrix_mult_complete_o <= ctrl_done_signal;
      tiles_global_start <= ctrl_fire_pulse;  // Register the pulse for clean timing

      // Counter Update
      if (ctrl_reset_all) load_idx <= 0;
      else if (ctrl_load_en && !loading_done) load_idx <= load_idx + 1;

      // Broadcast Logic (Registered for Timing)
      load_we_A <= '{default: 0};
      load_we_B <= '{default: 0};
      if (ctrl_load_en) begin
        sub_r = load_idx / TILE_SIZE;
        sub_c = load_idx % TILE_SIZE;
        for (i_L = 0; i_L < TILES_PER_DIM; i_L++) begin
          for (k_L = 0; k_L < TILES_PER_DIM; k_L++) begin
            addr_calc = ((i_L * TILE_SIZE) + sub_r) * MATRIX_SIZE + ((k_L * TILE_SIZE) + sub_c);
            load_data_A[i_L][k_L] <= mem_A[addr_calc];
            load_we_A[i_L][k_L]   <= 1;
          end
        end
        for (k_L = 0; k_L < TILES_PER_DIM; k_L++) begin
          for (j_L = 0; j_L < TILES_PER_DIM; j_L++) begin
            addr_calc = ((k_L * TILE_SIZE) + sub_r) * MATRIX_SIZE + ((j_L * TILE_SIZE) + sub_c);
            load_data_B[k_L][j_L] <= mem_B[addr_calc];
            load_we_B[k_L][j_L]   <= 1;
          end
        end
      end
    end
  end

  // =========================================================================
  // 3. Instantiation
  // =========================================================================
  logic [TILES_PER_DIM-1:0][TILES_PER_DIM-1:0][TILES_PER_DIM-1:0]                 t_ren;
  logic [TILES_PER_DIM-1:0][TILES_PER_DIM-1:0][TILES_PER_DIM-1:0][          31:0] t_addr;
  logic [TILES_PER_DIM-1:0][TILES_PER_DIM-1:0][TILES_PER_DIM-1:0][DATA_WIDTH-1:0] t_data;
  logic [TILES_PER_DIM-1:0][TILES_PER_DIM-1:0][TILES_PER_DIM-1:0]                 t_valid;
  logic [TILES_PER_DIM-1:0][TILES_PER_DIM-1:0][   DATA_WIDTH-1:0]                 final_data;

  genvar i, j, k;
  generate
    for (i = 0; i < TILES_PER_DIM; i++) begin : ROW
      for (j = 0; j < TILES_PER_DIM; j++) begin : COL

        AccumulationUnit #(
            .P(TILES_PER_DIM),
            .N(TILE_SIZE),
            .DATA_WIDTH(DATA_WIDTH)
        ) acc_unit (
            .clk_i(clk_i),
            .rstn_i(rstn_i),
            .start_i(ctrl_reduce_pulse),
            .tile_data_i(t_data[i][j]),
            .tile_valid_i(t_valid[i][j]),
            .tile_ren_o(t_ren[i][j]),
            .tile_addr_o(t_addr[i][j]),
            .ext_addr_i(read_addr_i % TILE_ELEMENTS),
            .ext_data_o(final_data[i][j]),
            .done_o(reducer_done[i][j])
        );

        for (k = 0; k < TILES_PER_DIM; k++) begin : DEPTH
          SystolicArray #(
              .N(TILE_SIZE),
              .DATA_WIDTH(DATA_WIDTH),
              .ROWS(ROWS_MEM),
              .COLS(COLS_MEM)
          ) tile (
              .clk_i(clk_i),
              .rstn_i(rstn_i),
              .start_matrix_mult_i(tiles_global_start),
              .west_write_enable_i(load_we_A[i][k]),
              .west_write_data_i(load_data_A[i][k]),
              .west_write_reset_i(ctrl_reset_all),
              .north_write_enable_i(load_we_B[k][j]),
              .north_write_data_i(load_data_B[k][j]),
              .north_write_reset_i(ctrl_reset_all),
              .collection_complete_o(tile_col_done[i][j][k]),
              .collection_active_o(tile_col_active[i][j][k]),
              .matrix_mult_complete_o(),
              .north_queue_empty_o(),
              .west_queue_empty_o(),
              .read_enable_i(t_ren[i][j][k]),
              .read_addr_i(t_addr[i][j][k]),
              .read_data_o(t_data[i][j][k]),
              .read_valid_o(t_valid[i][j][k])
          );
        end
      end
    end
  endgenerate

  // Output Mux
  integer sel_i, sel_j;
  always_comb begin
    sel_i = (read_addr_i / MATRIX_SIZE) / TILE_SIZE;
    sel_j = (read_addr_i % MATRIX_SIZE) / TILE_SIZE;
    if (sel_i >= TILES_PER_DIM) sel_i = 0;
    if (sel_j >= TILES_PER_DIM) sel_j = 0;
    read_data_o = final_data[sel_i][sel_j];
  end

  assign collection_complete_o = &reducer_done;
  assign collection_active_o   = !(&reducer_done) && (current_state == WAIT_REDUCE);
  always_ff @(posedge clk_i) read_valid_o <= read_enable_i;

endmodule

// =============================================================================
// SUBMODULE: Accumulation Unit (Refactored for Comb Outputs / Seq Registers)
// =============================================================================
module AccumulationUnit #(
    parameter P = 8,
    parameter N = 4,
    parameter DATA_WIDTH = 32
) (
    input logic clk_i,
    rstn_i,
    start_i,

    // Tiles Interface
    input  logic [P-1:0][DATA_WIDTH-1:0] tile_data_i,
    input  logic [P-1:0]                 tile_valid_i,
    output logic [P-1:0]                 tile_ren_o,
    output logic [P-1:0][          31:0] tile_addr_o,

    // External Interface
    input logic [31:0] ext_addr_i,
    output logic [DATA_WIDTH-1:0] ext_data_o,
    output logic done_o
);
  localparam PIXELS = N * N;

  // Registers (Must be in always_ff)
  logic [DATA_WIDTH-1:0] mem[0:PIXELS-1];
  logic [DATA_WIDTH-1:0] acc, op_b;
  integer p_idx, k_idx;

  // FSM States
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

  // Adder Interface
  logic add_pulse, add_done;
  logic [DATA_WIDTH-1:0] add_res;

  fp32Adder adder (
      .clk_i(clk_i),
      .rstn_i(rstn_i),
      .valid_i(add_pulse),
      .A(acc),
      .B(op_b),
      .result_o(add_res),
      .done_o(add_done)
  );

  // Control Signals (Generated in Comb, used in FF)
  logic c_clr_vars, c_inc_k, c_inc_pix;
  logic c_latch_b, c_upd_acc, c_mem_we;

  // =========================================================================
  // A. Combinational Logic: Next State & OUTPUTS
  // =========================================================================
  always_comb begin
    r_next = r_curr;

    // Default Outputs (Mealy/Moore style)
    tile_ren_o = 0;
    tile_addr_o = '{default: 0};
    add_pulse = 0;
    done_o = 0;

    // Default Internal Controls
    c_clr_vars = 0;
    c_inc_k = 0;
    c_inc_pix = 0;
    c_latch_b = 0;
    c_upd_acc = 0;
    c_mem_we = 0;

    // Drive address bus based on current index
    tile_addr_o[k_idx] = p_idx;

    case (r_curr)
      RIDLE: begin
        if (start_i) begin
          c_clr_vars = 1;
          r_next = REQ_TILE;
        end
      end

      REQ_TILE: begin
        tile_ren_o[k_idx] = 1;  // Pure Combinational Output
        r_next = WAIT_VAL;
      end

      WAIT_VAL: begin
        if (tile_valid_i[k_idx]) begin
          c_latch_b = 1;
          r_next = ADD_TRIG;
        end
      end

      ADD_TRIG: begin
        add_pulse = 1;  // Pure Combinational Output
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
        c_mem_we = 1;
        if (p_idx < PIXELS - 1) begin
          c_inc_pix = 1;
          r_next = REQ_TILE;
        end else begin
          r_next = RDONE;
        end
      end

      RDONE: begin
        done_o = 1;  // Pure Combinational Output
      end

      default: r_next = RIDLE;
    endcase
  end

  // =========================================================================
  // B. Sequential Logic: State & Register Updates
  // =========================================================================
  always_ff @(posedge clk_i or negedge rstn_i) begin
    if (!rstn_i) begin
      r_curr <= RIDLE;
      p_idx <= 0;
      k_idx <= 0;
      acc <= 0;
      op_b <= 0;
    end else begin
      r_curr <= r_next;

      // Counters
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

      // Registers
      if (c_latch_b) op_b <= tile_data_i[k_idx];
      if (c_upd_acc) acc <= add_res;
      if (c_mem_we) mem[p_idx] <= acc;
    end
  end

  assign ext_data_o = mem[ext_addr_i];

endmodule
