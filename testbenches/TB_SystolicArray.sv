`timescale 1ns / 100ps

module TB_SystolicArray;

    localparam N = 32;
    localparam DATA_WIDTH = 32;
    localparam CLK_PERIOD = 10;
    localparam SRAM_DEPTH = N * N;

    // Tolerance configuration
    localparam TOLERANCE_MODE = "RELATIVE";     // "ABSOLUTE", "RELATIVE", or "BOTH"
    localparam real ABSOLUTE_TOLERANCE = 1.0;
    localparam real RELATIVE_TOLERANCE = 0.10;
    localparam logic ENABLE_TOLERANCE = 1'b1;   // Enable/disable tolerance checking

    // Test tracking variables
    integer test_pass_count = 0;
    integer test_fail_count = 0;
    integer total_tests = 0;
    integer tolerance_pass_count = 0;           // Tests that passed due to tolerance

    reg clk;
    reg rstn;
    reg start_matrix_mult;

    reg north_write_enable;
    reg [DATA_WIDTH-1:0] north_write_data;
    reg north_write_reset;
    
    reg west_write_enable;
    reg [DATA_WIDTH-1:0] west_write_data;
    reg west_write_reset;

    wire north_queue_empty_o;
    wire west_queue_empty_o;
    wire matrix_mult_complete_o;

    // OutputSram interface signals
    reg read_enable;
    reg [$clog2(SRAM_DEPTH)-1:0] read_addr;
    wire [DATA_WIDTH-1:0] read_data;
    wire read_valid;
    wire collection_complete;
    wire collection_active;

    reg [DATA_WIDTH-1:0] expected_result [0:N-1][0:N-1];

    // Test configuration
    localparam INPUT_A_FILE = "matrixA.mem";
    localparam INPUT_B_FILE = "matrixB.mem";
    localparam EXPECTED_OUTPUT_FILE = "matrixC.mem";

    // Test description
    string test_name = "OutputSram Matrix Test";

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
        
        // North Queue Write interface
        .north_write_enable_i(north_write_enable),
        .north_write_data_i(north_write_data),
        .north_write_reset_i(north_write_reset),
        
        // West Queue Write interface
        .west_write_enable_i(west_write_enable),
        .west_write_data_i(west_write_data),
        .west_write_reset_i(west_write_reset),
        
        // Queue status
        .north_queue_empty_o(north_queue_empty_o),
        .west_queue_empty_o(west_queue_empty_o),
        .matrix_mult_complete_o(matrix_mult_complete_o),
        
        // OutputSram read interface
        .read_enable_i(read_enable),
        .read_addr_i(read_addr),
        .read_data_o(read_data),
        .read_valid_o(read_valid),
        
        // OutputSram status signals
        .collection_complete_o(collection_complete),
        .collection_active_o(collection_active)
    );

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
        // Assuming signed integer representation
        expected_real = $signed(expected);
        actual_real = $signed(actual);

        // Calculate absolute difference
        abs_diff = (expected_real > actual_real) ? (expected_real - actual_real) : (actual_real - expected_real);

        // Calculate relative difference (avoid division by zero)
        if (expected_real != 0.0) begin
            rel_diff = abs_diff / ((expected_real > 0) ? expected_real : -expected_real);
        end else begin
            rel_diff = (actual_real == 0.0) ? 0.0 : 1.0; // If expected is 0, only pass if actual is also 0
        end

        abs_within_tolerance = (abs_diff <= ABSOLUTE_TOLERANCE);
        rel_within_tolerance = (rel_diff <= RELATIVE_TOLERANCE);

        case (TOLERANCE_MODE)
            "ABSOLUTE": result = abs_within_tolerance;
            "RELATIVE": result = rel_within_tolerance;
            "BOTH": result = abs_within_tolerance && rel_within_tolerance;
            default: result = abs_within_tolerance;
        endcase

        tolerance_info = $sformatf("AbsDiff=%.3f(%.3f), RelDiff=%.3f%%(%.1f%%)", abs_diff, ABSOLUTE_TOLERANCE, rel_diff*100.0, RELATIVE_TOLERANCE*100.0);

        return result;
    endfunction

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

            read_enable = 0;
            read_addr = 0;

            $display("Tolerance Configuration:");
            $display("  Mode: %s", TOLERANCE_MODE);
            $display("  Absolute Tolerance: %.6f", ABSOLUTE_TOLERANCE);
            $display("  Relative Tolerance: %.2f%%", RELATIVE_TOLERANCE*100.0);
            $display("  Tolerance Enabled: %s\n", ENABLE_TOLERANCE ? "YES" : "NO");
        end
    endtask

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
            // Read and write data sequentially as it appears in the file
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
            // Read and write data sequentially as it appears in the file
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

    task wait_for_output_sram_collection();
        begin
            $display("Waiting for OutputSram to complete data collection...");
            
            // Wait for collection to start
            while (!collection_active) begin
                @(posedge clk);
            end
            $display("OutputSram collection started...");
            
            // Wait for collection to complete
            while (!collection_complete) begin
                @(posedge clk);
            end
            $display("OutputSram collection completed!");
        end
    endtask

    task verify_output_sram_results();
        logic exact_match, tolerance_match;
        string tolerance_info;
        reg [DATA_WIDTH-1:0] actual_result;
        integer sram_addr;
        begin
            $display("--- Verifying OutputSram Results ---");
            
            for (int i = 0; i < N; i++) begin
                for (int j = 0; j < N; j++) begin
                    total_tests++;
                    
                    // Calculate row-major address
                    sram_addr = i * N + j;
                    
                    // Read from OutputSram
                    read_enable = 1;
                    read_addr = sram_addr;
                    @(posedge clk);
                    
                    // Wait for valid data
                    while (!read_valid) begin
                        @(posedge clk);
                    end
                    
                    actual_result = read_data;
                    read_enable = 0;
                    @(posedge clk);
                    
                    // Check for exact match first
                    exact_match = (actual_result == expected_result[i][j]);
                    
                    // Check tolerance if enabled and exact match failed
                    if (!exact_match && ENABLE_TOLERANCE) begin
                        tolerance_match = check_tolerance(expected_result[i][j], actual_result, tolerance_info);
                    end else begin
                        tolerance_match = 1'b0;
                        tolerance_info = "N/A";
                    end
                    
                    // Report results
                    if (exact_match || tolerance_match) begin
                        if (exact_match) begin
                            $display("PASS: Result[%0d][%0d] (SRAM[%0d]) - Expected: 0x%08x (%0d), Actual: 0x%08x (%0d) [EXACT MATCH]", i, j, sram_addr, expected_result[i][j], $signed(expected_result[i][j]), actual_result, $signed(actual_result));
                        end else begin
                            $display("PASS: Result[%0d][%0d] (SRAM[%0d]) - Expected: 0x%08x (%0d), Actual: 0x%08x (%0d) [TOLERANCE: %s]", i, j, sram_addr, expected_result[i][j], $signed(expected_result[i][j]), actual_result, $signed(actual_result), tolerance_info);
                            tolerance_pass_count++;
                        end
                        test_pass_count++;
                    end else begin
                        if (ENABLE_TOLERANCE) begin
                            $display("FAIL: Result[%0d][%0d] (SRAM[%0d]) - Expected: 0x%08x (%0d), Actual: 0x%08x (%0d) [TOLERANCE: %s]", i, j, sram_addr, expected_result[i][j], $signed(expected_result[i][j]), actual_result, $signed(actual_result), tolerance_info);
                        end else begin
                            $display("FAIL: Result[%0d][%0d] (SRAM[%0d]) - Expected: 0x%08x (%0d), Actual: 0x%08x (%0d)", i, j, sram_addr, expected_result[i][j], $signed(expected_result[i][j]), actual_result, $signed(actual_result));
                        end
                        test_fail_count++;
                    end
                end
            end
        end
    endtask

    task display_output_sram_contents();
        reg [DATA_WIDTH-1:0] sram_data;
        integer sram_addr;
        begin
            $display("--- OutputSram Contents (Row-Major Order) ---");
            
            for (int i = 0; i < N; i++) begin
                $write("Row %0d: ", i);
                for (int j = 0; j < N; j++) begin
                    sram_addr = i * N + j;
                    
                    read_enable = 1;
                    read_addr = sram_addr;
                    @(posedge clk);
                    
                    while (!read_valid) begin
                        @(posedge clk);
                    end
                    
                    sram_data = read_data;
                    read_enable = 0;
                    @(posedge clk);
                    
                    $write("0x%08x ", sram_data);
                end
                $write("\n");
            end
            $display("--- End of OutputSram Contents ---");
        end
    endtask

    task execute_output_sram_matrix_test();
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

            repeat(10) @(posedge clk);

            $display("Starting matrix multiplication...");
            start_matrix_mult = 1;
            @(posedge clk);
            start_matrix_mult = 0;

            wait_for_output_sram_collection();

            display_output_sram_contents();

            verify_output_sram_results();

            $display("=== %s COMPLETED ===\n", test_name);
        end
    endtask

    task print_test_summary();
        automatic real pass_rate = (total_tests > 0) ? (test_pass_count * 100.0) / total_tests : 0.0;
        automatic real tolerance_rate = (test_pass_count > 0) ? (tolerance_pass_count * 100.0) / test_pass_count : 0.0;
        begin
            $display("\n" + "="*60);
            $display("SYSTOLIC ARRAY WITH OUTPUT SRAM TEST SUMMARY");
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
        $display("Testing SystolicArray module with integrated OutputSram\n");

        initialize_signals();
        
        execute_output_sram_matrix_test();
        
        repeat(10) @(posedge clk);

        print_test_summary();
        $finish;
    end

    initial begin
        #10000000;
        $display("ERROR: Testbench timeout after 10ms!");
        print_test_summary();
        $finish;
    end

    initial begin
        $dumpfile("TB_SystolicArray.vcd");
        $dumpvars(0, TB_SystolicArray);
    end

endmodule