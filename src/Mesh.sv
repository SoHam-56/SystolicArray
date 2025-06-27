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
    output wire accumulator_valid_o [0:N-1][0:N-1],
    output wire done_o
);

    // Internal connection wires
    // Data connections (North-South flow) - Fixed: needs N+1 rows for N PEs
    wire [DATA_WIDTH-1:0] weight_connections [0:N][0:N-1];

    // Weight connections (West-East flow) - Fixed: needs N+1 columns for N PEs
    wire [DATA_WIDTH-1:0] data_connections [0:N-1][0:N];

    // Valid signal connections (follow the systolic flow pattern)
    wire inputs_valid_internal [0:N-1][0:N-1];

    // Generate PE mesh with systematic connections
    genvar row, col;
    generate
        for (row = 0; row < N; row = row + 1) begin : gen_row
            for (col = 0; col < N; col = col + 1) begin : gen_col
                ProcessingElement #(
                    .DATA_WIDTH(DATA_WIDTH)
                ) pe_inst (
                    .clk_i(clk_i),
                    .rstn_i(rstn_i),
                    .north_i(weight_connections[row][col]),
                    .west_i(data_connections[row][col]),
                    .inputs_valid_i(inputs_valid_internal[row][col]),
                    .last_element_i(last_element_i),
                    .select_accumulator_i(select_accumulator_i[row][col]),
                    .south_o(weight_connections[row+1][col]),
                    .east_o(data_connections[row][col+1]),
                    .passthrough_valid_o(passthrough_valid_o[row][col]),
                    .accumulator_valid_o(accumulator_valid_o[row][col]),
                    .done_o(done_o)
                );
            end
        end
    endgenerate

    // Connect boundary inputs and outputs
    generate
        for (col = 0; col < N; col = col + 1) begin : gen_weight_boundary
            // Top boundary: Connect external weight inputs to first row
            assign weight_connections[0][col] = north_i[col];

            // Bottom boundary: Connect last row outputs to external outputs
            assign south_o[col] = weight_connections[N][col];
        end

        for (row = 0; row < N; row = row + 1) begin : gen_data_boundary
            // Left boundary: Connect external data inputs to first column
            assign data_connections[row][0] = west_i[row];

            // Right boundary: Connect last column outputs to external outputs
            assign east_o[row] = data_connections[row][N];
        end
    endgenerate

    // Connect inputs_valid signals following systolic flow pattern
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

endmodule
