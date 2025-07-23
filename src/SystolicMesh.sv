`timescale 1ns / 100ps

module SystolicMesh #(
    parameter MATRIX_SIZE   = 4,      // Total matrix dimension (N x N)
    parameter TILE_SIZE     = 2,      // Size of each tile (T x T)
    parameter DATA_WIDTH    = 32,     // Data width for each element
    parameter ROWS_MEM      = "rows.mem",
    parameter COLS_MEM      = "cols.mem"
) (
    input  logic                                                    clk_i,
    input  logic                                                    rstn_i,
    input  logic                                                    start_matrix_mult_i,

    // North Queue Write interface (Matrix B data)
    input  logic                                                    north_write_enable_i,
    input  logic [DATA_WIDTH-1:0]                                   north_write_data_i,
    input  logic                                                    north_write_reset_i,

    // West Queue Write interface (Matrix A data)
    input  logic                                                    west_write_enable_i,
    input  logic [DATA_WIDTH-1:0]                                   west_write_data_i,
    input  logic                                                    west_write_reset_i,

    // Status outputs
    output logic                                                    north_queue_empty_o,
    output logic                                                    west_queue_empty_o,
    output logic                                                    matrix_mult_complete_o,
    output logic                                                    allocation_complete_o
);

    // Calculate number of tiles needed for block matrix multiplication
    localparam NUM_TILES = MATRIX_SIZE / TILE_SIZE;           // Number of tiles per dimension (p)
    localparam TOTAL_PARTIAL_PRODUCTS = NUM_TILES * NUM_TILES * NUM_TILES;  // p^3 partial products
    localparam OUTPUT_TILES = NUM_TILES * NUM_TILES;          // p^2 output tiles
    localparam TILE_ELEMENTS = TILE_SIZE * TILE_SIZE;
    localparam MEM_DEPTH = MATRIX_SIZE * MATRIX_SIZE;
    localparam MEM_ADDR_WIDTH = $clog2(MEM_DEPTH);

    // Check that matrix size is divisible by tile size
    initial begin
        if (MATRIX_SIZE % TILE_SIZE != 0) begin
            $error("MATRIX_SIZE (%0d) must be divisible by TILE_SIZE (%0d)", MATRIX_SIZE, TILE_SIZE);
        end
        $display("Block Matrix Multiplication Configuration:");
        $display("  Matrix Size: %0dx%0d", MATRIX_SIZE, MATRIX_SIZE);
        $display("  Tile Size: %0dx%0d", TILE_SIZE, TILE_SIZE);
        $display("  Tiles per dimension (p): %0d", NUM_TILES);
        $display("  Total partial products: %0d", TOTAL_PARTIAL_PRODUCTS);
        $display("  Output tiles: %0d", OUTPUT_TILES);
    end

    typedef enum logic [2:0] {
        IDLE,
        FILLING_MEMORY,
        ALLOCATING_DATA,
        PROCESSING,
        ACCUMULATING,
        COMPLETE
    } state_t;

    state_t current_state, next_state;

    // Internal memory instances for storing full matrices
    logic north_mem_read_enable, west_mem_read_enable;
    logic [MEM_ADDR_WIDTH-1:0] north_mem_read_addr, west_mem_read_addr;
    logic [DATA_WIDTH-1:0] north_mem_read_data, west_mem_read_data;
    logic north_mem_read_valid, west_mem_read_valid;
    logic north_mem_empty, west_mem_empty;
    logic north_mem_full, west_mem_full;
    logic [MEM_ADDR_WIDTH:0] north_fill_count, west_fill_count;

    // Memory for Matrix A (west input)
    InternalMemory #(
        .DATA_WIDTH(DATA_WIDTH),
        .MEM_DEPTH(MEM_DEPTH),
        .ADDR_WIDTH(MEM_ADDR_WIDTH)
    ) west_memory (
        .clk_i(clk_i),
        .rstn_i(rstn_i),
        .write_enable_i(west_write_enable_i),
        .write_data_i(west_write_data_i),
        .write_reset_i(west_write_reset_i),
        .read_enable_i(west_mem_read_enable),
        .read_addr_i(west_mem_read_addr),
        .read_data_o(west_mem_read_data),
        .read_valid_o(west_mem_read_valid),
        .memory_empty_o(west_mem_empty),
        .memory_full_o(west_mem_full),
        .fill_count_o(west_fill_count)
    );

    // Memory for Matrix B (north input)
    InternalMemory #(
        .DATA_WIDTH(DATA_WIDTH),
        .MEM_DEPTH(MEM_DEPTH),
        .ADDR_WIDTH(MEM_ADDR_WIDTH)
    ) north_memory (
        .clk_i(clk_i),
        .rstn_i(rstn_i),
        .write_enable_i(north_write_enable_i),
        .write_data_i(north_write_data_i),
        .write_reset_i(north_write_reset_i),
        .read_enable_i(north_mem_read_enable),
        .read_addr_i(north_mem_read_addr),
        .read_data_o(north_mem_read_data),
        .read_valid_o(north_mem_read_valid),
        .memory_empty_o(north_mem_empty),
        .memory_full_o(north_mem_full),
        .fill_count_o(north_fill_count)
    );

    // Address mapping functions for block matrix multiplication
    function automatic logic [MEM_ADDR_WIDTH-1:0] get_matrix_a_addr(
        input logic [$clog2(NUM_TILES)-1:0] output_tile_row,  // i
        input logic [$clog2(NUM_TILES)-1:0] k_idx,           // k
        input logic [$clog2(TILE_SIZE)-1:0] elem_row,
        input logic [$clog2(TILE_SIZE)-1:0] elem_col
    );
        logic [MEM_ADDR_WIDTH-1:0] global_row, global_col;
        global_row = output_tile_row * TILE_SIZE + elem_row;
        global_col = k_idx * TILE_SIZE + elem_col;
        return global_row * MATRIX_SIZE + global_col;
    endfunction

    function automatic logic [MEM_ADDR_WIDTH-1:0] get_matrix_b_addr(
        input logic [$clog2(NUM_TILES)-1:0] k_idx,           // k
        input logic [$clog2(NUM_TILES)-1:0] output_tile_col, // j
        input logic [$clog2(TILE_SIZE)-1:0] elem_row,
        input logic [$clog2(TILE_SIZE)-1:0] elem_col
    );
        logic [MEM_ADDR_WIDTH-1:0] global_row, global_col;
        global_row = k_idx * TILE_SIZE + elem_row;
        global_col = output_tile_col * TILE_SIZE + elem_col;
        return global_row * MATRIX_SIZE + global_col;
    endfunction

    // Block matrix multiplication control logic
    logic allocation_active;
    logic allocation_complete;
    logic [$clog2(TOTAL_PARTIAL_PRODUCTS)-1:0] current_partial_product_idx;
    logic [$clog2(TILE_ELEMENTS)-1:0] current_element_idx;

    // Block indices for C[i,j] = sum over k of A[i,k] * B[k,j]
    logic [$clog2(NUM_TILES)-1:0] current_output_tile_row;    // i
    logic [$clog2(NUM_TILES)-1:0] current_output_tile_col;    // j
    logic [$clog2(NUM_TILES)-1:0] current_k_idx;             // k

    // Element indices within current tile
    logic [$clog2(TILE_SIZE)-1:0] current_elem_row, current_elem_col;

    // Check if memories are ready for allocation
    logic memories_ready;
    always_comb begin
        memories_ready = (north_fill_count >= MEM_DEPTH) && (west_fill_count >= MEM_DEPTH);
    end

    // State machine
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
                    next_state = FILLING_MEMORY;
                end
            end

            FILLING_MEMORY: begin
                if (memories_ready) begin
                    next_state = ALLOCATING_DATA;
                end
            end

            ALLOCATING_DATA: begin
                if (allocation_complete) begin
                    next_state = PROCESSING;
                end
            end

            PROCESSING: begin
                if (matrix_mult_complete_o) begin
                    next_state = ACCUMULATING;
                end
            end

            ACCUMULATING: begin
                // Add accumulation logic here if needed
                next_state = COMPLETE;
            end

            COMPLETE: begin
                // Can add logic to return to IDLE when results are read
                next_state = COMPLETE;
            end
        endcase
    end

    // Allocation counter logic for block matrix multiplication
    always_ff @(posedge clk_i or negedge rstn_i) begin
        if (!rstn_i) begin
            allocation_active <= 1'b0;
            current_partial_product_idx <= 0;
            current_element_idx <= 0;
            current_output_tile_row <= 0;
            current_output_tile_col <= 0;
            current_k_idx <= 0;
            current_elem_row <= 0;
            current_elem_col <= 0;
        end else if (current_state == IDLE) begin
            allocation_active <= 1'b0;
            current_partial_product_idx <= 0;
            current_element_idx <= 0;
            current_output_tile_row <= 0;
            current_output_tile_col <= 0;
            current_k_idx <= 0;
            current_elem_row <= 0;
            current_elem_col <= 0;
        end else if (current_state == ALLOCATING_DATA) begin
            allocation_active <= 1'b1;

            // Advance allocation counters when data is being written to tiles
            if (tile_allocation_active) begin
                if (current_elem_col == TILE_SIZE - 1) begin
                    current_elem_col <= 0;
                    if (current_elem_row == TILE_SIZE - 1) begin
                        current_elem_row <= 0;
                        if (current_element_idx == TILE_ELEMENTS - 1) begin
                            current_element_idx <= 0;
                            // Move to next partial product: A[i,k] * B[k,j]
                            if (current_k_idx == NUM_TILES - 1) begin
                                current_k_idx <= 0;
                                if (current_output_tile_col == NUM_TILES - 1) begin
                                    current_output_tile_col <= 0;
                                    if (current_output_tile_row == NUM_TILES - 1) begin
                                        current_output_tile_row <= 0;
                                    end else begin
                                        current_output_tile_row <= current_output_tile_row + 1;
                                    end
                                end else begin
                                    current_output_tile_col <= current_output_tile_col + 1;
                                end
                            end else begin
                                current_k_idx <= current_k_idx + 1;
                            end

                            if (current_partial_product_idx == TOTAL_PARTIAL_PRODUCTS - 1) begin
                                current_partial_product_idx <= 0;
                            end else begin
                                current_partial_product_idx <= current_partial_product_idx + 1;
                            end
                        end else begin
                            current_element_idx <= current_element_idx + 1;
                        end
                    end else begin
                        current_elem_row <= current_elem_row + 1;
                    end
                end else begin
                    current_elem_col <= current_elem_col + 1;
                end
            end
        end
    end

    // Check if allocation is complete
    logic tile_allocation_active;
    always_comb begin
        allocation_complete = (current_partial_product_idx == TOTAL_PARTIAL_PRODUCTS - 1) && (current_element_idx == TILE_ELEMENTS - 1);
        tile_allocation_active = allocation_active && !allocation_complete;
    end

    // Memory read control for allocation
    always_comb begin
        north_mem_read_enable = 1'b0;
        west_mem_read_enable = 1'b0;
        north_mem_read_addr = 0;
        west_mem_read_addr = 0;

        if (current_state == ALLOCATING_DATA && tile_allocation_active) begin
            // Calculate addresses for current partial product A[i,k] * B[k,j]
            west_mem_read_addr = get_matrix_a_addr(current_output_tile_row, current_k_idx,
                                                  current_elem_row, current_elem_col);
            north_mem_read_addr = get_matrix_b_addr(current_k_idx, current_output_tile_col,
                                                   current_elem_row, current_elem_col);

            north_mem_read_enable = !north_mem_empty;
            west_mem_read_enable = !west_mem_empty;
        end
    end

    // Tile interface arrays - generate tiles for partial products
    logic [TOTAL_PARTIAL_PRODUCTS-1:0] tile_start;
    logic [TOTAL_PARTIAL_PRODUCTS-1:0] tile_north_write_enable;
    logic [TOTAL_PARTIAL_PRODUCTS-1:0] tile_west_write_enable;
    logic [TOTAL_PARTIAL_PRODUCTS-1:0] tile_north_write_reset;
    logic [TOTAL_PARTIAL_PRODUCTS-1:0] tile_west_write_reset;
    logic [TOTAL_PARTIAL_PRODUCTS-1:0][DATA_WIDTH-1:0] tile_north_write_data;
    logic [TOTAL_PARTIAL_PRODUCTS-1:0][DATA_WIDTH-1:0] tile_west_write_data;

    // Tile status signals
    logic [TOTAL_PARTIAL_PRODUCTS-1:0] tile_north_queue_empty;
    logic [TOTAL_PARTIAL_PRODUCTS-1:0] tile_west_queue_empty;
    logic [TOTAL_PARTIAL_PRODUCTS-1:0] tile_matrix_mult_complete;

    // Generate the required number of tiles for partial products
    generate
        for (genvar t = 0; t < TOTAL_PARTIAL_PRODUCTS; t++) begin : gen_partial_product_tiles
            SystolicArray #(
                .N(TILE_SIZE),
                .DATA_WIDTH(DATA_WIDTH),
                .ROWS(ROWS_MEM),
                .COLS(COLS_MEM)
            ) partial_product_tile (
                .clk_i(clk_i),
                .rstn_i(rstn_i),
                .start_matrix_mult_i(tile_start[t]),

                // North Queue Write interface
                .north_write_enable_i(tile_north_write_enable[t]),
                .north_write_data_i(tile_north_write_data[t]),
                .north_write_reset_i(tile_north_write_reset[t]),

                // West Queue Write interface
                .west_write_enable_i(tile_west_write_enable[t]),
                .west_write_data_i(tile_west_write_data[t]),
                .west_write_reset_i(tile_west_write_reset[t]),

                // Queue status
                .north_queue_empty_o(tile_north_queue_empty[t]),
                .west_queue_empty_o(tile_west_queue_empty[t]),
                .matrix_mult_complete_o(tile_matrix_mult_complete[t]),

                // Read interface (not connected for now as requested)
                .read_enable_i(1'b0),
                .read_addr_i('h0),
                .read_data_o(),
                .read_valid_o(),

                // Status signals (not connected for now)
                .collection_complete_o(),
                .collection_active_o()
            );
        end
    endgenerate

    // Route data to tiles during allocation
    always_comb begin
        // Initialize all tile signals
        for (int t = 0; t < TOTAL_PARTIAL_PRODUCTS; t++) begin
            tile_north_write_enable[t] = 1'b0;
            tile_west_write_enable[t] = 1'b0;
            tile_north_write_data[t] = north_mem_read_data;
            tile_west_write_data[t] = west_mem_read_data;
            tile_north_write_reset[t] = north_write_reset_i;
            tile_west_write_reset[t] = west_write_reset_i;
            tile_start[t] = start_matrix_mult_i && (current_state == ALLOCATING_DATA);
        end

        // Route data to current partial product tile during allocation
        if (current_state == ALLOCATING_DATA && tile_allocation_active) begin
            tile_north_write_enable[current_partial_product_idx] = north_mem_read_valid;
            tile_west_write_enable[current_partial_product_idx] = west_mem_read_valid;
        end
    end

    // Aggregate status signals
    always_comb begin
        north_queue_empty_o = north_mem_empty;
        west_queue_empty_o = west_mem_empty;
        matrix_mult_complete_o = 1'b1;
        allocation_complete_o = allocation_complete;

        for (int t = 0; t < TOTAL_PARTIAL_PRODUCTS; t++) begin
            matrix_mult_complete_o &= tile_matrix_mult_complete[t];
        end
    end

endmodule

module InternalMemory #(
    parameter DATA_WIDTH = 32,
    parameter MEM_DEPTH = 64,
    parameter ADDR_WIDTH = $clog2(MEM_DEPTH)
) (
    input  logic                        clk_i,
    input  logic                        rstn_i,

    // Write interface
    input  logic                        write_enable_i,
    input  logic [DATA_WIDTH-1:0]       write_data_i,
    input  logic                        write_reset_i,

    // Read interface
    input  logic                        read_enable_i,
    input  logic [ADDR_WIDTH-1:0]       read_addr_i,
    output logic [DATA_WIDTH-1:0]       read_data_o,
    output logic                        read_valid_o,

    // Status signals
    output logic                        memory_empty_o,
    output logic                        memory_full_o,
    output logic [ADDR_WIDTH:0]         fill_count_o
);
    logic [DATA_WIDTH-1:0] memory [0:MEM_DEPTH-1];
    logic [ADDR_WIDTH:0] write_ptr;
    logic [ADDR_WIDTH:0] fill_count;

    always_ff @(posedge clk_i or negedge rstn_i) begin
        if (!rstn_i) begin
            write_ptr <= 0;
            fill_count <= 0;
        end else if (write_reset_i) begin
            write_ptr <= 0;
            fill_count <= 0;
        end else if (write_enable_i && !memory_full_o) begin
            write_ptr <= (write_ptr == MEM_DEPTH-1) ? 0 : write_ptr + 1;
            fill_count <= fill_count + 1;
        end
    end

    always_ff @(posedge clk_i)
        if (write_enable_i && !memory_full_o) memory[write_ptr] <= write_data_i;

    always_ff @(posedge clk_i or negedge rstn_i) begin
        if (!rstn_i) begin
            read_data_o <= 0;
            read_valid_o <= 1'b0;
        end else begin
            read_valid_o <= read_enable_i && !memory_empty_o;
            if (read_enable_i && !memory_empty_o) read_data_o <= memory[read_addr_i];
        end
    end

    assign memory_empty_o = (fill_count == 0);
    assign memory_full_o = (fill_count == MEM_DEPTH);
    assign fill_count_o = fill_count;

endmodule
