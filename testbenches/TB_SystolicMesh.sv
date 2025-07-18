`timescale 1ns / 100ps

module TB_SystolicMesh;

    // SystolicMesh parameters
    localparam TILE_SIZE = 2;
    localparam DATA_WIDTH = 32;
    localparam TILES_X = 2;
    localparam TILES_Y = 2;
    localparam CLK_PERIOD = 10;

    // Derived parameters
    localparam TOTAL_TILES = TILES_X * TILES_Y;
    localparam TILE_SRAM_SIZE = TILE_SIZE * TILE_SIZE;
    localparam UNIFIED_SRAM_SIZE = TILE_SRAM_SIZE * TOTAL_TILES;
    localparam UNIFIED_ADDR_BITS = $clog2(UNIFIED_SRAM_SIZE);

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

    // Clock and reset
    reg clk;
    reg rstn;
    reg start_matrix_mult;

    // North Queue Write interface (for weights)
    reg north_write_enable;
    reg [DATA_WIDTH-1:0] north_write_data;
    reg north_write_reset;

    // West Queue Write interface (for data)
    reg west_write_enable;
    reg [DATA_WIDTH-1:0] west_write_data;
    reg west_write_reset;

    // Queue status outputs
    wire north_queue_empty_o;
    wire west_queue_empty_o;
    wire matrix_mult_complete_o;

    // Unified SRAM read interface
    reg read_enable;
    reg [UNIFIED_ADDR_BITS-1:0] read_addr;
    wire [DATA_WIDTH-1:0] read_data;
    wire read_valid;

    // Unified SRAM status signals
    wire collection_complete;
    wire collection_active;

    // Expected results storage
    reg [DATA_WIDTH-1:0] expected_result [0:UNIFIED_SRAM_SIZE-1];

    // Test configuration
    localparam INPUT_A_FILE = "matrixA.mem";
    localparam INPUT_B_FILE = "matrixB.mem";
    localparam EXPECTED_OUTPUT_FILE = "matrixC.mem";

    // Test description
    string test_name = "SystolicMesh Unified SRAM Test";

    // Clock generation
    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end

    // DUT instantiation
    SystolicMesh #(
        .TILE_SIZE(TILE_SIZE),
        .DATA_WIDTH(DATA_WIDTH),
        .TILES_X(TILES_X),
        .TILES_Y(TILES_Y),
        .ROWS_MEM("rows.mem"),
        .COLS_MEM("cols.mem")
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

        // Unified SRAM read interface
        .read_enable_i(read_enable),
        .read_addr_i(read_addr),
        .read_data_o(read_data),
        .read_valid_o(read_valid),

        // Unified SRAM status signals
        .collection_complete_o(collection_complete),
        .collection_active_o(collection_active)
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
        abs_diff = (expected_real > actual_real) ? (expected_real - actual_real) : (actual_real - expected_real);

        // Calculate relative difference (avoid division by zero)
        if (expected_real != 0.0) begin
            rel_diff = abs_diff / ((expected_real > 0) ? expected_real : -expected_real);
        end else begin
            rel_diff = (actual_real == 0.0) ? 0.0 : 1.0;
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

    // Initialize signals
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

            $display("SystolicMesh Configuration:");
            $display("  Tile Size: %0d x %0d", TILE_SIZE, TILE_SIZE);
            $display("  Mesh Size: %0d x %0d tiles", TILES_X, TILES_Y);
            $display("  Total Tiles: %0d", TOTAL_TILES);
            $display("  Unified SRAM Size: %0d entries", UNIFIED_SRAM_SIZE);
            $display("  Data Width: %0d bits", DATA_WIDTH);
            $display("\nTolerance Configuration:");
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
            repeat(5) @(posedge clk);
            rstn = 1;
            repeat(5) @(posedge clk);
            $display("Reset sequence completed.");
        end
    endtask

    // Write data from file to north queue (weights)
    task write_file_to_north(input string filename);
        integer file_handle;
        integer scan_result;
        reg [DATA_WIDTH-1:0] temp_data;
        integer data_count;
        begin
            $display("Writing weights from file %s to North Queue...", filename);

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
            // Read and write data sequentially
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
            $display("Written %0d weight values from %s to north queue", data_count, filename);
        end
    endtask

    // Write data from file to west queue (input data)
    task write_file_to_west(input string filename);
        integer file_handle;
        integer scan_result;
        reg [DATA_WIDTH-1:0] temp_data;
        integer data_count;
        begin
            $display("Writing input data from file %s to West Queue...", filename);

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
            // Read and write data sequentially
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
            $display("Written %0d input values from %s to west queue", data_count, filename);
        end
    endtask

    // Load expected results from file
    task load_expected_results(input string filename);
        integer file_handle;
        integer scan_result;
        integer addr;
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
            addr = 0;
            // Read expected results for entire unified SRAM
            while (!$feof(file_handle) && addr < UNIFIED_SRAM_SIZE) begin
                scan_result = $fscanf(file_handle, "%h", temp_data);
                if (scan_result == 1) begin
                    expected_result[addr] = temp_data;
                    $display("Expected[%0d] = 0x%08x (%0d)", addr, temp_data, $signed(temp_data));
                    addr++;
                    data_count++;
                end
            end

            $fclose(file_handle);
            $display("Successfully loaded %0d expected values from %s", data_count, filename);
        end
    endtask

    // Wait for matrix multiplication to complete
    task wait_for_matrix_completion();
        begin
            $display("Waiting for matrix multiplication to complete...");

            // Wait for matrix multiplication to finish
            while (!matrix_mult_complete_o) begin
                @(posedge clk);
            end
            $display("Matrix multiplication completed!");
        end
    endtask

    // Wait for unified SRAM collection to complete
    task wait_for_collection_completion();
        begin
            $display("Waiting for unified SRAM collection to complete...");

            // Wait for collection to start
            while (!collection_active) begin
                @(posedge clk);
            end
            $display("Unified SRAM collection started...");

            // Wait for collection to complete
            while (!collection_complete) begin
                @(posedge clk);
            end
            $display("Unified SRAM collection completed!");
        end
    endtask

    // Verify unified SRAM results
    task verify_unified_sram_results();
        logic exact_match, tolerance_match;
        string tolerance_info;
        reg [DATA_WIDTH-1:0] actual_result;
        integer tile_id, tile_row, tile_col;
        integer local_addr, global_addr;
        begin
            $display("--- Verifying Unified SRAM Results ---");

            for (int addr = 0; addr < UNIFIED_SRAM_SIZE; addr++) begin
                total_tests++;

                // Read from unified SRAM
                read_enable = 1;
                read_addr = addr;
                @(posedge clk);

                // Wait for valid data
                while (!read_valid) begin
                    @(posedge clk);
                end

                actual_result = read_data;
                read_enable = 0;
                @(posedge clk);

                // Calculate tile information for display
                tile_id = addr / TILE_SRAM_SIZE;
                local_addr = addr % TILE_SRAM_SIZE;
                tile_row = tile_id / TILES_X;
                tile_col = tile_id % TILES_X;

                // Check for exact match first
                exact_match = (actual_result == expected_result[addr]);

                // Check tolerance if enabled and exact match failed
                if (!exact_match && ENABLE_TOLERANCE) begin
                    tolerance_match = check_tolerance(expected_result[addr], actual_result, tolerance_info);
                end else begin
                    tolerance_match = 1'b0;
                    tolerance_info = "N/A";
                end

                // Report results
                if (exact_match || tolerance_match) begin
                    if (exact_match) begin
                        $display("PASS: SRAM[%0d] Tile[%0d,%0d][%0d] - Expected: 0x%08x (%0d), Actual: 0x%08x (%0d) [EXACT MATCH]",
                                addr, tile_row, tile_col, local_addr, expected_result[addr], $signed(expected_result[addr]), actual_result, $signed(actual_result));
                    end else begin
                        $display("PASS: SRAM[%0d] Tile[%0d,%0d][%0d] - Expected: 0x%08x (%0d), Actual: 0x%08x (%0d) [TOLERANCE: %s]",
                                addr, tile_row, tile_col, local_addr, expected_result[addr], $signed(expected_result[addr]), actual_result, $signed(actual_result), tolerance_info);
                        tolerance_pass_count++;
                    end
                    test_pass_count++;
                end else begin
                    if (ENABLE_TOLERANCE) begin
                        $display("FAIL: SRAM[%0d] Tile[%0d,%0d][%0d] - Expected: 0x%08x (%0d), Actual: 0x%08x (%0d) [TOLERANCE: %s]",
                                addr, tile_row, tile_col, local_addr, expected_result[addr], $signed(expected_result[addr]), actual_result, $signed(actual_result), tolerance_info);
                    end else begin
                        $display("FAIL: SRAM[%0d] Tile[%0d,%0d][%0d] - Expected: 0x%08x (%0d), Actual: 0x%08x (%0d)",
                                addr, tile_row, tile_col, local_addr, expected_result[addr], $signed(expected_result[addr]), actual_result, $signed(actual_result));
                    end
                    test_fail_count++;
                end
            end
        end
    endtask

    // Display unified SRAM contents organized by tiles
    task display_unified_sram_contents();
        reg [DATA_WIDTH-1:0] sram_data;
        integer tile_id, tile_row, tile_col;
        integer local_addr, global_addr;
        begin
            $display("--- Unified SRAM Contents (Organized by Tiles) ---");

            for (int t_row = 0; t_row < TILES_Y; t_row++) begin
                for (int t_col = 0; t_col < TILES_X; t_col++) begin
                    tile_id = t_row * TILES_X + t_col;
                    $display("Tile[%0d,%0d] (ID=%0d):", t_row, t_col, tile_id);

                    for (int row = 0; row < TILE_SIZE; row++) begin
                        $write("  Row %0d: ", row);
                        for (int col = 0; col < TILE_SIZE; col++) begin
                            local_addr = row * TILE_SIZE + col;
                            global_addr = tile_id * TILE_SRAM_SIZE + local_addr;

                            read_enable = 1;
                            read_addr = global_addr;
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
                    $display("");
                end
            end
            $display("--- End of Unified SRAM Contents ---");
        end
    endtask

    // Execute the main mesh test
    task execute_systolic_mesh_test();
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

            $display("Starting systolic mesh matrix multiplication...");
            start_matrix_mult = 1;
            @(posedge clk);
            start_matrix_mult = 0;

            wait_for_matrix_completion();
            wait_for_collection_completion();

            display_unified_sram_contents();

            verify_unified_sram_results();

            $display("=== %s COMPLETED ===\n", test_name);
        end
    endtask

    // Print comprehensive test summary
    task print_test_summary();
        automatic real pass_rate = (total_tests > 0) ? (test_pass_count * 100.0) / total_tests : 0.0;
        automatic real tolerance_rate = (test_pass_count > 0) ? (tolerance_pass_count * 100.0) / test_pass_count : 0.0;
        begin
            $display("\n" + "="*70);
            $display("SYSTOLIC MESH WITH UNIFIED SRAM TEST SUMMARY");
            $display("="*70);
            $display("Test: %s", test_name);
            $display("Input A: %s", INPUT_A_FILE);
            $display("Input B: %s", INPUT_B_FILE);
            $display("Expected: %s", EXPECTED_OUTPUT_FILE);
            $display("-"*70);
            $display("MESH CONFIGURATION:");
            $display("  Tile Size: %0d x %0d", TILE_SIZE, TILE_SIZE);
            $display("  Mesh Size: %0d x %0d tiles", TILES_X, TILES_Y);
            $display("  Total Tiles: %0d", TOTAL_TILES);
            $display("  Unified SRAM Size: %0d entries", UNIFIED_SRAM_SIZE);
            $display("  Data Width: %0d bits", DATA_WIDTH);
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
            $display("  STATUS: %s", (test_fail_count == 0) ? "ALL TESTS PASSED!" : $sformatf("%0d TEST(S) FAILED!", test_fail_count));
            $display("="*70);
        end
    endtask

    // Main test stimulus
    initial begin
        $display("Testing SystolicMesh module with unified SRAM\n");

        initialize_signals();

        execute_systolic_mesh_test();

        repeat(10) @(posedge clk);

        print_test_summary();
        $finish;
    end

    // Timeout watchdog
    initial begin
        #50000000; // 50ms timeout
        $display("ERROR: Testbench timeout after 50ms!");
        print_test_summary();
        $finish;
    end

    // VCD dump
    initial begin
        $dumpfile("TB_SystolicMesh.vcd");
        $dumpvars(0, TB_SystolicMesh);
    end

endmodule
