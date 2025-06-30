`timescale 1ns / 100ps

module Mesh #(
    parameter N = 2,                    // Array size (NxN)
    parameter DATA_WIDTH = 32           // Data width for each PE
)(
    input wire clk_i,
    input wire rstn_i,

    // Data inputs (top row - North boundary)
    input wire [DATA_WIDTH-1:0] north_i [0:N-1],

    // Weight inputs (left column - West boundary)
    input wire [DATA_WIDTH-1:0] west_i [0:N-1],

    // Control inputs
    input wire inputs_valid_i,                          // Single input valid for top-left PE
    input wire last_element_i,                          // Pulse that indicates last element has been released from InputQueue
    input wire select_accumulator_i [0:N-1][0:N-1],     // Individual accumulator select for each PE

    // Data outputs (bottom row - South boundary)
    output wire [DATA_WIDTH-1:0] south_o [0:N-1],

    // Weight outputs (right column - East boundary)
    output wire [DATA_WIDTH-1:0] east_o [0:N-1],

    // Status outputs for each PE
    output wire passthrough_valid_o [0:N-1][0:N-1],
    output reg done_o,

    // Last element output (right column - East boundary) for bottom row
    output wire last_element_east_o [0:N-1]
);

    // Data connections (North-South flow)
    wire [DATA_WIDTH-1:0] north_connections [0:N][0:N-1];

    // Weight connections (West-East flow)
    wire [DATA_WIDTH-1:0] west_connections [0:N-1][0:N];

    // Valid signal connections (follow the systolic flow pattern)
    wire inputs_valid_internal [0:N-1][0:N-1];

    // last_element connections (horizontal flow in bottom row)
    wire last_element_horizontal [0:N-1][0:N];

    // Done logic state tracking
    reg last_element_seen;
    reg waiting_for_passthrough;

    // Drain mode logic
    reg drain_mode;
    reg [31:0] drain_step_counter;  // Counts steps 0 to N-1 for each column
    
    // Internal select_accumulator signal
    wire select_accumulator_internal [0:N-1][0:N-1];

    // Drain state machine
    typedef enum logic [1:0] {
        DRAIN_IDLE,
        DRAIN_PULSE,
        DRAIN_WAIT,
        DRAIN_COMPLETE
    } drain_state_t;
    
    drain_state_t drain_state;

    genvar row, col;
    generate
        for (row = 0; row < N; row = row + 1) begin : gen_row
            for (col = 0; col < N; col = col + 1) begin : gen_col
                ProcessingElement #(
                    .DATA_WIDTH(DATA_WIDTH)
                ) pe_inst (
                    .clk_i(clk_i),
                    .rstn_i(rstn_i),
                    .north_i(north_connections[row][col]),
                    .west_i(west_connections[row][col]),
                    .inputs_valid_i(inputs_valid_internal[row][col]),
                    .last_element_i(last_element_horizontal[row][col]),
                    .select_accumulator_i(select_accumulator_internal[row][col]),
                    .drain_mode_i(drain_mode),
                    .south_o(north_connections[row+1][col]),
                    .east_o(west_connections[row][col+1]),
                    .passthrough_valid_o(passthrough_valid_o[row][col]),
                    .last_element_east_o(last_element_horizontal[row][col+1])
                );
            end
        end
    endgenerate

    // Connect boundary inputs and outputs
    generate
        for (col = 0; col < N; col = col + 1) begin : gen_weight_boundary
            // Top boundary: Connect external weight inputs to first row
            assign north_connections[0][col] = north_i[col];

            // Bottom boundary: Connect last row outputs to external outputs
            assign south_o[col] = north_connections[N][col];
        end

        for (row = 0; row < N; row = row + 1) begin : gen_data_boundary
            // Left boundary: Connect external data inputs to first column
            assign west_connections[row][0] = west_i[row];

            // Right boundary: Connect last column outputs to external outputs
            assign east_o[row] = west_connections[row][N];
        end
    endgenerate

    // Connect last_element signals 
    generate
        for (row = 0; row < N; row = row + 1) begin : gen_last_element_boundary
            if (row == N-1) begin
                // Bottom row: Connect external last_element_i only to leftmost PE
                assign last_element_horizontal[row][0] = last_element_i;
                // Bottom row: Connect rightmost PE output to external output
                assign last_element_east_o[row] = last_element_horizontal[row][N];
            end else begin
                // Other rows: No last_element input
                assign last_element_horizontal[row][0] = 1'b0;
                // Other rows: No last_element output
                assign last_element_east_o[row] = 1'b0;
            end
        end
    endgenerate

    // Drain mode control logic - generate pulses and wait for data propagation
    reg data_collected;  // Flag to track when data has been collected from rightmost column
    
    always @(posedge clk_i or negedge rstn_i) begin
        if (!rstn_i) begin
            drain_mode <= 1'b0;
            drain_step_counter <= 0;
            drain_state <= DRAIN_IDLE;
            data_collected <= 1'b0;
        end else begin
            case (drain_state)
                DRAIN_IDLE: begin
                    if (done_o && !drain_mode) begin
                        // Enter drain mode after matrix multiplication is done
                        drain_mode <= 1'b1;
                        drain_step_counter <= 0;
                        drain_state <= DRAIN_PULSE;
                        data_collected <= 1'b0;
                    end
                end
                
                DRAIN_PULSE: begin
                    // Generate select_accumulator pulse for current column
                    // Pulse is generated for one clock cycle, then move to wait state
                    drain_state <= DRAIN_WAIT;
                    data_collected <= 1'b0;  // Reset data collection flag
                end
                
                DRAIN_WAIT: begin
                    // Wait for data from current column to propagate and appear at rightmost PEs
                    logic any_rightmost_valid;
                    any_rightmost_valid = 1'b0;
                    for (int i = 0; i < N; i++) begin
                        if (passthrough_valid_o[i][N-1]) begin
                            any_rightmost_valid = 1'b1;
                        end
                    end
                    
                    // Track when data appears at the rightmost column
                    if (any_rightmost_valid && !data_collected) begin
                        data_collected <= 1'b1;
                    end
                    
                    // Move to next column only after data has been collected and is no longer valid
                    // This ensures the external system has had time to capture the data
                    if (data_collected && !any_rightmost_valid) begin
                        // Data has been collected and is no longer present, move to next column
                        if (drain_step_counter < N-1) begin
                            drain_step_counter <= drain_step_counter + 1;
                            drain_state <= DRAIN_PULSE;  // Generate pulse for next column
                        end else begin
                            // All columns drained
                            drain_state <= DRAIN_COMPLETE;
                        end
                    end
                end
                
                DRAIN_COMPLETE: begin
                    // Stay in this state - drain is complete
                end
            endcase
        end
    end

    // Generate select_accumulator pulses: Only active during DRAIN_PULSE state
    generate
        for (row = 0; row < N; row = row + 1) begin : gen_select_mux_row
            for (col = 0; col < N; col = col + 1) begin : gen_select_mux_col
                assign select_accumulator_internal[row][col] = drain_mode ? 
                    (drain_state == DRAIN_PULSE && col == drain_step_counter) : 
                    select_accumulator_i[row][col];
            end
        end
    endgenerate

    // Connect inputs_valid signals following systolic flow pattern
    // During drain mode, PEs will use drain_mode_i to bypass MAC operations
    generate
        for (row = 0; row < N; row = row + 1) begin : gen_valid_row
            for (col = 0; col < N; col = col + 1) begin : gen_valid_col
                if (row == 0 && col == 0) begin
                    // Top-left PE gets external inputs_valid
                    assign inputs_valid_internal[row][col] = inputs_valid_i;
                end
                else if (row == 0) begin
                    // Top row (except top-left): gets valid from western neighbor
                    assign inputs_valid_internal[row][col] = passthrough_valid_o[row][col-1];
                end
                else if (col == 0) begin
                    // Left column (except top-left): gets valid from northern neighbor
                    assign inputs_valid_internal[row][col] = passthrough_valid_o[row-1][col];
                end
                else begin
                    // Interior PEs: AND of northern and western neighbor valid signals
                    assign inputs_valid_internal[row][col] = passthrough_valid_o[row-1][col] & passthrough_valid_o[row][col-1];
                end
            end
        end
    endgenerate

    // Done logic: Monitor bottom-right PE (PE[N-1][N-1])
    always @(posedge clk_i or negedge rstn_i) begin
        if (!rstn_i) begin
            last_element_seen <= 1'b0;
            waiting_for_passthrough <= 1'b0;
            done_o <= 1'b0;
        end else begin
            if (!drain_mode) begin
                // Step 1: Detect last_element_east_o pulse from bottom-right PE
                if (last_element_horizontal[N-1][N] && !last_element_seen) begin
                    last_element_seen <= 1'b1;
                    waiting_for_passthrough <= 1'b1;
                end
                
                // Step 2: After seeing last_element, wait for passthrough_valid_o pulse
                if (waiting_for_passthrough && passthrough_valid_o[N-1][N-1]) begin
                    done_o <= 1'b1;
                    waiting_for_passthrough <= 1'b0;
                end
            end
        end
    end

endmodule