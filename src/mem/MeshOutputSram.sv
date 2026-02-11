module MeshOutputSram #(
    parameter DEPTH = 1024,
    parameter DATA_WIDTH = 32,
    parameter NUM_PORTS = 1
) (
    input logic clk_i,
    input logic rstn_i,

    input logic [NUM_PORTS-1:0]                 we_i,
    input logic [NUM_PORTS-1:0][          31:0] waddr_i,
    input logic [NUM_PORTS-1:0][DATA_WIDTH-1:0] wdata_i,

    input  logic                  read_enable_i,
    input  logic [          31:0] read_addr_i,
    output logic [DATA_WIDTH-1:0] read_data_o,
    output logic                  read_valid_o
);

  logic [DATA_WIDTH-1:0] mem[0:DEPTH-1];

  always_ff @(posedge clk_i) begin
    if (rstn_i) begin
      for (int p = 0; p < NUM_PORTS; p++) begin
        if (we_i[p] && waddr_i[p] < DEPTH) begin
          mem[waddr_i[p]] <= wdata_i[p];
        end
      end
    end
  end

  always_ff @(posedge clk_i or negedge rstn_i) begin
    if (!rstn_i) begin
      read_data_o  <= '0;
      read_valid_o <= 0;
    end else begin
      read_valid_o <= 0;
      if (read_enable_i && read_addr_i < DEPTH) begin
        read_data_o  <= mem[read_addr_i];
        read_valid_o <= 1;
      end
    end
  end

  initial begin
    for (int i = 0; i < DEPTH; i++) mem[i] = 0;
  end

endmodule
