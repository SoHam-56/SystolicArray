`timescale 1ns / 100ps

module TB_SystolicArray;

    localparam N = 3;
    localparam DATA_WIDTH = 32;
    localparam CLK_PERIOD = 10;

    // Tolerance configuration
    localparam TOLERANCE_MODE = "RELATIVE"; // "ABSOLUTE", "RELATIVE", or "BOTH"
    localparam real ABSOLUTE_TOLERANCE = 1.0;
    localparam real RELATIVE_TOLERANCE = 0.10;
    localparam logic ENABLE_TOLERANCE = 1'b1; // Enable/disable tolerance checking

    // Test tracking variables
    integer test_pass_count = 0;
    integer test_fail_count = 0;
    integer total_tests = 0;
    integer tolerance_pass_count = 0; // Tests that passed due to tolerance

    reg clk;
    reg rstn;
    reg start_matrix_mult;

    reg north_write_enable;
    reg [DATA_WIDTH-1:0] north_write_data;
    reg north_write_reset;
    
    reg west_write_enable;
    reg [DATA_WIDTH-1:0] west_write_data;
    reg west_write_reset;

    wire [DATA_WIDTH-1:0] south_o [0:N-1];
    wire [DATA_WIDTH-1:0] east_o [0:N-1];
    wire passthrough_valid_o [0:N-1][0:N-1];  // Updated to match module interface
    wire north_queue_empty_o;
    wire west_queue_empty_o;
    wire matrix_mult_complete_o;

    // Drain mode outputs
    wire drain_complete_o;
    wire [DATA_WIDTH-1:0] drain_data_o;
    wire drain_valid_o;

    reg [DATA_WIDTH-1:0] expected_result [0:N-1][0:N-1];
    reg [DATA_WIDTH-1:0] captured_results [0:N-1][0:N-1];

    // Test configuration
    localparam INPUT_A_FILE = "matrixA.mem";
    localparam INPUT_B_FILE = "matrixB.mem";
    localparam EXPECTED_OUTPUT_FILE = "matrixC.mem";

    // Test description
    string test_name = "Systolic Array Matrix Multiplication Test";

    // Clock generation
    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end

    // DUT instantiation
    SystolicArray #(
        .N(N),
        .DATA_WIDTH(DATA_WIDTH),
        .ROWS(INPUT_A_FILE),
        .COLS(INPUT_B_FILE)
    ) dut (
        .clk_i(clk),
        .rstn_i(rstn),
        .start_matrix_mult_i(start_matrix_mult),
        
        // North Queue Write interface
        .north_write_enable_i(north_write_enable),
        .north_write_data_i(north_write_data),
        .north_write_reset_i(north_write_reset),
        
        // West Queue Write interface
        .west_write_enable_i(west_write_enable),
        .west_write_data_i(west_write_data),
        .west_write_reset_i(west_write_reset),
        
        // Outputs
        .south_o(south_o),
        .east_o(east_o),
        .passthrough_valid_o(passthrough_valid_o),  // Updated signal name
        .north_queue_empty_o(north_queue_empty_o),
        .west_queue_empty_o(west_queue_empty_o),
        .matrix_mult_complete_o(matrix_mult_complete_o),
        
        // Drain mode outputs
        .drain_complete_o(drain_complete_o),
        .drain_data_o(drain_data_o),
        .drain_valid_o(drain_valid_o)
    );

    // Tolerance checking function
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
        expected_real = $signed(expected);
        actual_real = $signed(actual);

        // Calculate absolute difference
        abs_diff = (expected_real > actual_real) ?
                   (expected_real - actual_real) : (actual_real - expected_real);

        // Calculate relative difference (avoid division by zero)
        if (expected_real != 0.0) begin
            rel_diff = abs_diff / ((expected_real > 0) ? expected_real : -expected_real);
        end else begin
            rel_diff = (actual_real == 0.0) ? 0.0 : 1.0;
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
                                   abs_diff, ABSOLUTE_TOLERANCE, rel_diff*100.0, RELATIVE_TOLERANCE*100.0);

        return result;
    endfunction

    // Initialize all signals
    task initialize_signals();
        begin
            rstn = 0;
            start_matrix_mult = 0;
            
            north_write_enable = 0;
            north_write_data = 0;
            north_write_reset = 0;
            
            west_write_enable = 0;
            west_write_data = 0;
            west_write_reset = 0;

            // Initialize captured results
            for (int i = 0; i < N; i++) begin
                for (int j = 0; j < N; j++) begin
                    captured_results[i][j] = 0;
                end
            end

            $display("=== Systolic Array Testbench Initialization ===");
            $display("Array Size: %0dx%0d", N, N);
            $display("Data Width: %0d bits", DATA_WIDTH);
            $display("Clock Period: %0d ns", CLK_PERIOD);
            $display("Tolerance Configuration:");
            $display("  Mode: %s", TOLERANCE_MODE);
            $display("  Absolute Tolerance: %.6f", ABSOLUTE_TOLERANCE);
            $display("  Relative Tolerance: %.2f%%", RELATIVE_TOLERANCE*100.0);
            $display("  Tolerance Enabled: %s\n", ENABLE_TOLERANCE ? "YES" : "NO");
        end
    endtask

    // Apply reset sequence
    task apply_reset();
        begin
            $display("Applying reset sequence...");
            rstn = 0;
            repeat(10) @(posedge clk);
            rstn = 1;
            repeat(10) @(posedge clk);
            $display("Reset sequence completed.");
        end
    endtask

    // Write data from file to north queue
    task write_file_to_north(input string filename);
        integer file_handle;
        integer scan_result;
        reg [DATA_WIDTH-1:0] temp_data;
        integer data_count;
        begin
            $display("Writing data from file %s to North Queue...", filename);

            file_handle = $fopen(filename, "r");
            if (file_handle == 0) begin
                $display("ERROR: Could not open file: %s", filename);
                $finish;
            end

            // Reset write pointer
            north_write_reset = 1;
            @(posedge clk);
            north_write_reset = 0;
            @(posedge clk);

            data_count = 0;
            while (!$feof(file_handle)) begin
                scan_result = $fscanf(file_handle, "%h", temp_data);
                if (scan_result == 1) begin
                    north_write_enable = 1;
                    north_write_data = temp_data;
                    @(posedge clk);
                    data_count++;
                end
            end

            north_write_enable = 0;
            @(posedge clk);
            $fclose(file_handle);
            $display("Written %0d values from %s to north queue", data_count, filename);
        end
    endtask

    // Write data from file to west queue
    task write_file_to_west(input string filename);
        integer file_handle;
        integer scan_result;
        reg [DATA_WIDTH-1:0] temp_data;
        integer data_count;
        begin
            $display("Writing data from file %s to West Queue...", filename);

            file_handle = $fopen(filename, "r");
            if (file_handle == 0) begin
                $display("ERROR: Could not open file: %s", filename);
                $finish;
            end

            // Reset write pointer
            west_write_reset = 1;
            @(posedge clk);
            west_write_reset = 0;
            @(posedge clk);

            data_count = 0;
            while (!$feof(file_handle)) begin
                scan_result = $fscanf(file_handle, "%h", temp_data);
                if (scan_result == 1) begin
                    west_write_enable = 1;
                    west_write_data = temp_data;
                    @(posedge clk);
                    data_count++;
                end
            end

            west_write_enable = 0;
            @(posedge clk);
            $fclose(file_handle);
            $display("Written %0d values from %s to west queue", data_count, filename);
        end
    endtask

    // Load expected results from file
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

    // Improved drain mode result capture
    task capture_drain_results();
        integer timeout_counter;
        integer captured_count;
        reg [N-1:0] column_captured;
        begin
            $display("Capturing results via drain mode...");
            
            captured_count = 0;
            column_captured = 0;
            timeout_counter = 0;
            
            // Wait for drain mode to become active
            while (!dut.systolic_array_inst.drain_mode && timeout_counter < 1000) begin
                @(posedge clk);
                timeout_counter++;
            end
            
            if (timeout_counter >= 1000) begin
                $display("ERROR: Timeout waiting for drain mode to activate");
                return;
            end
            
            $display("Drain mode activated, capturing results...");
            
            // Capture data from each column as it becomes available
            for (int col = 0; col < N; col++) begin
                // Wait for this column to be selected
                while (dut.systolic_array_inst.drain_step_counter != col) begin
                    @(posedge clk);
                end
                
                // Wait for data to propagate to east outputs
                repeat(5) @(posedge clk);
                
                // Capture data from all rows in this column
                for (int row = 0; row < N; row++) begin
                    if (passthrough_valid_o[row][N-1]) begin
                        captured_results[row][col] = east_o[row];
                        captured_count++;
                        $display("Captured[%0d][%0d] = 0x%08x (%0d)", 
                                row, col, east_o[row], $signed(east_o[row]));
                    end
                end
                
                column_captured[col] = 1;
                $display("Column %0d captured", col);
            end
            
            $display("Drain capture complete: %0d values captured", captured_count);
        end
    endtask

    // Verify captured results against expected values
    task verify_results();
        logic exact_match, tolerance_match;
        string tolerance_info;
        begin
            $display("--- Verifying Results ---");
            
            for (int row = 0; row < N; row++) begin
                for (int col = 0; col < N; col++) begin
                    total_tests++;
                    
                    exact_match = (captured_results[row][col] == expected_result[row][col]);
                    
                    if (!exact_match && ENABLE_TOLERANCE) begin
                        tolerance_match = check_tolerance(expected_result[row][col], 
                                                        captured_results[row][col], 
                                                        tolerance_info);
                    end else begin
                        tolerance_match = 1'b0;
                        tolerance_info = "N/A";
                    end
                    
                    if (exact_match || tolerance_match) begin
                        if (exact_match) begin
                            $display("PASS: PE[%0d][%0d] - Expected: 0x%08x (%0d), Actual: 0x%08x (%0d) [EXACT]",
                                    row, col, expected_result[row][col], $signed(expected_result[row][col]),
                                    captured_results[row][col], $signed(captured_results[row][col]));
                        end else begin
                            $display("PASS: PE[%0d][%0d] - Expected: 0x%08x (%0d), Actual: 0x%08x (%0d) [TOLERANCE: %s]",
                                    row, col, expected_result[row][col], $signed(expected_result[row][col]),
                                    captured_results[row][col], $signed(captured_results[row][col]), tolerance_info);
                            tolerance_pass_count++;
                        end
                        test_pass_count++;
                    end else begin
                        $display("FAIL: PE[%0d][%0d] - Expected: 0x%08x (%0d), Actual: 0x%08x (%0d) [TOLERANCE: %s]",
                                row, col, expected_result[row][col], $signed(expected_result[row][col]),
                                captured_results[row][col], $signed(captured_results[row][col]), tolerance_info);
                        test_fail_count++;
                    end
                end
            end
        end
    endtask

    // Execute complete matrix multiplication test
    task execute_matrix_test();
        integer timeout_counter;
        begin
            $display("\n=== %s ===", test_name);
            $display("Input A file: %s", INPUT_A_FILE);
            $display("Input B file: %s", INPUT_B_FILE);
            $display("Expected output file: %s", EXPECTED_OUTPUT_FILE);

            load_expected_results(EXPECTED_OUTPUT_FILE);
            apply_reset();

            // Write data files to the input queues
            fork
                write_file_to_west(INPUT_A_FILE);
                write_file_to_north(INPUT_B_FILE);
            join

            // Wait for queues to be populated
            repeat(20) @(posedge clk);

            // Start matrix multiplication
            $display("Starting matrix multiplication...");
            start_matrix_mult = 1;
            @(posedge clk);
            start_matrix_mult = 0;

            // Wait for completion with timeout
            timeout_counter = 0;
            while (!matrix_mult_complete_o && timeout_counter < 10000) begin
                @(posedge clk);
                timeout_counter++;
            end

            if (timeout_counter >= 10000) begin
                $display("ERROR: Matrix multiplication timeout!");
                $finish;
            end

            $display("Matrix multiplication completed after %0d cycles", timeout_counter);

            // Capture results via drain mode
            capture_drain_results();

            // Verify results
            verify_results();

            $display("=== %s COMPLETED ===\n", test_name);
        end
    endtask

    // Print comprehensive test summary
    task print_test_summary();
        automatic real pass_rate = (total_tests > 0) ? (test_pass_count * 100.0) / total_tests : 0.0;
        automatic real tolerance_rate = (test_pass_count > 0) ? (tolerance_pass_count * 100.0) / test_pass_count : 0.0;
        begin
            $display("\n" + "="*70);
            $display("SYSTOLIC ARRAY TEST SUMMARY");
            $display("="*70);
            $display("Test: %s", test_name);
            $display("Array Size: %0dx%0d", N, N);
            $display("Data Width: %0d bits", DATA_WIDTH);
            $display("Input A: %s", INPUT_A_FILE);
            $display("Input B: %s", INPUT_B_FILE);
            $display("Expected: %s", EXPECTED_OUTPUT_FILE);
            $display("-"*70);
            $display("TOLERANCE CONFIGURATION:");
            $display("  Mode: %s", TOLERANCE_MODE);
            $display("  Absolute Tolerance: %.6f", ABSOLUTE_TOLERANCE);
            $display("  Relative Tolerance: %.2f%%", RELATIVE_TOLERANCE*100.0);
            $display("  Tolerance Enabled: %s", ENABLE_TOLERANCE ? "YES" : "NO");
            $display("-"*70);
            $display("TEST RESULTS:");
            $display("  Total Tests: %0d", total_tests);
            $display("  Passed: %0d", test_pass_count);
            $display("  Failed: %0d", test_fail_count);
            $display("  Pass Rate: %.1f%%", pass_rate);
            if (ENABLE_TOLERANCE && tolerance_pass_count > 0) begin
                $display("  Tolerance Passes: %0d (%.1f%% of passes)", tolerance_pass_count, tolerance_rate);
                $display("  Exact Matches: %0d", test_pass_count - tolerance_pass_count);
            end
            $display("  STATUS: %s", (test_fail_count == 0) ? "ALL TESTS PASSED!" : 
                     $sformatf("%0d TEST(S) FAILED!", test_fail_count));
            $display("="*70);
        end
    endtask

    // Main test execution
    initial begin
        $display("Starting Systolic Array Testbench...\n");
        
        initialize_signals();
        execute_matrix_test();
        
        repeat(100) @(posedge clk);
        
        print_test_summary();
        
        if (test_fail_count == 0) begin
            $display("\n✓ All tests passed successfully!");
        end else begin
            $display("\n✗ %0d test(s) failed!", test_fail_count);
        end
        
        $finish;
    end

    // Timeout watchdog
    initial begin
        #50000000; // 50ms timeout
        $display("ERROR: Testbench timeout after 50ms!");
        print_test_summary();
        $finish;
    end

    // VCD dump for waveform analysis
    initial begin
        $dumpfile("TB_SystolicArray.vcd");
        $dumpvars(0, TB_SystolicArray);
        $display("VCD file created: TB_SystolicArray.vcd");
    end

    // Optional: Monitor key signals during simulation
//    initial begin
//        $monitor("Time=%0t: matrix_complete=%b, drain_mode=%b, drain_step=%0d", 
//                 $time, matrix_mult_complete_o, 
//                 dut.systolic_array_inst.drain_mode, 
//                 dut.systolic_array_inst.drain_step_counter);
//    end

endmodule