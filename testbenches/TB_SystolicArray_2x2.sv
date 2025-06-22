`timescale 1ns / 100ps

module TB_SystolicArray_2x2;

    localparam N = 2;                   // Array size (2x2 for original test compatibility)
    localparam DATA_WIDTH = 32;
    localparam CLK_PERIOD = 10;

    // Test tracking variables
    integer test_pass_count = 0;
    integer test_fail_count = 0;
    integer total_tests = 0;

    reg clk;
    reg rstn;

    // SystolicArray interface signals
    reg [DATA_WIDTH-1:0] weight_in_north [0:N-1];
    reg [DATA_WIDTH-1:0] data_in_west [0:N-1];
    reg inputs_valid;
    reg select_accumulator [0:N-1][0:N-1];

    wire [DATA_WIDTH-1:0] weight_out_south [0:N-1];
    wire [DATA_WIDTH-1:0] data_out_east [0:N-1];
    wire passthrough_valid [0:N-1][0:N-1];
    wire accumulator_valid [0:N-1][0:N-1];

    // Matrix storage for 2x2 operations
    reg [DATA_WIDTH-1:0] matrix_a [0:1][0:1];
    reg [DATA_WIDTH-1:0] matrix_b [0:1][0:1];
    reg [DATA_WIDTH-1:0] expected_result [0:1][0:1];

    // FP32 test values (IEEE 754 format)
    localparam real TEST_DATA_1 = 2.0;      // 0x40000000
    localparam real TEST_DATA_2 = 3.0;      // 0x40400000
    localparam real TEST_DATA_3 = 4.0;      // 0x40800000
    localparam real TEST_DATA_4 = 5.0;      // 0x40A00000
    localparam real TEST_WEIGHT_1 = 0.5;    // 0x3F000000
    localparam real TEST_WEIGHT_2 = 1.5;    // 0x3FC00000
    localparam real TEST_WEIGHT_3 = 2.5;    // 0x40200000
    localparam real TEST_WEIGHT_4 = 3.5;    // 0x40600000

    // Convert real to hex for display
    localparam [31:0] HEX_DATA_1 = 32'h40000000;    // 2.0
    localparam [31:0] HEX_DATA_2 = 32'h40400000;    // 3.0
    localparam [31:0] HEX_DATA_3 = 32'h40800000;    // 4.0
    localparam [31:0] HEX_DATA_4 = 32'h40A00000;    // 5.0
    localparam [31:0] HEX_WEIGHT_1 = 32'h3F000000;  // 0.5
    localparam [31:0] HEX_WEIGHT_2 = 32'h3FC00000;  // 1.5
    localparam [31:0] HEX_WEIGHT_3 = 32'h40200000;  // 2.5
    localparam [31:0] HEX_WEIGHT_4 = 32'h40600000;  // 3.5

    // Expected results (IEEE 754 format)
    localparam [31:0] HEX_RESULT_1_0 = 32'h3F800000; // 1.0 (2.0 * 0.5)
    localparam [31:0] HEX_RESULT_3_0 = 32'h40400000; // 3.0 (2.0 * 1.5)
    localparam [31:0] HEX_RESULT_10_0 = 32'h41200000; // 10.0 (4.0 * 2.5)
    localparam [31:0] HEX_RESULT_17_5 = 32'h418C0000; // 17.5 (5.0 * 3.5)

    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end

    // DUT Instantiation
    SystolicArray #(
        .N(N),
        .DATA_WIDTH(DATA_WIDTH)
    ) dut (
        .clk_i(clk),
        .rstn_i(rstn),
        .weight_in_north(weight_in_north),
        .data_in_west(data_in_west),
        .inputs_valid(inputs_valid),
        .select_accumulator(select_accumulator),
        .weight_out_south(weight_out_south),
        .data_out_east(data_out_east),
        .passthrough_valid(passthrough_valid),
        .accumulator_valid(accumulator_valid)
    );

    task initialize_signals();
        integer i, j;
        begin
            rstn = 0;
            inputs_valid = 0;

            // Initialize weight and data inputs
            for (i = 0; i < N; i = i + 1) begin
                weight_in_north[i] = 32'h0;
                data_in_west[i] = 32'h0;
            end

            // Initialize select_accumulator for all PEs
            for (i = 0; i < N; i = i + 1) begin
                for (j = 0; j < N; j = j + 1) begin
                    select_accumulator[i][j] = 0;
                end
            end
        end
    endtask

    task apply_reset();
        begin
            $display("Applying reset sequence...");
            rstn = 0;
            repeat(2) @(posedge clk);  // Wait 2 clock cycles
            rstn = 1;
            repeat(2) @(posedge clk);  // Wait 2 more clock cycles
            $display("Reset sequence completed.");
        end
    endtask

    // task wait_for_pe_idle(input integer row, input integer col);
    //     begin
    //         // Access the PE state through the DUT hierarchy
    //         case ({row, col})
    //             {0, 0}: begin
    //                 while (dut.gen_row[0].gen_col[0].pe_inst.current_state != dut.gen_row[0].gen_col[0].pe_inst.IDLE) @(posedge clk);
    //             end
    //             {0, 1}: begin
    //                 while (dut.gen_row[0].gen_col[1].pe_inst.current_state != dut.gen_row[0].gen_col[1].pe_inst.IDLE) @(posedge clk);
    //             end
    //             {1, 0}: begin
    //                 while (dut.gen_row[1].gen_col[0].pe_inst.current_state != dut.gen_row[1].gen_col[0].pe_inst.IDLE) @(posedge clk);
    //             end
    //             {1, 1}: begin
    //                 while (dut.gen_row[1].gen_col[1].pe_inst.current_state != dut.gen_row[1].gen_col[1].pe_inst.IDLE) @(posedge clk);
    //             end
    //             default: $display("ERROR: Invalid PE coordinates [%0d][%0d]", row, col);
    //         endcase
    //     end
    // endtask

    task wait_for_pe_idle(input integer row, input integer col);
        begin
            $display("Waiting for PE[%0d][%0d] to reach IDLE state...", row, col);

            // Use if-else structure instead of problematic case statement
            if (row == 0 && col == 0) begin
                while (dut.gen_row[0].gen_col[0].pe_inst.current_state != dut.gen_row[0].gen_col[0].pe_inst.IDLE) @(posedge clk);
            end else if (row == 0 && col == 1) begin
                while (dut.gen_row[0].gen_col[1].pe_inst.current_state != dut.gen_row[0].gen_col[1].pe_inst.IDLE) @(posedge clk);
            end else if (row == 1 && col == 0) begin
                while (dut.gen_row[1].gen_col[0].pe_inst.current_state != dut.gen_row[1].gen_col[0].pe_inst.IDLE) @(posedge clk);
            end else if (row == 1 && col == 1) begin
                while (dut.gen_row[1].gen_col[1].pe_inst.current_state != dut.gen_row[1].gen_col[1].pe_inst.IDLE) @(posedge clk);
            end else begin
                $display("ERROR: Invalid PE coordinates [%0d][%0d]", row, col);
            end

            $display("PE[%0d][%0d] reached IDLE state", row, col);
        end
    endtask

    task verify_accumulator(
        input integer row,
        input integer col,
        input string pe_name,
        input [DATA_WIDTH-1:0] expected_value,
        input string test_name
    );
        reg [DATA_WIDTH-1:0] actual_value;
        reg valid_flag;
        begin
            total_tests = total_tests + 1;
            $display("Verifying %s accumulator for %s...", pe_name, test_name);

            // Ensure PE is in IDLE state before attempting to read accumulator
            wait_for_pe_idle(row, col);

            // Set select_accumulator for the specific PE
            select_accumulator[row][col] = 1;
            @(posedge clk);

            // Wait for valid pulse
            while (!accumulator_valid[row][col]) begin
                @(posedge clk);
            end

            // Read the accumulator value from data output
            if (col == N-1) begin
                // Rightmost column - read from data_out_east
                actual_value = data_out_east[row];
            end else begin
                // Interior PE - read from eastern connection
                actual_value = dut.data_connections[row][col+1];
            end

            valid_flag = accumulator_valid[row][col];

            select_accumulator[row][col] = 0;
            @(posedge clk);

            // Verify the result
            if (valid_flag && (actual_value == expected_value)) begin
                $display("PASS: %s %s - Expected: 0x%08x, Actual: 0x%08x", pe_name, test_name, expected_value, actual_value);
                test_pass_count = test_pass_count + 1;
            end else begin
                $display("FAIL: %s %s - Expected: 0x%08x, Actual: 0x%08x, Valid: %b", pe_name, test_name, expected_value, actual_value, valid_flag);
                test_fail_count = test_fail_count + 1;
            end
        end
    endtask

    // Verify individual PE passthrough
    task verify_pe_passthrough(
        input integer row,
        input integer col,
        input string pe_name,
        input [DATA_WIDTH-1:0] expected_weight_input,
        input [DATA_WIDTH-1:0] expected_data_input,
        input [DATA_WIDTH-1:0] expected_weight_output,
        input [DATA_WIDTH-1:0] expected_data_output,
        input string test_name
    );
        reg [DATA_WIDTH-1:0] actual_weight_out, actual_data_out;
        begin
            total_tests = total_tests + 2; // Weight and data verification

            // Get outputs from the PE
            if (row == N-1) begin
                // Bottom row - weight output goes to external
                actual_weight_out = weight_out_south[col];
            end else begin
                // Interior PE - weight output goes to southern connection
                actual_weight_out = dut.weight_connections[row+1][col];
            end

            if (col == N-1) begin
                // Rightmost column - data output goes to external
                actual_data_out = data_out_east[row];
            end else begin
                // Interior PE - data output goes to eastern connection
                actual_data_out = dut.data_connections[row][col+1];
            end

            // Verify weight passthrough (north -> south)
            if (actual_weight_out == expected_weight_output) begin
                $display("PASS: %s %s - Weight passthrough (N->S): Input=0x%08x, Output=0x%08x", pe_name, test_name, expected_weight_input, actual_weight_out);
                test_pass_count = test_pass_count + 1;
            end else begin
                $display("FAIL: %s %s - Weight passthrough (N->S): Expected=0x%08x, Actual=0x%08x", pe_name, test_name, expected_weight_output, actual_weight_out);
                test_fail_count = test_fail_count + 1;
            end

            // Verify data passthrough (west -> east)
            if (actual_data_out == expected_data_output) begin
                $display("PASS: %s %s - Data passthrough (W->E): Input=0x%08x, Output=0x%08x", pe_name, test_name, expected_data_input, actual_data_out);
                test_pass_count = test_pass_count + 1;
            end else begin
                $display("FAIL: %s %s - Data passthrough (W->E): Expected=0x%08x, Actual=0x%08x", pe_name, test_name, expected_data_output, actual_data_out);
                test_fail_count = test_fail_count + 1;
            end
        end
    endtask

    // Wait for each PE to complete its operation before verifying passthrough
    task verify_all_passthrough_sequential(input string test_name);
        begin
            $display("--- Verifying Sequential Passthrough for All PEs (2x2 Array) ---");

            // PE[0][0]: Verify immediately after PE0 completes
            verify_pe_passthrough(0, 0, "PE[0][0]", weight_in_north[0], data_in_west[0], weight_in_north[0], data_in_west[0], test_name);

            // PE[0][1]: Wait for PE1 to complete its MAC operation, then verify passthrough
            $display("Waiting for PE[0][1] to complete MAC operation...");
            wait_for_pe_idle(0, 1);
            @(posedge clk);
            verify_pe_passthrough(0, 1, "PE[0][1]", weight_in_north[1], dut.data_connections[0][1], weight_in_north[1], dut.data_connections[0][1], test_name);

            // PE[1][0]: Wait for PE2 to complete its MAC operation, then verify passthrough
            $display("Waiting for PE[1][0] to complete MAC operation...");
            wait_for_pe_idle(1, 0);
            @(posedge clk);
            verify_pe_passthrough(1, 0, "PE[1][0]", dut.weight_connections[1][0], data_in_west[1], dut.weight_connections[1][0], data_in_west[1], test_name);

            // PE[1][1]: Wait for PE3 to complete its MAC operation, then verify passthrough
            $display("Waiting for PE[1][1] to complete MAC operation...");
            wait_for_pe_idle(1, 1);
            @(posedge clk);
            verify_pe_passthrough(1, 1, "PE[1][1]", dut.weight_connections[1][1], dut.data_connections[1][1], dut.weight_connections[1][1], dut.data_connections[1][1], test_name);
        end
    endtask

    task execute_systolic_cycle(
        input [DATA_WIDTH-1:0] pe0_weight,
        input [DATA_WIDTH-1:0] pe0_data,
        input [DATA_WIDTH-1:0] pe1_weight,
        input [DATA_WIDTH-1:0] pe2_data,
        input string cycle_name
    );
        begin
            $display("=== %s ===", cycle_name);

            // Set up inputs for the systolic array
            weight_in_north[0] = pe0_weight;
            weight_in_north[1] = pe1_weight;
            data_in_west[0] = pe0_data;
            data_in_west[1] = pe2_data;

            // Ensure clean state
            inputs_valid = 0;
            @(posedge clk); // Setup time

            // Generate clean valid pulse
            inputs_valid = 1;
            @(posedge clk); // Hold for one clock
            inputs_valid = 0;

            // Wait for PE[0][0] to complete
            wait(passthrough_valid[0][0]);
            @(posedge clk);
            $display("PE[0][0] completed: weight_out=0x%08x, data_out=0x%08x", dut.weight_connections[1][0], dut.data_connections[0][1]);

            // Now PE[0][1] and PE[1][0] will start their operations automatically
            // Wait for PE[0][1] to complete
            wait(passthrough_valid[0][1]);
            @(posedge clk);
            $display("PE[0][1] completed: weight_out=0x%08x, data_out=0x%08x", weight_out_south[1], data_out_east[0]);

            // Wait for PE[1][0] to complete
            wait(passthrough_valid[1][0]);
            @(posedge clk);
            $display("PE[1][0] completed: weight_out=0x%08x, data_out=0x%08x", weight_out_south[0], dut.data_connections[1][1]);

            // Wait for PE[1][1] to complete
            wait(passthrough_valid[1][1]);
            @(posedge clk);
            $display("PE[1][1] completed: weight_out=0x%08x, data_out=0x%08x", weight_out_south[1], data_out_east[1]);
        end
    endtask

    // Scenario 1 - Only PE0 receives inputs, others get passthrough + zeros
    task passthrough_test();
        begin
            $display("\n=== SCENARIO 1: PASSTHROUGH TEST (2x2 Array) ===");
            $display("PE[0][0] gets independent inputs, PE[0][1], PE[1][0], PE[1][1] get passthrough + independent zeros");

            // Reset accumulators by applying reset
            apply_reset();

            // Execute systolic cycle: PE[0][0] operation: 2.0 * 0.5 = 1.0
            // PE[0][1] gets passthrough data (2.0) with weight 0.0
            // PE[1][0] gets passthrough weight (0.5) with data 0.0
            // PE[1][1] gets passthrough from both PE[0][1] and PE[1][0]
            execute_systolic_cycle(HEX_WEIGHT_1, HEX_DATA_1, 32'h0, 32'h0, "PE[0][0]: 2.0 * 0.5, Others: passthrough * 0.0");

            // Verify passthrough for all PEs after complete cycle
            verify_all_passthrough_sequential("Scenario 1 - Complete Cycle");

            // Wait for all operations to complete
            repeat(5) @(posedge clk);

            // Verify accumulator contents
            verify_accumulator(0, 0, "PE[0][0]", HEX_RESULT_1_0, "Scenario 1"); // 2.0 * 0.5 = 1.0
            verify_accumulator(0, 1, "PE[0][1]", 32'h00000000, "Scenario 1");   // 2.0 * 0.0 = 0.0
            verify_accumulator(1, 0, "PE[1][0]", 32'h00000000, "Scenario 1");   // 0.0 * 0.5 = 0.0
            verify_accumulator(1, 1, "PE[1][1]", 32'h00000000, "Scenario 1");   // 0.0 * 0.0 = 0.0

            $display("=== SCENARIO 1 COMPLETED ===\n");
        end
    endtask

    // Scenario 2 - All PEs receive independent inputs + passthrough
    task independent_plus_passthrough();
        begin
            $display("\n=== SCENARIO 2: INDEPENDENT + PASSTHROUGH TEST (2x2 Array) ===");
            $display("All PEs get non-zero independent inputs, creating actual MAC operations");

            // Reset accumulators
            apply_reset();

            // First round: All PEs get independent inputs
            execute_systolic_cycle(HEX_WEIGHT_1, HEX_DATA_1, HEX_WEIGHT_2, HEX_DATA_3, "Round 1: PE[0][0](2.0*0.5), PE[0][1](2.0*1.5), PE[1][0](4.0*0.5), PE[1][1](4.0*1.5)");

            // Verify passthrough after first round
            verify_all_passthrough_sequential("Scenario 2 Round 1");

            repeat(3) @(posedge clk);

            // Second round: New independent inputs with accumulation
            execute_systolic_cycle(HEX_WEIGHT_3, HEX_DATA_2, HEX_WEIGHT_4, HEX_DATA_4,
                                 "Round 2: PE[0][0](3.0*2.5), PE[0][1](3.0*3.5), PE[1][0](5.0*2.5), PE[1][1](5.0*3.5) - Accumulate");

            // Verify passthrough after second round
            verify_all_passthrough_sequential("Scenario 2 Round 2");

            repeat(5) @(posedge clk);

            // Verify final accumulator contents
            // PE[0][0]: (2.0 * 0.5) + (3.0 * 2.5) = 1.0 + 7.5 = 8.5 = 0x41080000
            verify_accumulator(0, 0, "PE[0][0]", 32'h41080000, "Scenario 2 Final");

            // PE[0][1]: (2.0 * 1.5) + (3.0 * 3.5) = 3.0 + 10.5 = 13.5 = 0x41580000
            verify_accumulator(0, 1, "PE[0][1]", 32'h41580000, "Scenario 2 Final");

            // PE[1][0]: (4.0 * 0.5) + (5.0 * 2.5) = 2.0 + 12.5 = 14.5 = 0x41680000
            verify_accumulator(1, 0, "PE[1][0]", 32'h41680000, "Scenario 2 Final");

            // PE[1][1]: (4.0 * 1.5) + (5.0 * 3.5) = 6.0 + 17.5 = 23.5 = 0x41BC0000
            verify_accumulator(1, 1, "PE[1][1]", 32'h41BC0000, "Scenario 2 Final");

            $display("=== SCENARIO 2 COMPLETED ===\n");
        end
    endtask

    // Scenario 3 - Dedicated passthrough verification test
    task dedicated_passthrough_test();
        begin
            $display("\n=== SCENARIO 3: DEDICATED PASSTHROUGH VERIFICATION (2x2 Array) ===");
            $display("Testing passthrough functionality with complete systolic flow");

            // Reset accumulators
            apply_reset();

            // Execute a complete systolic cycle with different values
            execute_systolic_cycle(HEX_WEIGHT_2, HEX_DATA_3, HEX_WEIGHT_4, HEX_DATA_4, "Passthrough Test: PE[0][0](4.0*1.5), PE[0][1](4.0*3.5), PE[1][0](5.0*1.5), PE[1][1](5.0*3.5)");

            // Verify passthrough for all PEs after complete operations
            verify_all_passthrough_sequential("Dedicated Passthrough Test");

            $display("=== SCENARIO 3 COMPLETED ===\n");
        end
    endtask

    // Initialize matrices for identity test
    task init_identity_test();
        begin
            $display("Initializing Identity Test Matrices:");
            // A = [[1, 2], [3, 4]]
            matrix_a[0][0] = 32'h3f800000; // a1 = 1.0
            matrix_a[0][1] = 32'h40000000; // a2 = 2.0
            matrix_a[1][0] = 32'h40400000; // a3 = 3.0
            matrix_a[1][1] = 32'h40800000; // a4 = 4.0
            // B = Identity [[1, 0], [0, 1]]
            matrix_b[0][0] = 32'h3f800000; // b1 = 1.0
            matrix_b[0][1] = 32'h00000000; // b2 = 0.0
            matrix_b[1][0] = 32'h00000000; // b3 = 0.0
            matrix_b[1][1] = 32'h3f800000; // b4 = 1.0
            // Expected result = A * I = A
            expected_result[0][0] = 32'h3f800000; // 1.0
            expected_result[0][1] = 32'h40000000; // 2.0
            expected_result[1][0] = 32'h40400000; // 3.0
            expected_result[1][1] = 32'h40800000; // 4.0
            $display("Matrix A: [[%h, %h], [%h, %h]]", matrix_a[0][0], matrix_a[0][1], matrix_a[1][0], matrix_a[1][1]);
            $display("Matrix B: [[%h, %h], [%h, %h]]", matrix_b[0][0], matrix_b[0][1], matrix_b[1][0], matrix_b[1][1]);
            $display("Expected: [[%h, %h], [%h, %h]]", expected_result[0][0], expected_result[0][1], expected_result[1][0], expected_result[1][1]);
        end
    endtask

    // Scenario 4 - 2x2 Matrix Multiplication Identity Test
    task identity_matrix_test();
        begin
            $display("\n=== SCENARIO 4: 2x2 IDENTITY MATRIX TEST ===");
            $display("Testing A * I = A using 2x2 systolic array");

            // Initialize matrices
            init_identity_test();

            // Reset accumulators
            apply_reset();

            $display("--- Time Step 1: First elements ---");
            execute_systolic_cycle(matrix_b[0][0], matrix_a[0][0], matrix_b[1][0], matrix_a[1][0], "Step 1: Weights=[b11,b21], Data=[a11,a21]");

            repeat(3) @(posedge clk);

            $display("--- Time Step 2: Second elements ---");
            execute_systolic_cycle(matrix_b[0][1], matrix_a[0][1], matrix_b[1][1], matrix_a[1][1], "Step 2: Weights=[b12,b22], Data=[a12,a22]");

            repeat(5) @(posedge clk);

            // Verify final results
            $display("--- Verifying Matrix Multiplication Results ---");
            verify_accumulator(0, 0, "PE[0][0]", expected_result[0][0], "Matrix Identity C[0][0]"); // Should be 1.0
            verify_accumulator(0, 1, "PE[0][1]", expected_result[0][1], "Matrix Identity C[0][1]"); // Should be 2.0
            verify_accumulator(1, 0, "PE[1][0]", expected_result[1][0], "Matrix Identity C[1][0]"); // Should be 3.0
            verify_accumulator(1, 1, "PE[1][1]", expected_result[1][1], "Matrix Identity C[1][1]"); // Should be 4.0

            $display("=== SCENARIO 4 COMPLETED ===\n");
        end
    endtask

    task print_test_summary();
        begin
            $display("\n" + "="*50);
            $display("TEST SUMMARY");
            $display("="*50);
            $display("Total Tests: %0d", total_tests);
            $display("Passed: %0d", test_pass_count);
            $display("Failed: %0d", test_fail_count);
            $display("Pass Rate: %.1f%%", (test_pass_count * 100.0) / total_tests);

            if (test_fail_count == 0) begin
                $display("STATUS: ALL TESTS PASSED!");
            end else begin
                $display("STATUS: %0d TEST(S) FAILED!", test_fail_count);
            end
            $display("="*50);
        end
    endtask

    // Main test stimulus
    initial begin
        $display("");
        $display("Test values:");
        $display("  Data: 2.0 (0x%08x), 3.0 (0x%08x), 4.0 (0x%08x), 5.0 (0x%08x)", HEX_DATA_1, HEX_DATA_2, HEX_DATA_3, HEX_DATA_4);
        $display("  Weights: 0.5 (0x%08x), 1.5 (0x%08x), 2.5 (0x%08x), 3.5 (0x%08x)", HEX_WEIGHT_1, HEX_WEIGHT_2, HEX_WEIGHT_3, HEX_WEIGHT_4);
        $display("");

        initialize_signals();
        apply_reset();

        // Execute test scenarios
        passthrough_test();
        repeat(10) @(posedge clk);

        independent_plus_passthrough();
        repeat(10) @(posedge clk);

        dedicated_passthrough_test();
        repeat(10) @(posedge clk);

        identity_matrix_test();
        repeat(10) @(posedge clk);

        print_test_summary();

        $finish;
    end

    // Timeout
    initial begin
        #200000; // Increased timeout for 4 PE operations
        $display("ERROR: Testbench timeout!");
        print_test_summary();
        $finish;
    end

    initial begin
        $dumpfile("TB_SystolicArray.vcd");
        $dumpvars(0, TB_SystolicArray);
    end

endmodule
