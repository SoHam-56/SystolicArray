`timescale 1ns / 100ps

module SystolicArrayWithQueues #(
    parameter N = 8,
    parameter DATA_WIDTH = 32,
    parameter WEIGHT = "weights.mem",
    parameter DATA = "data.mem"
) (
    input logic clk_i,
    input logic rstn_i,
    input logic start_matrix_mult_i,

    // Outputs from systolic array
    output logic [DATA_WIDTH-1:0] south_o [0:N-1],
    output logic [DATA_WIDTH-1:0] east_o [0:N-1],
    output logic passthrough_valid_o [0:N-1][0:N-1],
    output logic accumulator_valid_o [0:N-1][0:N-1],

    // Queue status
    output logic north_queue_empty_o,
    output logic west_queue_empty_o,
    output logic matrix_mult_complete_o
);

    // Internal signals
    logic [DATA_WIDTH-1:0] weight_in_north [0:N-1];
    logic [DATA_WIDTH-1:0] data_in_west [0:N-1];
    logic inputs_valid;
    logic select_accumulator [0:N-1][0:N-1];

    // Extract edge passthrough_valid signals
    logic [N-1:0] top_edge_passthrough_valid;
    logic [N-1:0] left_edge_passthrough_valid;

    // Extract top edge (row 0) passthrough_valid
    always_comb begin
        for (int i = 0; i < N; i++) begin
            top_edge_passthrough_valid[i] = passthrough_valid_o[0][i];
        end
    end

    // Extract left edge (column 0) passthrough_valid
    always_comb begin
        for (int i = 0; i < N; i++) begin
            left_edge_passthrough_valid[i] = passthrough_valid_o[i][0];
        end
    end

    // North Input Queue (Weights)
    NorthInputQueue #(
        .N(N),
        .DATA_WIDTH(DATA_WIDTH),
        .MEM_FILE(WEIGHT)
    ) north_queue (
        .clk_i(clk_i),
        .rstn_i(rstn_i),
        .start_i(start_matrix_mult_i),
        .top_edge_passthrough_valid_i(top_edge_passthrough_valid),
        .weight_out_north(weight_in_north),
        .inputs_valid_o(inputs_valid),
        .queue_empty_o(north_queue_empty_o)
    );

    // West Input Queue (Data)
    WestInputQueue #(
        .N(N),
        .DATA_WIDTH(DATA_WIDTH),
        .MEM_FILE(DATA)
    ) west_queue (
        .clk_i(clk_i),
        .rstn_i(rstn_i),
        .start_i(start_matrix_mult_i),
        .left_edge_passthrough_valid_i(left_edge_passthrough_valid),
        .data_out_west(data_in_west),
        .queue_empty_o(west_queue_empty_o)
    );

    // Set all accumulator selects to 0 for now (you can control this as needed)
    always_comb begin
        for (int i = 0; i < N; i++) begin
            for (int j = 0; j < N; j++) begin
                select_accumulator[i][j] = 1'b0;
            end
        end
    end

    // Systolic Array instance
    SystolicArray #(
        .N(N),
        .DATA_WIDTH(DATA_WIDTH)
    ) systolic_array_inst (
        .clk_i(clk_i),
        .rstn_i(rstn_i),
        .north_i(weight_in_north),
        .west_i(data_in_west),
        .inputs_valid_i(inputs_valid),
        .select_accumulator_i(select_accumulator),
        .south_o(south_o),
        .east_o(east_o),
        .passthrough_valid_o(passthrough_valid_o),
        .accumulator_valid_o(accumulator_valid_o)
    );

    // Matrix multiplication complete when both queues are empty
    assign matrix_mult_complete_o = north_queue_empty_o && west_queue_empty_o;

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
    output logic [DATA_WIDTH-1:0] weight_out_north [0:N-1],
    output logic inputs_valid_o,
    output logic queue_empty_o
);

    RowInputQueue #(
        .N(N),
        .DATA_WIDTH(DATA_WIDTH),
        .MEM_FILE(MEM_FILE)
    ) north_queue_inst (
        .clk_i(clk_i),
        .rstn_i(rstn_i),
        .start_i(start_i),
        .passthrough_valid_i(top_edge_passthrough_valid_i),
        .data_o(weight_out_north),
        .data_valid_o(inputs_valid_o),
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
    output logic [DATA_WIDTH-1:0] data_out_west [0:N-1],
    output logic queue_empty_o
);

    ColumnInputQueue #(
        .N(N),
        .DATA_WIDTH(DATA_WIDTH),
        .MEM_FILE(MEM_FILE)
    ) west_queue_inst (
        .clk_i(clk_i),
        .rstn_i(rstn_i),
        .start_i(start_i),
        .passthrough_valid_i(left_edge_passthrough_valid_i),
        .data_o(data_out_west),
        .data_valid_o(),  // Not used for west queue
        .queue_empty_o(queue_empty_o)
    );

endmodule
