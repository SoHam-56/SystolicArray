`timescale 1ns / 100ps

module SystolicArray #(
    parameter N = 8,
    parameter DATA_WIDTH = 32,
    parameter ROWS = "rows.mem",
    parameter COLS = "cols.mem"
) (
    input logic                   clk_i,
    input logic                   rstn_i,
    input logic                   start_matrix_mult_i,

    // North Queue Write interface
    input logic                   north_write_enable_i,
    input logic [DATA_WIDTH-1:0]  north_write_data_i,
    input logic                   north_write_reset_i,

    // West Queue Write interface
    input logic                   west_write_enable_i,
    input logic [DATA_WIDTH-1:0]  west_write_data_i,
    input logic                   west_write_reset_i,

    // Outputs from systolic array
    output logic [DATA_WIDTH-1:0] south_o [0:N-1],
    output logic [DATA_WIDTH-1:0] east_o [0:N-1],
    output logic                  accumulator_valid_o [0:N-1][0:N-1],

    // Queue status
    output logic                  north_queue_empty_o,
    output logic                  west_queue_empty_o,
    output logic                  matrix_mult_complete_o
);
    // Internal signals
    logic [DATA_WIDTH-1:0] weight_in_north [0:N-1];
    logic [DATA_WIDTH-1:0] data_in_west [0:N-1];
    logic inputs_valid;
    logic passthrough_valid [0:N-1][0:N-1];
    logic select_accumulator [0:N-1][0:N-1];

    // Extract edge passthrough_valid signals
    logic [N-1:0] top_edge_passthrough_valid;
    logic [N-1:0] left_edge_passthrough_valid;
    logic [N-1:0] last_row, last_col;

    always_comb begin
        for (int i = 0; i < N; i++) begin
            top_edge_passthrough_valid[i] = passthrough_valid[0][i];  // Extract top edge (row 0) passthrough_valid
            left_edge_passthrough_valid[i] = passthrough_valid[i][0]; // Extract left edge (column 0) passthrough_valid
        end
    end

    NorthInputQueue #(
        .N                              (N),
        .DATA_WIDTH                     (DATA_WIDTH),
        .MEM_FILE                       (COLS)
    ) north_queue (
        .clk_i                          (clk_i),
        .rstn_i                         (rstn_i),
        .start_i                        (start_matrix_mult_i),
        .top_edge_passthrough_valid_i   (top_edge_passthrough_valid),
        .write_enable_i                 (north_write_enable_i),
        .write_data_i                   (north_write_data_i),
        .write_reset_i                  (north_write_reset_i),
        .weight_out_north               (weight_in_north),
        .last_o                         (last_col),
        .queue_empty_o                  (north_queue_empty_o)
    );

    WestInputQueue #(
        .N                              (N),
        .DATA_WIDTH                     (DATA_WIDTH),
        .MEM_FILE                       (ROWS)
    ) west_queue (
        .clk_i                          (clk_i),
        .rstn_i                         (rstn_i),
        .start_i                        (start_matrix_mult_i),
        .left_edge_passthrough_valid_i  (left_edge_passthrough_valid),
        .write_enable_i                 (west_write_enable_i),
        .write_data_i                   (west_write_data_i),
        .write_reset_i                  (west_write_reset_i),
        .data_out_west                  (data_in_west),
        .inputs_valid_o                 (inputs_valid),
        .last_o                         (last_row),
        .queue_empty_o                  (west_queue_empty_o)
    );

    always_comb begin
        for (int i = 0; i < N; i++)
            for (int j = 0; j < N; j++) select_accumulator[i][j] = 1'b0;
    end

    Mesh #(
        .N                              (N),
        .DATA_WIDTH                     (DATA_WIDTH)
    ) systolic_array_inst (
        .clk_i                          (clk_i),
        .rstn_i                         (rstn_i),
        .north_i                        (weight_in_north),
        .west_i                         (data_in_west),
        .inputs_valid_i                 (inputs_valid),
        .last_element_i                 (last_row[N-1]),
        .select_accumulator_i           (select_accumulator),
        .south_o                        (south_o),
        .east_o                         (east_o),
        .passthrough_valid_o            (passthrough_valid),
        .accumulator_valid_o            (accumulator_valid_o),
        .done_o                         (matrix_mult_complete_o)
    );
endmodule

// Wrapper module for North Input Queue
module NorthInputQueue #(
    parameter N = 8,
    parameter DATA_WIDTH = 32,
    parameter MEM_FILE = "weights.mem"
) (
    input logic clk_i,
    input logic rstn_i,
    input logic start_i,
    input logic [N-1:0] top_edge_passthrough_valid_i,  // From top edge PEs

    // Write interface
    input logic write_enable_i,                         // Write enable
    input logic [DATA_WIDTH-1:0] write_data_i,         // Write data
    input logic write_reset_i,                          // Reset write pointer to 0

    output logic [DATA_WIDTH-1:0] weight_out_north [0:N-1],
    output logic [N-1:0] last_o,
    output logic queue_empty_o
);
    ColumnInputQueue #(
        .N(N),
        .DATA_WIDTH(DATA_WIDTH),
        .MEM_FILE(MEM_FILE)
    ) north_queue_inst (
        .clk_i(clk_i),
        .rstn_i(rstn_i),
        .start_i(start_i),
        .passthrough_valid_i(top_edge_passthrough_valid_i),
        .write_enable_i(write_enable_i),
        .write_data_i(write_data_i),
        .write_reset_i(write_reset_i),
        .data_o(weight_out_north),
        .data_valid_o(),
        .last_o(last_o),
        .queue_empty_o(queue_empty_o)
    );
endmodule

// Wrapper module for West Input Queue
module WestInputQueue #(
    parameter N = 8,
    parameter DATA_WIDTH = 32,
    parameter MEM_FILE = "data.mem"
) (
    input logic clk_i,
    input logic rstn_i,
    input logic start_i,
    input logic [N-1:0] left_edge_passthrough_valid_i,  // From left edge PEs

    // Write interface
    input logic write_enable_i,                         // Write enable
    input logic [DATA_WIDTH-1:0] write_data_i,         // Write data
    input logic write_reset_i,                          // Reset write pointer to 0

    output logic [DATA_WIDTH-1:0] data_out_west [0:N-1],
    output logic inputs_valid_o,
    output logic [N-1:0] last_o,
    output logic queue_empty_o
);
    RowInputQueue #(
        .N(N),
        .DATA_WIDTH(DATA_WIDTH),
        .MEM_FILE(MEM_FILE)
    ) west_queue_inst (
        .clk_i(clk_i),
        .rstn_i(rstn_i),
        .start_i(start_i),
        .passthrough_valid_i(left_edge_passthrough_valid_i),
        .write_enable_i(write_enable_i),
        .write_data_i(write_data_i),
        .write_reset_i(write_reset_i),
        .data_o(data_out_west),
        .data_valid_o(inputs_valid_o),
        .last_o(last_o),
        .queue_empty_o(queue_empty_o)
    );
endmodule
