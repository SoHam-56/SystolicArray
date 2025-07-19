`timescale 1ns / 100ps

module SystolicMesh #(
    parameter TILE_SIZE     = 2,      // Size of each systolic array tile (N x N)
    parameter DATA_WIDTH    = 32,     // Data width for each element
    parameter TILES_X       = 2,      // Number of tiles in X direction (columns)
    parameter TILES_Y       = 2,      // Number of tiles in Y direction (rows)
    parameter ROWS_MEM      = "rows.mem",
    parameter COLS_MEM      = "cols.mem"
) (
    input  logic                                    clk_i,
    input  logic                                    rstn_i,
    input  logic                                    start_matrix_mult_i,
    
    // North Queue Write interface (for weights)
    input  logic                                    north_write_enable_i,
    input  logic [DATA_WIDTH-1:0]                   north_write_data_i,
    input  logic                                    north_write_reset_i,
    
    // West Queue Write interface (for data)
    input  logic                                    west_write_enable_i,
    input  logic [DATA_WIDTH-1:0]                   west_write_data_i,
    input  logic                                    west_write_reset_i,
    
    // Queue status
    output logic                                    north_queue_empty_o,
    output logic                                    west_queue_empty_o,
    output logic                                    matrix_mult_complete_o,
    
    // Unified SRAM read interface
    input  logic                                    read_enable_i,
    input  logic [$clog2(TILE_SIZE*TILE_SIZE*TILES_X*TILES_Y)-1:0] read_addr_i,
    output logic [DATA_WIDTH-1:0]                   read_data_o,
    output logic                                    read_valid_o,
    
    // Status signals
    output logic                                    collection_complete_o,
    output logic                                    collection_active_o
);

    localparam TILE_ELEMENTS = TILE_SIZE * TILE_SIZE;
    localparam TOTAL_TILES = TILES_X * TILES_Y;
    localparam MATRIX_SIZE = TILE_SIZE * TILES_X;  // Total matrix dimension
    
    typedef enum logic [2:0] {
        IDLE,
        FILLING_TILES,
        PROCESSING,
        COMPLETE
    } state_t;
    
    state_t current_state, next_state;
    
    // Global element counters for matrix-based addressing
    logic [$clog2(MATRIX_SIZE*MATRIX_SIZE+1)-1:0] north_global_element_count, next_north_global_count;
    logic [$clog2(MATRIX_SIZE*MATRIX_SIZE+1)-1:0] west_global_element_count, next_west_global_count;
    
    // Current target tile for each stream
    logic [$clog2(TILES_Y)-1:0] north_target_tile_y, west_target_tile_y;
    logic [$clog2(TILES_X)-1:0] north_target_tile_x, west_target_tile_x;
    
    // Matrix position calculation variables
    logic [$clog2(MATRIX_SIZE)-1:0] north_matrix_row, north_matrix_col;
    logic [$clog2(MATRIX_SIZE)-1:0] west_matrix_row, west_matrix_col;
    
    // Pulse generation for tile_start
    logic start_pulse;
    
    // Tile interface arrays
    logic [TILES_Y-1:0][TILES_X-1:0] tile_start;
    logic [TILES_Y-1:0][TILES_X-1:0] tile_north_write_enable;
    logic [TILES_Y-1:0][TILES_X-1:0] tile_west_write_enable;
    logic [TILES_Y-1:0][TILES_X-1:0] tile_north_write_reset;
    logic [TILES_Y-1:0][TILES_X-1:0] tile_west_write_reset;
    logic [TILES_Y-1:0][TILES_X-1:0] [DATA_WIDTH-1:0] tile_north_write_data;
    logic [TILES_Y-1:0][TILES_X-1:0] [DATA_WIDTH-1:0] tile_west_write_data;
    
    // Tile status signals
    logic [TILES_Y-1:0][TILES_X-1:0] tile_north_queue_empty;
    logic [TILES_Y-1:0][TILES_X-1:0] tile_west_queue_empty;
    logic [TILES_Y-1:0][TILES_X-1:0] tile_matrix_mult_complete;
    logic [TILES_Y-1:0][TILES_X-1:0] tile_collection_complete;
    logic [TILES_Y-1:0][TILES_X-1:0] tile_collection_active;
    
    // Tile read interface
    logic [TILES_Y-1:0][TILES_X-1:0] tile_read_enable;
    logic [TILES_Y-1:0][TILES_X-1:0] [$clog2(TILE_ELEMENTS)-1:0] tile_read_addr;
    logic [TILES_Y-1:0][TILES_X-1:0] [DATA_WIDTH-1:0] tile_read_data;
    logic [TILES_Y-1:0][TILES_X-1:0] tile_read_valid;
    
    always_ff @(posedge clk_i or negedge rstn_i) begin
        if (!rstn_i) begin
            current_state <= IDLE;
        end else begin
            current_state <= next_state;
        end
    end
    
    always_comb begin
        next_state = current_state;
        
        case (current_state)
            IDLE: begin
                if (north_write_enable_i || west_write_enable_i) begin
                    next_state = FILLING_TILES;
                end
            end
            
            FILLING_TILES: begin
                if (start_matrix_mult_i) begin
                    next_state = PROCESSING;
                end
            end
            
            PROCESSING: begin
                if (matrix_mult_complete_o) begin
                    next_state = COMPLETE;
                end
            end
            
            COMPLETE: begin
                if (collection_complete_o) begin
                    next_state = IDLE;
                end
            end
        endcase
    end
    
    // Generate pulse when transitioning to PROCESSING state
    always_comb begin
        start_pulse = (current_state == FILLING_TILES) && (next_state == PROCESSING);
    end
    
    // Global element counter management
    always_ff @(posedge clk_i or negedge rstn_i) begin
        if (!rstn_i) begin
            north_global_element_count <= 0;
            west_global_element_count <= 0;
        end else begin
            north_global_element_count <= next_north_global_count;
            west_global_element_count <= next_west_global_count;
        end
    end
    
    // Global element counter logic
    always_comb begin
        // Default: keep current values
        next_north_global_count = north_global_element_count;
        next_west_global_count = west_global_element_count;
        
        // Reset on write reset
        if (north_write_reset_i || west_write_reset_i) begin
            next_north_global_count = 0;
            next_west_global_count = 0;
        end
        // Increment counters during filling
        else if (current_state == FILLING_TILES || (current_state == IDLE && (north_write_enable_i || west_write_enable_i))) begin
            
            // Track north writes
            if (north_write_enable_i) begin
                next_north_global_count = north_global_element_count + 1;
            end
            
            // Track west writes
            if (west_write_enable_i) begin
                next_west_global_count = west_global_element_count + 1;
            end
        end
    end
    
    // Matrix-based tile targeting logic
    always_comb begin
        // For north stream (weights) - COLUMN-MAJOR ORDER
        north_matrix_col = north_global_element_count / MATRIX_SIZE;  // Column changes first
        north_matrix_row = north_global_element_count % MATRIX_SIZE;  // Row cycles within column
        north_target_tile_y = north_matrix_row / TILE_SIZE;
        north_target_tile_x = north_matrix_col / TILE_SIZE;
        
        // For west stream (data) - ROW-MAJOR ORDER (unchanged)
        west_matrix_row = west_global_element_count / MATRIX_SIZE;
        west_matrix_col = west_global_element_count % MATRIX_SIZE;
        west_target_tile_y = west_matrix_row / TILE_SIZE;
        west_target_tile_x = west_matrix_col / TILE_SIZE;
    end
    
    // Generate tile instances
    generate
        for (genvar y = 0; y < TILES_Y; y++) begin : gen_tile_row
            for (genvar x = 0; x < TILES_X; x++) begin : gen_tile_col
                SystolicArray #(
                    .N(TILE_SIZE),
                    .DATA_WIDTH(DATA_WIDTH),
                    .ROWS(ROWS_MEM),
                    .COLS(COLS_MEM)
                ) tile_inst (
                    .clk_i(clk_i),
                    .rstn_i(rstn_i),
                    .start_matrix_mult_i(tile_start[y][x]),
                    
                    // North Queue Write interface
                    .north_write_enable_i(tile_north_write_enable[y][x]),
                    .north_write_data_i(tile_north_write_data[y][x]),
                    .north_write_reset_i(tile_north_write_reset[y][x]),
                    
                    // West Queue Write interface
                    .west_write_enable_i(tile_west_write_enable[y][x]),
                    .west_write_data_i(tile_west_write_data[y][x]),
                    .west_write_reset_i(tile_west_write_reset[y][x]),
                    
                    // Queue status
                    .north_queue_empty_o(tile_north_queue_empty[y][x]),
                    .west_queue_empty_o(tile_west_queue_empty[y][x]),
                    .matrix_mult_complete_o(tile_matrix_mult_complete[y][x]),
                    
                    // Read interface
                    .read_enable_i(tile_read_enable[y][x]),
                    .read_addr_i(tile_read_addr[y][x]),
                    .read_data_o(tile_read_data[y][x]),
                    .read_valid_o(tile_read_valid[y][x]),
                    
                    // Status signals
                    .collection_complete_o(tile_collection_complete[y][x]),
                    .collection_active_o(tile_collection_active[y][x])
                );
            end
        end
    endgenerate
    
    // Distribute data to tiles (matrix-based: each tile gets sub-matrix)
    always_comb begin
        // Initialize all tile signals to inactive
        for (int y = 0; y < TILES_Y; y++) begin
            for (int x = 0; x < TILES_X; x++) begin
                tile_north_write_enable[y][x] = 1'b0;
                tile_west_write_enable[y][x] = 1'b0;
                tile_north_write_data[y][x] = north_write_data_i;
                tile_west_write_data[y][x] = west_write_data_i;
                tile_north_write_reset[y][x] = north_write_reset_i;
                tile_west_write_reset[y][x] = west_write_reset_i;
                tile_start[y][x] = start_pulse;
            end
        end
        
        // Route write enables to target tiles based on matrix position
        if (current_state == FILLING_TILES || (current_state == IDLE && (north_write_enable_i || west_write_enable_i))) begin
            if (north_write_enable_i) begin
                tile_north_write_enable[north_target_tile_y][north_target_tile_x] = 1'b1;
            end
            if (west_write_enable_i) begin
                tile_west_write_enable[west_target_tile_y][west_target_tile_x] = 1'b1;
            end
        end
    end
    
    // Aggregate status signals
    always_comb begin
        north_queue_empty_o = 1'b1;
        west_queue_empty_o = 1'b1;
        matrix_mult_complete_o = 1'b1;
        collection_complete_o = 1'b1;
        collection_active_o = 1'b0;
        
        for (int y = 0; y < TILES_Y; y++) begin
            for (int x = 0; x < TILES_X; x++) begin
                north_queue_empty_o &= tile_north_queue_empty[y][x];
                west_queue_empty_o &= tile_west_queue_empty[y][x];
                matrix_mult_complete_o &= tile_matrix_mult_complete[y][x];
                collection_complete_o &= tile_collection_complete[y][x];
                collection_active_o |= tile_collection_active[y][x];
            end
        end
    end
    
    // Read interface address decoding (kept same as original)
    logic [$clog2(TILES_Y)-1:0] read_tile_y;
    logic [$clog2(TILES_X)-1:0] read_tile_x;
    logic [$clog2(TILE_ELEMENTS)-1:0] read_tile_addr;
    logic [$clog2(TOTAL_TILES)-1:0] read_tile_idx;
    
    always_comb begin
        read_tile_idx = read_addr_i / TILE_ELEMENTS;
        read_tile_addr = read_addr_i % TILE_ELEMENTS;
        read_tile_y = read_tile_idx / TILES_X;
        read_tile_x = read_tile_idx % TILES_X;
    end
    
    // Route read signals to appropriate tile
    always_comb begin
        for (int y = 0; y < TILES_Y; y++) begin
            for (int x = 0; x < TILES_X; x++) begin
                tile_read_enable[y][x] = (read_tile_y == y && read_tile_x == x) ? read_enable_i : 1'b0;
                tile_read_addr[y][x] = read_tile_addr;
            end
        end
    end
    
    // Multiplex read data output
    always_comb begin
        read_data_o = tile_read_data[read_tile_y][read_tile_x];
        read_valid_o = tile_read_valid[read_tile_y][read_tile_x];
    end

endmodule