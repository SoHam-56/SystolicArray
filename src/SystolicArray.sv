`timescale 1ns / 100ps

module SystolicArray #(
    parameter N          = 8,
    parameter DATA_WIDTH = 32,
    parameter ROWS       = "rows.mem",
    parameter COLS       = "cols.mem"
) (
    input  logic                    clk_i,
    input  logic                    rstn_i,
    input  logic                    start_matrix_mult_i,

    // North Queue Write interface
    input  logic                    north_write_enable_i,
    input  logic [DATA_WIDTH-1:0]   north_write_data_i,
    input  logic                    north_write_reset_i,

    // West Queue Write interface
    input  logic                    west_write_enable_i,
    input  logic [DATA_WIDTH-1:0]   west_write_data_i,
    input  logic                    west_write_reset_i,

    // Queue status
    output logic                    north_queue_empty_o,
    output logic                    west_queue_empty_o,
    output logic                    matrix_mult_complete_o,

    // OutputSram read interface
    input  logic                    read_enable_i,
    input  logic [$clog2(N*N)-1:0]  read_addr_i,
    output logic [DATA_WIDTH-1:0]   read_data_o,
    output logic                    read_valid_o,
    
    // OutputSram status signals
    output logic                    collection_complete_o,
    output logic                    collection_active_o
);

    // Internal signals for systolic array outputs
    logic [DATA_WIDTH-1:0] south_o  [0:N-1];
    logic [DATA_WIDTH-1:0] east_o   [0:N-1];
    logic                  accumulator_valid_o [0:N-1][0:N-1];
    logic [DATA_WIDTH-1:0] weight_in_north  [0:N-1];
    logic [DATA_WIDTH-1:0] data_in_west     [0:N-1];
    logic inputs_valid;
    logic passthrough_valid   [0:N-1][0:N-1];
    logic select_accumulator  [0:N-1][0:N-1];
    logic [N-1:0] drain_o;

    // Edge passthrough_valid
    logic [N-1:0] top_edge_passthrough_valid;
    logic [N-1:0] left_edge_passthrough_valid;
    logic [N-1:0] last_row, last_col;

    logic matrix_mult_done_reg;
    always_ff @(posedge clk_i or negedge rstn_i) begin
        if (!rstn_i)
            matrix_mult_done_reg <= 1'b0;
        else if (start_matrix_mult_i)
            matrix_mult_done_reg <= 1'b0;
        else if (matrix_mult_complete_o)
            matrix_mult_done_reg <= 1'b1;
    end

    // Shift-register "wave" for column selection
    logic [N-1:0] col_shift;
    logic         wave_active;

    // Detect rising edge of matrix_mult_complete_o
    logic matrix_mult_done_ff;
    always_ff @(posedge clk_i or negedge rstn_i) begin
        if (!rstn_i)
            matrix_mult_done_ff <= 1'b0;
        else
            matrix_mult_done_ff <= matrix_mult_complete_o;
    end
    wire start_wave = matrix_mult_complete_o & ~matrix_mult_done_ff;

    // Drive col_shift and wave_active
    always_ff @(posedge clk_i or negedge rstn_i) begin
        if (!rstn_i) begin
            col_shift   <= '0;
            wave_active <= 1'b0;
        end else begin
            if (start_wave) begin
                col_shift   <= {1'b1, {(N-1){1'b0}}}; // load a '1' into MSB
                wave_active <= 1'b1;
            end else if (wave_active) begin
                col_shift <= col_shift >> 1;
                if (col_shift == '0) wave_active <= 1'b0; // stop after shift register empties
            end
        end
    end

    // Broadcast col_shift to select_accumulator
    always_ff @(posedge clk_i or negedge rstn_i) begin
        if (!rstn_i) foreach (select_accumulator[i,j]) select_accumulator[i][j] <= 1'b0;
        else foreach (select_accumulator[i,j]) select_accumulator[i][j] <= col_shift[j];
    end

    // Tie passthrough edges
    always_comb begin
        for (int i = 0; i < N; i++) begin
            top_edge_passthrough_valid[i]  = passthrough_valid[0][i];
            left_edge_passthrough_valid[i] = passthrough_valid[i][0];
        end
    end

    NorthInputQueue #(
        .N          (N),
        .DATA_WIDTH (DATA_WIDTH),
        .MEM_FILE   (COLS)
    ) north_queue (
        .clk_i                        (clk_i),
        .rstn_i                       (rstn_i),
        
        .start_i                      (start_matrix_mult_i),
        .top_edge_passthrough_valid_i(top_edge_passthrough_valid),
        
        .write_enable_i               (north_write_enable_i),
        .write_data_i                 (north_write_data_i),
        .write_reset_i                (north_write_reset_i),
        
        .weight_out_north             (weight_in_north),
        
        .last_o                       (last_col),
        .queue_empty_o                (north_queue_empty_o)
    );

    WestInputQueue #(
        .N          (N),
        .DATA_WIDTH (DATA_WIDTH),
        .MEM_FILE   (ROWS)
    ) west_queue (
        .clk_i                         (clk_i),
        .rstn_i                        (rstn_i),
        
        .start_i                       (start_matrix_mult_i),
        .left_edge_passthrough_valid_i (left_edge_passthrough_valid),
        
        .write_enable_i                (west_write_enable_i),
        .write_data_i                  (west_write_data_i),
        .write_reset_i                 (west_write_reset_i),
        
        .data_out_west                 (data_in_west),
        .inputs_valid_o                (inputs_valid),
        
        .last_o                        (last_row),
        .queue_empty_o                 (west_queue_empty_o)
    );

    Mesh #(
        .N          (N),
        .DATA_WIDTH (DATA_WIDTH)
    ) systolic_array_inst (
        .clk_i                 (clk_i),
        .rstn_i                (rstn_i),
        
        .north_i               (weight_in_north),
        .west_i                (data_in_west),
        
        .inputs_valid_i        (inputs_valid),      
        .last_element_i        (last_row[N-1]),
        .select_accumulator_i  (select_accumulator),
        
        .south_o               (south_o),
        .east_o                (east_o),
        
        .passthrough_valid_o   (passthrough_valid),
        .done_o                (matrix_mult_complete_o),
        .drain_o               (drain_o)
    );

    OutputSram #(
        .N                      (N),
        .DATA_WIDTH             (DATA_WIDTH),
        .SRAM_DEPTH             (N * N)
    ) output_sram_inst (
        .clk_i                  (clk_i),
        .rstn_i                 (rstn_i),
        
        .data_i                 (east_o),
        .drain_i                (drain_o),
        .matrix_mult_complete_i (matrix_mult_complete_o),
        
        .read_enable_i          (read_enable_i),
        .read_addr_i            (read_addr_i),
        .read_data_o            (read_data_o),
        .read_valid_o           (read_valid_o),
        
        .collection_complete_o  (collection_complete_o),
        .collection_active_o    (collection_active_o)
    );

endmodule

module NorthInputQueue #(
    parameter N = 8,
    parameter DATA_WIDTH = 32,
    parameter MEM_FILE = "weights.mem"
) (
    input logic clk_i,
    input logic rstn_i,
    input logic start_i,
    input logic [N-1:0] top_edge_passthrough_valid_i,
    input logic write_enable_i,
    input logic [DATA_WIDTH-1:0] write_data_i,
    input logic write_reset_i,
    output logic [DATA_WIDTH-1:0] weight_out_north [0:N-1],
    output logic [N-1:0] last_o,
    output logic queue_empty_o
);
    ColumnInputQueue #(
        .N                              (N),
        .DATA_WIDTH                     (DATA_WIDTH),
        .MEM_FILE                       (MEM_FILE)
    ) north_queue_inst (
        .clk_i                          (clk_i),
        .rstn_i                         (rstn_i),
        
        .start_i                        (start_i),
        .passthrough_valid_i            (top_edge_passthrough_valid_i),
        
        .write_enable_i                 (write_enable_i),
        .write_data_i                   (write_data_i),
        .write_reset_i                  (write_reset_i),
        
        .data_o                         (weight_out_north),
        .data_valid_o                   (),
        
        .last_o                         (last_o),
        .queue_empty_o                  (queue_empty_o)
    );
endmodule

module WestInputQueue #(
    parameter N = 8,
    parameter DATA_WIDTH = 32,
    parameter MEM_FILE = "data.mem"
) (
    input logic clk_i,
    input logic rstn_i,
    input logic start_i,
    input logic [N-1:0] left_edge_passthrough_valid_i,
    input logic write_enable_i,
    input logic [DATA_WIDTH-1:0] write_data_i,
    input logic write_reset_i,
    output logic [DATA_WIDTH-1:0] data_out_west [0:N-1],
    output logic inputs_valid_o,
    output logic [N-1:0] last_o,
    output logic queue_empty_o
);
    RowInputQueue #(
        .N                              (N),
        .DATA_WIDTH                     (DATA_WIDTH),
        .MEM_FILE                       (MEM_FILE)
    ) west_queue_inst (
        .clk_i                          (clk_i),
        .rstn_i                         (rstn_i),
        
        .start_i                        (start_i),
        .passthrough_valid_i            (left_edge_passthrough_valid_i),
        
        .write_enable_i                 (write_enable_i),
        .write_data_i                   (write_data_i),
        .write_reset_i                  (write_reset_i),
        
        .data_o                         (data_out_west),
        .data_valid_o                   (inputs_valid_o),
        
        .last_o                         (last_o),
        .queue_empty_o                  (queue_empty_o)
    );
endmodule