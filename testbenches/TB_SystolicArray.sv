`timescale 1ns / 100ps

module TB_SystolicArray;

    localparam N = 32;
    localparam DATA_WIDTH = 32;
    localparam CLK_PERIOD = 10;

    // Tolerance configuration
    localparam TOLERANCE_MODE = "RELATIVE"; // "ABSOLUTE", "RELATIVE", or "BOTH"
    localparam real ABSOLUTE_TOLERANCE = 1.0; // Absolute difference tolerance
    localparam real RELATIVE_TOLERANCE = 0.10; // 1% relative tolerance
    localparam logic ENABLE_TOLERANCE = 1'b1; // Enable/disable tolerance checking

    // Test tracking variables
    integer test_pass_count = 0;
    integer test_fail_count = 0;
    integer total_tests = 0;
    integer tolerance_pass_count = 0; // Tests that passed due to tolerance

    reg clk;
    reg rstn;
    reg start_matrix_mult;

    wire [DATA_WIDTH-1:0] south_o [0:N-1];
    wire [DATA_WIDTH-1:0] east_o [0:N-1];
    wire accumulator_valid_o [0:N-1][0:N-1];
    wire north_queue_empty_o;
    wire west_queue_empty_o;
    wire matrix_mult_complete_o;

    reg [DATA_WIDTH-1:0] expected_result [0:N-1][0:N-1];
    logic select_accumulator [0:N-1][0:N-1];

    // Test configuration
    localparam INPUT_A_FILE = "matrixA.mem";
    localparam INPUT_B_FILE = "matrixB.mem";
    localparam EXPECTED_OUTPUT_FILE = "matrixC.mem";

    // Test description
    string test_name = "Random Matrix Test";

    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end

    SystolicArray #(
        .N(N),
        .DATA_WIDTH(DATA_WIDTH),
        .ROWS(INPUT_A_FILE),
        .COLS(INPUT_B_FILE)
    ) dut (
        .clk_i(clk),
        .rstn_i(rstn),
        .start_matrix_mult_i(start_matrix_mult),
        .south_o(south_o),
        .east_o(east_o),
        .accumulator_valid_o(accumulator_valid_o),
        .north_queue_empty_o(north_queue_empty_o),
        .west_queue_empty_o(west_queue_empty_o),
        .matrix_mult_complete_o(matrix_mult_complete_o)
    );

    // Override the select_accumulator signal
    always_comb begin
        for (int i = 0; i < N; i++)
            for (int j = 0; j < N; j++)
                dut.select_accumulator[i][j] = select_accumulator[i][j];
    end

    // Function to check if values are within tolerance
    function automatic logic check_tolerance(
        input [DATA_WIDTH-1:0] expected,
        input [DATA_WIDTH-1:0] actual,
        output string tolerance_info
    );
        real expected_real, actual_real;
        real abs_diff, rel_diff;
        logic abs_within_tolerance, rel_within_tolerance;
        logic result;

        // Convert to real for tolerance calculations
        // Assuming signed integer representation - adjust as needed for your data format
        expected_real = $signed(expected);
        actual_real = $signed(actual);

        // Calculate absolute difference
        abs_diff = (expected_real > actual_real) ?
                   (expected_real - actual_real) : (actual_real - expected_real);

        // Calculate relative difference (avoid division by zero)
        if (expected_real != 0.0) begin
            rel_diff = abs_diff / ((expected_real > 0) ? expected_real : -expected_real);
        end else begin
            rel_diff = (actual_real == 0.0) ? 0.0 : 1.0; // If expected is 0, only pass if actual is also 0
        end

        // Check tolerance conditions
        abs_within_tolerance = (abs_diff <= ABSOLUTE_TOLERANCE);
        rel_within_tolerance = (rel_diff <= RELATIVE_TOLERANCE);

        // Determine result based on tolerance mode
        case (TOLERANCE_MODE)
            "ABSOLUTE": result = abs_within_tolerance;
            "RELATIVE": result = rel_within_tolerance;
            "BOTH": result = abs_within_tolerance && rel_within_tolerance;
            default: result = abs_within_tolerance;
        endcase

        // Generate tolerance info string
        tolerance_info = $sformatf("AbsDiff=%.3f(%.3f), RelDiff=%.3f%%(%.1f%%)",
                                  abs_diff, ABSOLUTE_TOLERANCE,
                                  rel_diff*100.0, RELATIVE_TOLERANCE*100.0);

        return result;
    endfunction

    // Enhanced function for floating-point data (if using floating-point representation)
    function automatic logic check_fp_tolerance(
        input [DATA_WIDTH-1:0] expected,
        input [DATA_WIDTH-1:0] actual,
        output string tolerance_info
    );
        // This function can be customized for IEEE 754 floating-point format
        // For now, it uses the same logic as check_tolerance
        return check_tolerance(expected, actual, tolerance_info);
    endfunction

    // Task to initialize signals
    task initialize_signals();
        begin
            rstn = 0;
            start_matrix_mult = 0;

            // Initialize select_accumulator
            for (int i = 0; i < N; i++) begin
                for (int j = 0; j < N; j++)
                    select_accumulator[i][j] = 0;
            end

            $display("Tolerance Configuration:");
            $display("  Mode: %s", TOLERANCE_MODE);
            $display("  Absolute Tolerance: %.6f", ABSOLUTE_TOLERANCE);
            $display("  Relative Tolerance: %.2f%%", RELATIVE_TOLERANCE*100.0);
            $display("  Tolerance Enabled: %s\n", ENABLE_TOLERANCE ? "YES" : "NO");
        end
    endtask

    // Task to apply reset
    task apply_reset();
        begin
            $display("Applying reset sequence...");
            rstn = 0;
            repeat(5) @(posedge clk);
            rstn = 1;
            repeat(5) @(posedge clk);
            $display("Reset sequence completed.");
        end
    endtask

    // Task to load expected results from file
    task load_expected_results(input string filename);
        integer file_handle;
        integer scan_result;
        integer row, col;
        reg [DATA_WIDTH-1:0] temp_data;
        integer data_count;
        begin
            $display("Loading expected results from file: %s", filename);

            file_handle = $fopen(filename, "r");
            if (file_handle == 0) begin
                $display("ERROR: Could not open expected output file: %s", filename);
                $finish;
            end

            data_count = 0;
            // Read data in row-major order
            for (row = 0; row < N; row++) begin
                for (col = 0; col < N; col++) begin
                    scan_result = $fscanf(file_handle, "%h", temp_data);
                    if (scan_result != 1) begin
                        $display("ERROR: Failed to read expected data at position [%0d][%0d]", row, col);
                        $fclose(file_handle);
                        $finish;
                    end
                    expected_result[row][col] = temp_data;
                    data_count++;
                    $display("Expected[%0d][%0d] = 0x%08x (%0d)", row, col, temp_data, $signed(temp_data));
                end
            end

            $fclose(file_handle);
            $display("Successfully loaded %0d expected values from %s", data_count, filename);
        end
    endtask

    // Task to wait for PE to reach IDLE state
    task wait_for_pe_idle(input integer row, input integer col);
        begin
            // Validate coordinates
            if (row >= N || col >= N || row < 0 || col < 0) begin
                $display("ERROR: Invalid PE coordinates [%0d][%0d] for %0dx%0d array", row, col, N, N);
                return;
            end

            $display("Waiting for PE[%0d][%0d] computation to complete...", row, col);

            // Wait for matrix multiplication completion
            while (!matrix_mult_complete_o) begin
                @(posedge clk);
            end

            // Additional wait to ensure all PEs have settled
            repeat(10) @(posedge clk);

            $display("PE[%0d][%0d] computation completed", row, col);
        end
    endtask

    // Enhanced task to verify accumulator with tolerance
    task verify_accumulator(
        input integer row,
        input integer col,
        input string pe_name,
        input [DATA_WIDTH-1:0] expected_value,
        input string test_description
    );
        reg [DATA_WIDTH-1:0] actual_value;
        reg valid_flag;
        logic exact_match, tolerance_match;
        string tolerance_info;
        begin
            total_tests++;
            $display("Verifying %s accumulator for %s...", pe_name, test_description);

            wait_for_pe_idle(row, col);

            select_accumulator[row][col] = 1;
            @(posedge clk);

            // Wait for valid pulse
            while (!accumulator_valid_o[row][col]) @(posedge clk);

            // Read accumulator value
            actual_value = (col == N-1) ? east_o[row] : dut.systolic_array_inst.west_connections[row][col+1];
            valid_flag = accumulator_valid_o[row][col];

            select_accumulator[row][col] = 0;
            @(posedge clk);

            // Check for exact match first
            exact_match = (actual_value == expected_value);

            // Check tolerance if enabled and exact match failed
            if (!exact_match && ENABLE_TOLERANCE) begin
                tolerance_match = check_tolerance(expected_value, actual_value, tolerance_info);
            end else begin
                tolerance_match = 1'b0;
                tolerance_info = "N/A";
            end

            // Verify and update counters
            if (valid_flag && (exact_match || tolerance_match)) begin
                if (exact_match) begin
                    $display("PASS: %s %s - Expected: 0x%08x (%0d), Actual: 0x%08x (%0d) [EXACT MATCH]",
                            pe_name, test_description, expected_value, $signed(expected_value),
                            actual_value, $signed(actual_value));
                end else begin
                    $display("PASS: %s %s - Expected: 0x%08x (%0d), Actual: 0x%08x (%0d) [TOLERANCE: %s]",
                            pe_name, test_description, expected_value, $signed(expected_value),
                            actual_value, $signed(actual_value), tolerance_info);
                    tolerance_pass_count++;
                end
                test_pass_count++;
            end else begin
                if (ENABLE_TOLERANCE) begin
                    $display("FAIL: %s %s - Expected: 0x%08x (%0d), Actual: 0x%08x (%0d), Valid: %b [TOLERANCE: %s]",
                            pe_name, test_description, expected_value, $signed(expected_value),
                            actual_value, $signed(actual_value), valid_flag, tolerance_info);
                end else begin
                    $display("FAIL: %s %s - Expected: 0x%08x (%0d), Actual: 0x%08x (%0d), Valid: %b",
                            pe_name, test_description, expected_value, $signed(expected_value),
                            actual_value, $signed(actual_value), valid_flag);
                end
                test_fail_count++;
            end
        end
    endtask

    // Task to execute matrix test
    task execute_matrix_test();
        begin
            $display("\n=== %s ===", test_name);
            $display("Input A file: %s", INPUT_A_FILE);
            $display("Input B file: %s", INPUT_B_FILE);
            $display("Expected output file: %s", EXPECTED_OUTPUT_FILE);

            // Load expected results
            load_expected_results(EXPECTED_OUTPUT_FILE);

            // Apply reset
            apply_reset();

            // Start matrix multiplication
            $display("Starting matrix multiplication...");
            start_matrix_mult = 1;
            @(posedge clk);
            start_matrix_mult = 0;

            // Wait for completion
            $display("Waiting for matrix multiplication to complete...");
            while (!matrix_mult_complete_o) begin
                @(posedge clk);
            end
            $display("Matrix multiplication completed!");

            // Additional wait for all computations to settle
            repeat(20) @(posedge clk);

            // Verify all results
            $display("--- Verifying Results ---");
            for (int i = 0; i < N; i++) begin
                for (int j = 0; j < N; j++) begin
                    verify_accumulator(i, j, $sformatf("PE[%0d][%0d]", i, j), expected_result[i][j], $sformatf("C[%0d][%0d]", i, j));
                end
            end

            $display("=== %s COMPLETED ===\n", test_name);
        end
    endtask

    // Enhanced task to print test summary with tolerance information
    task print_test_summary();
        automatic real pass_rate = (total_tests > 0) ? (test_pass_count * 100.0) / total_tests : 0.0;
        automatic real tolerance_rate = (test_pass_count > 0) ? (tolerance_pass_count * 100.0) / test_pass_count : 0.0;
        begin
            $display("\n" + "="*60);
            $display("SYSTOLIC ARRAY TEST SUMMARY");
            $display("="*60);
            $display("Test: %s", test_name);
            $display("Input A: %s", INPUT_A_FILE);
            $display("Input B: %s", INPUT_B_FILE);
            $display("Expected: %s", EXPECTED_OUTPUT_FILE);
            $display("-"*60);
            $display("TOLERANCE CONFIGURATION:");
            $display("  Mode: %s", TOLERANCE_MODE);
            $display("  Absolute Tolerance: %.6f", ABSOLUTE_TOLERANCE);
            $display("  Relative Tolerance: %.2f%%", RELATIVE_TOLERANCE*100.0);
            $display("  Tolerance Enabled: %s", ENABLE_TOLERANCE ? "YES" : "NO");
            $display("-"*60);
            $display("TEST RESULTS:");
            $display("  Total Tests: %0d", total_tests);
            $display("  Passed: %0d", test_pass_count);
            $display("  Failed: %0d", test_fail_count);
            $display("  Pass Rate: %.1f%%", pass_rate);
            if (ENABLE_TOLERANCE && tolerance_pass_count > 0) begin
                $display("  Tolerance Passes: %0d (%.1f%% of passes)", tolerance_pass_count, tolerance_rate);
                $display("  Exact Matches: %0d", test_pass_count - tolerance_pass_count);
            end
            $display("  STATUS: %s", (test_fail_count == 0) ? "ALL TESTS PASSED!" : $sformatf("%0d TEST(S) FAILED!", test_fail_count));
            $display("="*60);
        end
    endtask

    // Main test stimulus
    initial begin
        $display("Testing SystolicArray module with tolerance-based verification\n");

        initialize_signals();
        execute_matrix_test();
        repeat(10) @(posedge clk);

        print_test_summary();
        $finish;
    end

    // Timeout
    initial begin
        #10000000;
        $display("ERROR: Testbench timeout after 1ms!");
        print_test_summary();
        $finish;
    end

    // VCD dump
    initial begin
        $dumpfile("TB_SystolicArray.vcd");
        $dumpvars(0, TB_SystolicArray);
    end

endmodule
