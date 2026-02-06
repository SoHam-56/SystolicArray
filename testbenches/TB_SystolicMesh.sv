`timescale 1ns / 100ps

module TB_SystolicMesh;

  localparam TILE_SIZE = 2;
  localparam DATA_WIDTH = 32;
  localparam TILES_X = 2;  // Number of Tiles in X
  localparam TILES_Y = 2;  // Number of Tiles in Y
  localparam CLK_PERIOD = 10;

  localparam MATRIX_SIZE = TILES_X * TILE_SIZE;
  localparam UNIFIED_SRAM_SIZE = MATRIX_SIZE * MATRIX_SIZE;

  reg clk, rstn, start_mult;
  reg n_we, w_we, n_rst, w_rst;
  reg [DATA_WIDTH-1:0] n_data, w_data;
  wire n_empty, w_empty, complete;

  reg r_en;
  reg [31:0] r_addr;
  wire [DATA_WIDTH-1:0] r_data;
  wire r_valid;

  reg [DATA_WIDTH-1:0] expected_mem[0:UNIFIED_SRAM_SIZE-1];

  SystolicMesh #(
      .MATRIX_SIZE(MATRIX_SIZE),
      .TILE_SIZE  (TILE_SIZE),
      .DATA_WIDTH (DATA_WIDTH)
  ) dut (
      .clk_i(clk),
      .rstn_i(rstn),
      .start_matrix_mult_i(start_mult),
      .north_write_enable_i(n_we),
      .north_write_data_i(n_data),
      .north_write_reset_i(n_rst),
      .west_write_enable_i(w_we),
      .west_write_data_i(w_data),
      .west_write_reset_i(w_rst),
      .north_queue_empty_o(n_empty),
      .west_queue_empty_o(w_empty),
      .matrix_mult_complete_o(complete),
      .read_enable_i(r_en),
      .read_addr_i(r_addr),
      .read_data_o(r_data),
      .read_valid_o(r_valid)
  );

  task apply_reset();
    begin
      $display("Applying Reset...");

      rstn = 0;
      start_mult = 0;
      n_we = 0;
      n_rst = 0;
      n_data = 0;
      w_we = 0;
      w_rst = 0;
      w_data = 0;
      r_en = 0;
      r_addr = 0;

      repeat (5) @(posedge clk);

      rstn = 1;
      repeat (5) @(posedge clk);
      $display("Reset Complete.");
    end
  endtask

  task load_west_queue(input string filename);
    integer fh, res, cnt;
    reg [DATA_WIDTH-1:0] tmp;
    begin
      $display("Loading %s to WEST Queue...", filename);
      fh = $fopen(filename, "r");
      if (!fh) begin
        $display("Error opening %s", filename);
        $finish;
      end

      w_rst = 1;
      @(posedge clk);
      w_rst = 0;
      @(posedge clk);
      cnt = 0;
      while (!$feof(
          fh
      )) begin
        res = $fscanf(fh, "%h", tmp);
        if (res == 1) begin
          w_we   = 1;
          w_data = tmp;
          @(posedge clk);
          cnt++;
        end
      end
      w_we = 0;
      @(posedge clk);
      $fclose(fh);
      $display("Loaded %0d values to West.", cnt);
    end
  endtask

  task load_north_queue(input string filename);
    integer fh, res, cnt;
    reg [DATA_WIDTH-1:0] tmp;
    begin
      $display("Loading %s to NORTH Queue...", filename);
      fh = $fopen(filename, "r");
      if (!fh) begin
        $display("Error opening %s", filename);
        $finish;
      end

      n_rst = 1;
      @(posedge clk);
      n_rst = 0;
      @(posedge clk);
      cnt = 0;
      while (!$feof(
          fh
      )) begin
        res = $fscanf(fh, "%h", tmp);
        if (res == 1) begin
          n_we   = 1;
          n_data = tmp;
          @(posedge clk);
          cnt++;
        end
      end
      n_we = 0;
      @(posedge clk);
      $fclose(fh);
      $display("Loaded %0d values to North.", cnt);
    end
  endtask

  task check_results();
    integer fh, i, err;
    reg [DATA_WIDTH-1:0] exp_val;
    begin
      $display("Checking Results...");
      fh = $fopen("matrixC.mem", "r");
      if (!fh) begin
        $display("Error opening expected output file");
        $finish;
      end

      i   = 0;
      err = 0;
      while (!$feof(
          fh
      ) && i < UNIFIED_SRAM_SIZE) begin
        void'($fscanf(fh, "%h", exp_val));
        expected_mem[i] = exp_val;
        i++;
      end
      $fclose(fh);

      for (i = 0; i < UNIFIED_SRAM_SIZE; i++) begin
        r_en   = 1;
        r_addr = i;
        @(posedge clk);
        while (!r_valid) @(posedge clk);
        r_en = 0;

        if (r_data !== expected_mem[i]) begin
          $display("FAIL: Addr %0d, Exp %h, Got %h", i, expected_mem[i], r_data);
          err++;
        end
      end

      if (err == 0) $display("ALL TESTS PASSED!");
      else $display("%0d FAILURES FOUND", err);
    end
  endtask

  initial begin
    clk = 0;
    forever #(CLK_PERIOD / 2) clk = ~clk;
  end

  initial begin
    apply_reset();

    fork
      load_west_queue("matrixA.mem");
      load_north_queue("matrixB.mem");
    join

    repeat (10) @(posedge clk);

    $display("Starting Matrix Mult...");
    start_mult = 1;
    @(posedge clk);
    start_mult = 0;

    while (!complete) @(posedge clk);
    $display("Matrix Mult Complete.");

    check_results();
    $finish;
  end

  initial begin
    $dumpfile("TB_SystolicMesh.vcd");
    $dumpvars(0, TB_SystolicMesh);
  end

endmodule
