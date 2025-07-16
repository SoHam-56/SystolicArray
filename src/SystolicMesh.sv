`timescale 1ns / 100ps

module SystolicMesh #(
    parameter TILE_SIZE     = 8,      // Size of each systolic array tile (N x N)
    parameter DATA_WIDTH    = 32,     // Data width for each element
    parameter TILES_X       = 4,      // Number of tiles in X direction (columns)
    parameter TILES_Y       = 4,      // Number of tiles in Y direction (rows)
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

    // Unified SRAM status signals
    output logic                                    collection_complete_o,
    output logic                                    collection_active_o
);

    // Local parameters
    localparam TOTAL_TILES = TILES_X * TILES_Y;
    localparam TILE_SRAM_SIZE = TILE_SIZE * TILE_SIZE;
    localparam UNIFIED_SRAM_SIZE = TILE_SRAM_SIZE * TOTAL_TILES;
    localparam TILE_ADDR_BITS = $clog2(TILE_SRAM_SIZE);
    localparam UNIFIED_ADDR_BITS = $clog2(UNIFIED_SRAM_SIZE);

    // Tile control signals
    logic [TOTAL_TILES-1:0] tile_start;
    logic [TOTAL_TILES-1:0] tile_north_write_enable;
    logic [TOTAL_TILES-1:0] tile_west_write_enable;
    logic [TOTAL_TILES-1:0] tile_north_write_reset;
    logic [TOTAL_TILES-1:0] tile_west_write_reset;

    // Tile status signals
    logic [TOTAL_TILES-1:0] tile_north_queue_empty;
    logic [TOTAL_TILES-1:0] tile_west_queue_empty;
    logic [TOTAL_TILES-1:0] tile_matrix_mult_complete;
    logic [TOTAL_TILES-1:0] tile_collection_complete;
    logic [TOTAL_TILES-1:0] tile_collection_active;

    // Tile SRAM read interfaces
    logic [TOTAL_TILES-1:0] tile_read_enable;
    logic [TILE_ADDR_BITS-1:0] tile_read_addr [TOTAL_TILES-1:0];
    logic [DATA_WIDTH-1:0] tile_read_data [TOTAL_TILES-1:0];
    logic [TOTAL_TILES-1:0] tile_read_valid;

    // Input distribution state machine
    typedef enum logic [2:0] {
        IDLE,
        LOADING_WEIGHTS,
        LOADING_DATA,
        PROCESSING,
        COLLECTING
    } state_t;

    state_t current_state, next_state;

    // Tile address counters for input distribution
    logic [$clog2(TILES_X)-1:0] weight_tile_x;
    logic [$clog2(TILES_Y)-1:0] weight_tile_y;
    logic [$clog2(TILES_X)-1:0] data_tile_x;
    logic [$clog2(TILES_Y)-1:0] data_tile_y;

    // Unified SRAM for collecting results
    logic [DATA_WIDTH-1:0] unified_sram [UNIFIED_SRAM_SIZE-1:0];
    logic collection_in_progress;
    logic [$clog2(TOTAL_TILES)-1:0] current_collecting_tile;
    logic [TILE_ADDR_BITS-1:0] current_tile_addr;
    logic collection_state_machine_active;

    // Generate systolic array tiles
    genvar i, j;
    generate
        for (i = 0; i < TILES_Y; i++) begin : gen_tiles_y
            for (j = 0; j < TILES_X; j++) begin : gen_tiles_x
                localparam TILE_ID = i * TILES_X + j;

                SystolicArray #(
                    .N          (TILE_SIZE),
                    .DATA_WIDTH (DATA_WIDTH),
                    .ROWS       (ROWS_MEM),
                    .COLS       (COLS_MEM)
                ) tile_inst (
                    .clk_i                    (clk_i),
                    .rstn_i                   (rstn_i),
                    .start_matrix_mult_i      (tile_start[TILE_ID]),

                    .north_write_enable_i     (tile_north_write_enable[TILE_ID]),
                    .north_write_data_i       (north_write_data_i),
                    .north_write_reset_i      (tile_north_write_reset[TILE_ID]),

                    .west_write_enable_i      (tile_west_write_enable[TILE_ID]),
                    .west_write_data_i        (west_write_data_i),
                    .west_write_reset_i       (tile_west_write_reset[TILE_ID]),

                    .north_queue_empty_o      (tile_north_queue_empty[TILE_ID]),
                    .west_queue_empty_o       (tile_west_queue_empty[TILE_ID]),
                    .matrix_mult_complete_o   (tile_matrix_mult_complete[TILE_ID]),

                    .read_enable_i            (tile_read_enable[TILE_ID]),
                    .read_addr_i              (tile_read_addr[TILE_ID]),
                    .read_data_o              (tile_read_data[TILE_ID]),
                    .read_valid_o             (tile_read_valid[TILE_ID]),

                    .collection_complete_o    (tile_collection_complete[TILE_ID]),
                    .collection_active_o      (tile_collection_active[TILE_ID])
                );
            end
        end
    endgenerate

    // Input distribution logic
    always_comb begin
        // Default values
        tile_start = '0;
        tile_north_write_enable = '0;
        tile_west_write_enable = '0;
        tile_north_write_reset = '0;
        tile_west_write_reset = '0;

        case (current_state)
            IDLE: begin
                if (start_matrix_mult_i) begin
                    tile_start = {TOTAL_TILES{1'b1}};
                end
            end

            LOADING_WEIGHTS: begin
                if (north_write_enable_i) begin
                    tile_north_write_enable[weight_tile_y * TILES_X + weight_tile_x] = 1'b1;
                end
                if (north_write_reset_i) begin
                    tile_north_write_reset = {TOTAL_TILES{1'b1}};
                end
            end

            LOADING_DATA: begin
                if (west_write_enable_i) begin
                    tile_west_write_enable[data_tile_y * TILES_X + data_tile_x] = 1'b1;
                end
                if (west_write_reset_i) begin
                    tile_west_write_reset = {TOTAL_TILES{1'b1}};
                end
            end

            PROCESSING: begin
                // All tiles are processing
            end

            COLLECTING: begin
                // Collection logic handled separately
            end
        endcase
    end

    // State machine for overall control
    always_ff @(posedge clk_i or negedge rstn_i) begin
        if (!rstn_i) begin
            current_state <= IDLE;
            weight_tile_x <= 0;
            weight_tile_y <= 0;
            data_tile_x <= 0;
            data_tile_y <= 0;
        end else begin
            current_state <= next_state;

            // Update tile counters for input distribution
            if (current_state == LOADING_WEIGHTS && north_write_enable_i) begin
                if (weight_tile_x == TILES_X - 1) begin
                    weight_tile_x <= 0;
                    if (weight_tile_y == TILES_Y - 1) begin
                        weight_tile_y <= 0;
                    end else begin
                        weight_tile_y <= weight_tile_y + 1;
                    end
                end else begin
                    weight_tile_x <= weight_tile_x + 1;
                end
            end

            if (current_state == LOADING_DATA && west_write_enable_i) begin
                if (data_tile_x == TILES_X - 1) begin
                    data_tile_x <= 0;
                    if (data_tile_y == TILES_Y - 1) begin
                        data_tile_y <= 0;
                    end else begin
                        data_tile_y <= data_tile_y + 1;
                    end
                end else begin
                    data_tile_x <= data_tile_x + 1;
                end
            end
        end
    end

    // Next state logic
    always_comb begin
        next_state = current_state;

        case (current_state)
            IDLE: begin
                if (start_matrix_mult_i) begin
                    next_state = LOADING_WEIGHTS;
                end
            end

            LOADING_WEIGHTS: begin
                if (&tile_north_queue_empty == 1'b0) begin // All queues have data
                    next_state = LOADING_DATA;
                end
            end

            LOADING_DATA: begin
                if (&tile_west_queue_empty == 1'b0) begin // All queues have data
                    next_state = PROCESSING;
                end
            end

            PROCESSING: begin
                if (&tile_matrix_mult_complete) begin
                    next_state = COLLECTING;
                end
            end

            COLLECTING: begin
                if (&tile_collection_complete) begin
                    next_state = IDLE;
                end
            end
        endcase
    end

    // Output collection state machine
    always_ff @(posedge clk_i or negedge rstn_i) begin
        if (!rstn_i) begin
            collection_in_progress <= 1'b0;
            current_collecting_tile <= 0;
            current_tile_addr <= 0;
            collection_state_machine_active <= 1'b0;
        end else begin
            if (current_state == COLLECTING && !collection_in_progress) begin
                collection_in_progress <= 1'b1;
                collection_state_machine_active <= 1'b1;
                current_collecting_tile <= 0;
                current_tile_addr <= 0;
            end else if (collection_in_progress) begin
                if (tile_read_valid[current_collecting_tile]) begin
                    // Store data in unified SRAM
                    unified_sram[current_collecting_tile * TILE_SRAM_SIZE + current_tile_addr] <= tile_read_data[current_collecting_tile];

                    if (current_tile_addr == TILE_SRAM_SIZE - 1) begin
                        current_tile_addr <= 0;
                        if (current_collecting_tile == TOTAL_TILES - 1) begin
                            collection_in_progress <= 1'b0;
                            collection_state_machine_active <= 1'b0;
                        end else begin
                            current_collecting_tile <= current_collecting_tile + 1;
                        end
                    end else begin
                        current_tile_addr <= current_tile_addr + 1;
                    end
                end
            end
        end
    end

    // Tile read enable generation for collection
    always_comb begin
        tile_read_enable = '0;
        for (int k = 0; k < TOTAL_TILES; k++) begin
            tile_read_addr[k] = current_tile_addr;
            if (collection_in_progress && k == current_collecting_tile) begin
                tile_read_enable[k] = 1'b1;
            end
        end
    end

    // Unified SRAM read logic
    always_ff @(posedge clk_i or negedge rstn_i) begin
        if (!rstn_i) begin
            read_data_o <= '0;
            read_valid_o <= 1'b0;
        end else begin
            if (read_enable_i && read_addr_i < UNIFIED_SRAM_SIZE) begin
                read_data_o <= unified_sram[read_addr_i];
                read_valid_o <= 1'b1;
            end else begin
                read_valid_o <= 1'b0;
            end
        end
    end

    // Output status signals
    assign north_queue_empty_o = &tile_north_queue_empty;
    assign west_queue_empty_o = &tile_west_queue_empty;
    assign matrix_mult_complete_o = &tile_matrix_mult_complete;
    assign collection_complete_o = &tile_collection_complete && !collection_state_machine_active;
    assign collection_active_o = |tile_collection_active || collection_state_machine_active;

endmodule
