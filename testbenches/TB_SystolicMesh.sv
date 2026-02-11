`timescale 1ns / 100ps

module TB_SystolicMesh;

  localparam DATA_WIDTH = 32;
  localparam CLK_PERIOD = 10;

  localparam MATRIX_SIZE = 32;
  localparam TILE_SIZE = 8;
  localparam SRAM_SIZE = MATRIX_SIZE * MATRIX_SIZE;

  localparam int NUM_TEST_SETS = 3;

  // Tolerance Settings
  localparam TOLERANCE_MODE = "RELATIVE";  // "ABSOLUTE", "RELATIVE", or "BOTH"
  localparam real ABS_TOL = 0.001;  // Max absolute difference allowed
  localparam real REL_TOL = 0.01;  // Max relative difference allowed (1%)
  localparam logic ENABLE_TOL = 1'b1;  // 1 = Use tolerance, 0 = Exact match only

  reg clk, rstn, start_mult;

  reg n_we, w_we, n_rst, w_rst;
  reg [DATA_WIDTH-1:0] n_data, w_data;
  wire n_empty, w_empty, complete;

  reg r_en;
  reg [31:0] r_addr;
  wire [DATA_WIDTH-1:0] r_data;
  wire r_valid;

  reg [DATA_WIDTH-1:0] expected_mem[0:SRAM_SIZE-1];

  int total_sets_run = 0;
  int sets_passed = 0;
  int sets_failed = 0;
  int total_elements = 0;
  int tol_pass_elements = 0;  // Elements passed via tolerance (not exact)

  SystolicMesh #(
      .MATRIX_SIZE(MATRIX_SIZE),
      .TILE_SIZE  (TILE_SIZE),
      .DATA_WIDTH (DATA_WIDTH)
  ) dut (
      .clk_i(clk),
      .rstn_i(rstn),
      .start_matrix_mult_i(start_mult),

      .north_write_enable_i(n_we),
      .north_write_data_i  (n_data),
      .north_write_reset_i (n_rst),

      .west_write_enable_i(w_we),
      .west_write_data_i  (w_data),
      .west_write_reset_i (w_rst),

      .north_queue_empty_o(n_empty),
      .west_queue_empty_o(w_empty),
      .matrix_mult_complete_o(complete),
      .collection_complete_o(),
      .collection_active_o(),

      .read_enable_i(r_en),
      .read_addr_i  (r_addr),
      .read_data_o  (r_data),
      .read_valid_o (r_valid)
  );

  initial begin
    clk = 0;
    forever #(CLK_PERIOD / 2) clk = ~clk;
  end

  function automatic logic check_tolerance(
      input [DATA_WIDTH-1:0] expected, input [DATA_WIDTH-1:0] actual, output string tolerance_info);
    real expected_real, actual_real;
    real abs_diff, rel_diff;
    logic abs_ok, rel_ok, result;

    // Cast hex to signed real (assuming signed integers or fixed point)
    // Modify $signed() if your data is floating point IEEE-754
    expected_real = $signed(expected);
    actual_real = $signed(actual);

    // Absolute Difference
    abs_diff = (expected_real > actual_real) ? 
               (expected_real - actual_real) : (actual_real - expected_real);

    // Relative Difference (handle divide-by-zero)
    if (expected_real != 0.0) begin
      rel_diff = abs_diff / ((expected_real > 0) ? expected_real : -expected_real);
    end else begin
      rel_diff = (actual_real == 0.0) ? 0.0 : 1.0;
    end

    abs_ok = (abs_diff <= ABS_TOL);
    rel_ok = (rel_diff <= REL_TOL);

    case (TOLERANCE_MODE)
      "ABSOLUTE": result = abs_ok;
      "RELATIVE": result = rel_ok;
      "BOTH":     result = abs_ok && rel_ok;
      default:    result = abs_ok;
    endcase

    tolerance_info = $sformatf(
        "Abs=%.4f (Limit %.4f), Rel=%.4f%% (Limit %.2f%%)",
        abs_diff,
        ABS_TOL,
        rel_diff * 100.0,
        REL_TOL * 100.0
    );
    return result;
  endfunction

  task apply_reset();
    begin
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
    end
  endtask

  task load_west_queue(input string filename);
    integer fh, res, cnt;
    reg [DATA_WIDTH-1:0] tmp;
    begin
      fh = $fopen(filename, "r");
      if (!fh) begin
        $display("  [Error] Could not open WEST file: %s", filename);
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
    end
  endtask

  task load_north_queue(input string filename);
    integer fh, res, cnt;
    reg [DATA_WIDTH-1:0] tmp;
    begin
      fh = $fopen(filename, "r");
      if (!fh) begin
        $display("  [Error] Could not open NORTH file: %s", filename);
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
    end
  endtask

  task verify_results(input string filename, output int err_count);
    integer fh, i, res;
    reg [DATA_WIDTH-1:0] exp_val, actual_val;
    logic exact_match, tol_match;
    string tol_info;
    begin
      $display("  [Verify] Checking against %s...", filename);
      fh = $fopen(filename, "r");
      if (!fh) begin
        $display("  [Error] Could not open EXPECTED file: %s", filename);
        $finish;
      end

      i = 0;
      while (!$feof(
          fh
      ) && i < SRAM_SIZE) begin
        res = $fscanf(fh, "%h", exp_val);
        if (res == 1) begin
          expected_mem[i] = exp_val;
          i++;
        end
      end
      $fclose(fh);

      err_count = 0;

      for (i = 0; i < SRAM_SIZE; i++) begin
        r_en   = 1;
        r_addr = i;
        @(posedge clk);
        while (!r_valid) @(posedge clk);

        actual_val = r_data;
        r_en = 0;  // Stop reading

        total_elements++;

        // 1. Check Exact Match
        exact_match = (actual_val == expected_mem[i]);

        // 2. Check Tolerance (if exact match fails)
        if (!exact_match && ENABLE_TOL) begin
          tol_match = check_tolerance(expected_mem[i], actual_val, tol_info);
        end else begin
          tol_match = 0;
          tol_info  = "N/A";
        end

        // 3. Verdict
        if (exact_match) begin
          // Pass (Exact) - silent unless debug needed
        end else if (tol_match) begin
          // Pass (Tolerance)
          $display("    [PASS-TOL] Addr %0d: Exp=0x%h, Act=0x%h | %s", i, expected_mem[i],
                   actual_val, tol_info);
          tol_pass_elements++;
        end else begin
          // Fail
          $display("    [FAIL]     Addr %0d: Exp=0x%h, Act=0x%h", i, expected_mem[i], actual_val);
          if (ENABLE_TOL) $display("               %s", tol_info);
          err_count++;
        end
      end

      if (err_count == 0) $display("  [Result] Set Passed.");
      else $display("  [Result] Set FAILED with %0d mismatches.", err_count);
    end
  endtask

  task execute_test_set(input int set_id);
    string f_a, f_b, f_c;
    int set_errors;
    begin
      // Determine filenames
      if (NUM_TEST_SETS == 1) begin
        f_a = "matrixA.mem";
        f_b = "matrixB.mem";
        f_c = "matrixC.mem";
      end else begin
        f_a = $sformatf("matrixA_%0d.mem", set_id);
        f_b = $sformatf("matrixB_%0d.mem", set_id);
        f_c = $sformatf("matrixC_%0d.mem", set_id);
      end

      $display("\n=========================================");
      $display("STARTING TEST SET %0d", set_id);
      $display("=========================================");
      $display("  Inputs: %s, %s", f_a, f_b);

      apply_reset();

      fork
        load_west_queue(f_a);
        load_north_queue(f_b);
      join

      repeat (10) @(posedge clk);

      $display("  [Action] Starting Matrix Mult...");
      start_mult = 1;
      @(posedge clk);
      start_mult = 0;

      // Timeout Protection
      fork
        begin
          wait (complete);
        end
        begin
          repeat (500000) @(posedge clk);
          if (!complete) begin
            $display("  [FATAL] Timeout waiting for completion signal!");
            $finish;
          end
        end
      join_any
      disable fork;

      $display("  [Action] Processing Complete. Verifying...");

      verify_results(f_c, set_errors);

      total_sets_run++;
      if (set_errors == 0) sets_passed++;
      else sets_failed++;

      repeat (20) @(posedge clk);
    end
  endtask

  initial begin
    $dumpfile("TB_SystolicMesh.vcd");
    $dumpvars(0, TB_SystolicMesh);

    $display("----------------------------------------------");
    $display(" SYSTOLIC MESH VERIFICATION (TOLERANCE MODE)  ");
    $display("----------------------------------------------");
    $display(" Sets to Run:    %0d", NUM_TEST_SETS);
    $display(" Tolerance Mode: %s", TOLERANCE_MODE);
    if (ENABLE_TOL) begin
      $display(" Abs Tolerance:  %.4f", ABS_TOL);
      $display(" Rel Tolerance:  %.2f%%", REL_TOL * 100.0);
    end else begin
      $display(" Tolerance:      DISABLED (Exact Match Only)");
    end
    $display("----------------------------------------------");

    for (int i = 0; i < NUM_TEST_SETS; i++) begin
      execute_test_set(i);
    end

    // Final Report
    $display("\n##############################################");
    $display(" GLOBAL SUMMARY ");
    $display("##############################################");
    $display(" Total Sets:     %0d", total_sets_run);
    $display(" Passed Sets:    %0d", sets_passed);
    $display(" Failed Sets:    %0d", sets_failed);
    $display(" Total Elements: %0d", total_elements);
    if (ENABLE_TOL) begin
      $display(" Tol Passed Els: %0d (%.1f%%)", tol_pass_elements,
               (tol_pass_elements * 100.0) / (total_elements > 0 ? total_elements : 1));
    end
    $display("##############################################");

    if (sets_failed == 0) $display(" RESULT: SUCCESS");
    else $display(" RESULT: FAILURE");

    $finish;
  end

endmodule
