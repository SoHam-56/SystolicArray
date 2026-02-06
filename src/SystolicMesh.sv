`timescale 1ns / 100ps

module SystolicMesh #(
    parameter MATRIX_SIZE = 4,           // Global Matrix Dimension (M)
    parameter TILE_SIZE   = 2,           // Tile Dimension (N)
    parameter DATA_WIDTH  = 32,          // Data Width
    parameter ROWS_MEM    = "rows.mem",
    parameter COLS_MEM    = "cols.mem"
) (
    input logic clk_i,
    input logic rstn_i,
    input logic start_matrix_mult_i,

    // Global North Queue (Matrix B Input)
    input logic                  north_write_enable_i,
    input logic [DATA_WIDTH-1:0] north_write_data_i,
    input logic                  north_write_reset_i,

    // Global West Queue (Matrix A Input)
    input logic                  west_write_enable_i,
    input logic [DATA_WIDTH-1:0] west_write_data_i,
    input logic                  west_write_reset_i,

    // Global Status Signals
    output logic north_queue_empty_o,
    output logic west_queue_empty_o,
    output logic matrix_mult_complete_o,
    output logic collection_complete_o,
    output logic collection_active_o,

    // Unified SRAM Read Interface
    input  logic                  read_enable_i,
    input  logic [          31:0] read_addr_i,
    output logic [DATA_WIDTH-1:0] read_data_o,
    output logic                  read_valid_o
);

  // =========================================================================
  // 1. Parameters & Constants
  // =========================================================================
  localparam TILES_PER_DIM = MATRIX_SIZE / TILE_SIZE;
  localparam GLOBAL_ELEMENTS = MATRIX_SIZE * MATRIX_SIZE;
  localparam TILE_ELEMENTS = TILE_SIZE * TILE_SIZE;

  // =========================================================================
  // 2. Global Input Buffers
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
  // 3. 3D Interconnect Signals
  // =========================================================================
  // Broadcast Buses
  logic [TILES_PER_DIM-1:0][TILES_PER_DIM-1:0] load_we_A;  // [i][k]
  logic [TILES_PER_DIM-1:0][TILES_PER_DIM-1:0][DATA_WIDTH-1:0] load_data_A;

  logic [TILES_PER_DIM-1:0][TILES_PER_DIM-1:0] load_we_B;  // [k][j]
  logic [TILES_PER_DIM-1:0][TILES_PER_DIM-1:0][DATA_WIDTH-1:0] load_data_B;

  // Outputs from the 3D Grid [i][j][k]
  logic [TILES_PER_DIM-1:0][TILES_PER_DIM-1:0][TILES_PER_DIM-1:0] tile_done;
  logic [TILES_PER_DIM-1:0][TILES_PER_DIM-1:0][TILES_PER_DIM-1:0] tile_col_done;
  logic [TILES_PER_DIM-1:0][TILES_PER_DIM-1:0][TILES_PER_DIM-1:0] tile_col_active;

  logic [TILES_PER_DIM-1:0][TILES_PER_DIM-1:0][TILES_PER_DIM-1:0] tile_read_en;
  logic [TILES_PER_DIM-1:0][TILES_PER_DIM-1:0][TILES_PER_DIM-1:0][31:0] tile_read_addr;
  logic [TILES_PER_DIM-1:0][TILES_PER_DIM-1:0][TILES_PER_DIM-1:0][DATA_WIDTH-1:0] tile_read_data;

  logic tiles_global_start;
  logic tiles_global_reset;

  // Status aggregation
  assign collection_complete_o = &tile_col_done;
  assign collection_active_o   = |tile_col_active;

  // =========================================================================
  // 4. Control FSM 
  // =========================================================================
  // Split states to ensure PULSE generation
  typedef enum logic [2:0] {
    IDLE,
    RESET_TILES,
    BROADCAST_LOAD,
    TRIGGER_START,    // Generates the pulse
    WAIT_COLLECTION,  // Waits for finish (start is low here)
    DONE
  } state_t;

  state_t state;
  integer load_idx;

  // Scratch variables 
  integer i_load, j_load, k_load;
  integer sub_r, sub_c;
  integer addr_calc;

  always_ff @(posedge clk_i or negedge rstn_i) begin
    if (!rstn_i) begin
      state <= IDLE;
      matrix_mult_complete_o <= 0;
      tiles_global_start <= 0;
      tiles_global_reset <= 0;
      load_idx <= 0;
      load_we_A <= '{default: 0};
      load_we_B <= '{default: 0};
      load_data_A <= '{default: 0};
      load_data_B <= '{default: 0};
    end else begin
      // ------------------------------------
      // Default Values (Pulse Generation)
      // ------------------------------------
      // Unless overridden in a specific state, these signals 
      // return to 0 every clock cycle.
      tiles_global_start <= 0;
      tiles_global_reset <= 0;
      load_we_A <= '{default: 0};
      load_we_B <= '{default: 0};

      case (state)
        IDLE: begin
          if (start_matrix_mult_i) begin
            state <= RESET_TILES;
            matrix_mult_complete_o <= 0;
          end
        end

        RESET_TILES: begin
          tiles_global_reset <= 1;  // Pulse Reset High
          load_idx <= 0;
          state <= BROADCAST_LOAD;
        end

        BROADCAST_LOAD: begin
          if (load_idx < TILE_ELEMENTS) begin
            sub_r = load_idx / TILE_SIZE;
            sub_c = load_idx % TILE_SIZE;

            // 1. Broadcast A[i,k]
            for (i_load = 0; i_load < TILES_PER_DIM; i_load = i_load + 1) begin
              for (k_load = 0; k_load < TILES_PER_DIM; k_load = k_load + 1) begin
                addr_calc = ((i_load * TILE_SIZE) + sub_r) * MATRIX_SIZE + ((k_load * TILE_SIZE) + sub_c);
                load_data_A[i_load][k_load] <= mem_A[addr_calc];
                load_we_A[i_load][k_load]   <= 1'b1;
              end
            end

            // 2. Broadcast B[k,j]
            for (k_load = 0; k_load < TILES_PER_DIM; k_load = k_load + 1) begin
              for (j_load = 0; j_load < TILES_PER_DIM; j_load = j_load + 1) begin
                addr_calc = ((k_load * TILE_SIZE) + sub_r) * MATRIX_SIZE + ((j_load * TILE_SIZE) + sub_c);
                load_data_B[k_load][j_load] <= mem_B[addr_calc];
                load_we_B[k_load][j_load]   <= 1'b1;
              end
            end
            load_idx <= load_idx + 1;
          end else begin
            state <= TRIGGER_START;
          end
        end

        TRIGGER_START: begin
          // 1. Assert Start Pulse
          tiles_global_start <= 1;

          // 2. Move immediately to wait state
          // This ensures tiles_global_start is high for exactly 1 cycle
          // because the default assignment at top of always_ff will
          // clear it in the next cycle (WAIT_COLLECTION).
          state <= WAIT_COLLECTION;
        end

        WAIT_COLLECTION: begin
          // tiles_global_start is 0 here (default)

          // Wait for the final collection signal from all tiles
          if (&tile_col_done) begin
            state <= DONE;
          end
        end

        DONE: begin
          matrix_mult_complete_o <= 1;
          if (start_matrix_mult_i) state <= RESET_TILES;
        end
      endcase
    end
  end

  // =========================================================================
  // 5. Output Summation Logic (Combinational)
  // =========================================================================
  logic [DATA_WIDTH-1:0] spatial_sum;

  integer target_i, target_j;
  integer sub_r_read, sub_c_read, target_sub_addr;
  integer k_sum;

  always_comb begin
    // 1. Address Decoding
    target_i = (read_addr_i / MATRIX_SIZE) / TILE_SIZE;
    target_j = (read_addr_i % MATRIX_SIZE) / TILE_SIZE;

    sub_r_read = (read_addr_i / MATRIX_SIZE) % TILE_SIZE;
    sub_c_read = (read_addr_i % MATRIX_SIZE) % TILE_SIZE;
    target_sub_addr = sub_r_read * TILE_SIZE + sub_c_read;

    // 2. Spatial Summation Loop
    spatial_sum = 0;
    tile_read_en = '{default: 0};
    tile_read_addr = '{default: 0};

    if (read_enable_i) begin
      for (k_sum = 0; k_sum < TILES_PER_DIM; k_sum = k_sum + 1) begin
        // Enable Read
        tile_read_en[target_i][target_j][k_sum] = 1'b1;
        tile_read_addr[target_i][target_j][k_sum] = target_sub_addr;

        // Summation
        spatial_sum = spatial_sum + tile_read_data[target_i][target_j][k_sum];
      end
    end
  end

  // Drive Output Register
  always_ff @(posedge clk_i) begin
    read_valid_o <= read_enable_i;
    if (read_enable_i) begin
      read_data_o <= spatial_sum;
    end
  end

  // =========================================================================
  // 6. 3D Grid Instantiation
  // =========================================================================
  genvar i, j, k;
  generate
    for (i = 0; i < TILES_PER_DIM; i++) begin : ROW
      for (j = 0; j < TILES_PER_DIM; j++) begin : COL
        for (k = 0; k < TILES_PER_DIM; k++) begin : DEPTH

          SystolicArray #(
              .N(TILE_SIZE),
              .DATA_WIDTH(DATA_WIDTH),
              .ROWS(ROWS_MEM),
              .COLS(COLS_MEM)
          ) tile_inst (
              .clk_i(clk_i),
              .rstn_i(rstn_i),
              .start_matrix_mult_i(tiles_global_start),

              // Inputs (Mapped to Broadcast Wires)
              .west_write_enable_i(load_we_A[i][k]),
              .west_write_data_i  (load_data_A[i][k]),
              .west_write_reset_i (tiles_global_reset),

              .north_write_enable_i(load_we_B[k][j]),
              .north_write_data_i  (load_data_B[k][j]),
              .north_write_reset_i (tiles_global_reset),

              // Outputs
              .matrix_mult_complete_o(tile_done[i][j][k]),
              .north_queue_empty_o(),
              .west_queue_empty_o(),

              // Collection Handshake Signals
              .collection_complete_o(tile_col_done[i][j][k]),
              .collection_active_o  (tile_col_active[i][j][k]),

              // Read Interface (Wired to Summation Logic)
              .read_enable_i(tile_read_en[i][j][k]),
              .read_addr_i  (tile_read_addr[i][j][k]),
              .read_data_o  (tile_read_data[i][j][k]),
              .read_valid_o ()
          );
        end
      end
    end
  endgenerate

endmodule
