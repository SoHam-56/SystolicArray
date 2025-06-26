`timescale 1ns / 100ps

module TB_Mesh_5x5;

    localparam N = 5;
    localparam DATA_WIDTH = 32;
    localparam CLK_PERIOD = 10;

    // Test tracking variables
    integer test_pass_count = 0;
    integer test_fail_count = 0;
    integer total_tests = 0;

    reg clk;
    reg rstn;

    // Mesh interface signals
    reg [DATA_WIDTH-1:0] weight_in_north [0:N-1];
    reg [DATA_WIDTH-1:0] data_in_west [0:N-1];
    reg inputs_valid;
    reg select_accumulator [0:N-1][0:N-1];

    wire [DATA_WIDTH-1:0] weight_out_south [0:N-1];
    wire [DATA_WIDTH-1:0] data_out_east [0:N-1];
    wire passthrough_valid [0:N-1][0:N-1];
    wire accumulator_valid [0:N-1][0:N-1];

    // Matrix storage for 5x5 operations
    reg [DATA_WIDTH-1:0] matrix_a [0:N-1][0:N-1];
    reg [DATA_WIDTH-1:0] matrix_b [0:N-1][0:N-1];
    reg [DATA_WIDTH-1:0] expected_result [0:N-1][0:N-1];

    // FP32 constant values for 5x5
    typedef struct packed {
        logic [31:0] val_0_0;   // 0.0
        logic [31:0] val_1_0;   // 1.0
        logic [31:0] val_2_0;   // 2.0
        logic [31:0] val_3_0;   // 3.0
        logic [31:0] val_4_0;   // 4.0
        logic [31:0] val_5_0;   // 5.0
        logic [31:0] val_6_0;   // 6.0
        logic [31:0] val_7_0;   // 7.0
        logic [31:0] val_8_0;   // 8.0
        logic [31:0] val_9_0;   // 9.0
        logic [31:0] val_10_0;  // 10.0
        logic [31:0] val_11_0;  // 11.0
        logic [31:0] val_12_0;  // 12.0
        logic [31:0] val_13_0;  // 13.0
        logic [31:0] val_14_0;  // 14.0
        logic [31:0] val_15_0;  // 15.0
        logic [31:0] val_16_0;  // 16.0
        logic [31:0] val_17_0;  // 17.0
        logic [31:0] val_18_0;  // 18.0
        logic [31:0] val_19_0;  // 19.0
        logic [31:0] val_20_0;  // 20.0
        logic [31:0] val_21_0;  // 21.0
        logic [31:0] val_22_0;  // 22.0
        logic [31:0] val_23_0;  // 23.0
        logic [31:0] val_24_0;  // 24.0
        logic [31:0] val_25_0;  // 25.0
        logic [31:0] val_0_5;   // 0.5
        logic [31:0] val_1_5;   // 1.5
        logic [31:0] val_2_5;   // 2.5
        logic [31:0] val_3_5;   // 3.5
    } fp32_constants_t;

    localparam fp32_constants_t FP32_CONST = '{
        val_0_0:  32'h00000000,  // 0.0
        val_1_0:  32'h3F800000,  // 1.0
        val_2_0:  32'h40000000,  // 2.0
        val_3_0:  32'h40400000,  // 3.0
        val_4_0:  32'h40800000,  // 4.0
        val_5_0:  32'h40A00000,  // 5.0
        val_6_0:  32'h40C00000,  // 6.0
        val_7_0:  32'h40E00000,  // 7.0
        val_8_0:  32'h41000000,  // 8.0
        val_9_0:  32'h41100000,  // 9.0
        val_10_0: 32'h41200000,  // 10.0
        val_11_0: 32'h41300000,  // 11.0
        val_12_0: 32'h41400000,  // 12.0
        val_13_0: 32'h41500000,  // 13.0
        val_14_0: 32'h41600000,  // 14.0
        val_15_0: 32'h41700000,  // 15.0
        val_16_0: 32'h41800000,  // 16.0
        val_17_0: 32'h41880000,  // 17.0
        val_18_0: 32'h41900000,  // 18.0
        val_19_0: 32'h41980000,  // 19.0
        val_20_0: 32'h41A00000,  // 20.0
        val_21_0: 32'h41A80000,  // 21.0
        val_22_0: 32'h41B00000,  // 22.0
        val_23_0: 32'h41B80000,  // 23.0
        val_24_0: 32'h41C00000,  // 24.0
        val_25_0: 32'h41C80000,  // 25.0
        val_0_5:  32'h3F000000,  // 0.5
        val_1_5:  32'h3FC00000,  // 1.5
        val_2_5:  32'h40200000,  // 2.5
        val_3_5:  32'h40600000   // 3.5
    };

    // Clock generation
    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end

    // DUT instantiation - fixed port names to match 2x2 version
    Mesh #(
        .N(N),
        .DATA_WIDTH(DATA_WIDTH)
    ) dut (
        .clk_i(clk),
        .rstn_i(rstn),
        .north_i(weight_in_north),
        .west_i(data_in_west),
        .inputs_valid_i(inputs_valid),
        .select_accumulator_i(select_accumulator),
        .south_o(weight_out_south),
        .east_o(data_out_east),
        .passthrough_valid_o(passthrough_valid),
        .accumulator_valid_o(accumulator_valid)
    );

    // Initialize all signals
    task initialize_signals();
        begin
            rstn = 0;
            inputs_valid = 0;

            // Initialize weight and data inputs
            for (int i = 0; i < N; i++) begin
                weight_in_north[i] = 32'h0;
                data_in_west[i] = 32'h0;
            end

            // Initialize select_accumulator for all PEs
            for (int i = 0; i < N; i++) begin
                for (int j = 0; j < N; j++) begin
                    select_accumulator[i][j] = 0;
                end
            end
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

    // Generic function to wait for any PE to reach IDLE state
    task wait_for_pe_idle(input integer row, input integer col);
        begin
            $display("Waiting for PE[%0d][%0d] to reach IDLE state...", row, col);

            // Use a generic approach with case statement
            case ({row[2:0], col[2:0]})
                6'b000_000: while (dut.gen_row[0].gen_col[0].pe_inst.current_state != dut.gen_row[0].gen_col[0].pe_inst.IDLE) @(posedge clk);
                6'b000_001: while (dut.gen_row[0].gen_col[1].pe_inst.current_state != dut.gen_row[0].gen_col[1].pe_inst.IDLE) @(posedge clk);
                6'b000_010: while (dut.gen_row[0].gen_col[2].pe_inst.current_state != dut.gen_row[0].gen_col[2].pe_inst.IDLE) @(posedge clk);
                6'b000_011: while (dut.gen_row[0].gen_col[3].pe_inst.current_state != dut.gen_row[0].gen_col[3].pe_inst.IDLE) @(posedge clk);
                6'b000_100: while (dut.gen_row[0].gen_col[4].pe_inst.current_state != dut.gen_row[0].gen_col[4].pe_inst.IDLE) @(posedge clk);
                6'b001_000: while (dut.gen_row[1].gen_col[0].pe_inst.current_state != dut.gen_row[1].gen_col[0].pe_inst.IDLE) @(posedge clk);
                6'b001_001: while (dut.gen_row[1].gen_col[1].pe_inst.current_state != dut.gen_row[1].gen_col[1].pe_inst.IDLE) @(posedge clk);
                6'b001_010: while (dut.gen_row[1].gen_col[2].pe_inst.current_state != dut.gen_row[1].gen_col[2].pe_inst.IDLE) @(posedge clk);
                6'b001_011: while (dut.gen_row[1].gen_col[3].pe_inst.current_state != dut.gen_row[1].gen_col[3].pe_inst.IDLE) @(posedge clk);
                6'b001_100: while (dut.gen_row[1].gen_col[4].pe_inst.current_state != dut.gen_row[1].gen_col[4].pe_inst.IDLE) @(posedge clk);
                6'b010_000: while (dut.gen_row[2].gen_col[0].pe_inst.current_state != dut.gen_row[2].gen_col[0].pe_inst.IDLE) @(posedge clk);
                6'b010_001: while (dut.gen_row[2].gen_col[1].pe_inst.current_state != dut.gen_row[2].gen_col[1].pe_inst.IDLE) @(posedge clk);
                6'b010_010: while (dut.gen_row[2].gen_col[2].pe_inst.current_state != dut.gen_row[2].gen_col[2].pe_inst.IDLE) @(posedge clk);
                6'b010_011: while (dut.gen_row[2].gen_col[3].pe_inst.current_state != dut.gen_row[2].gen_col[3].pe_inst.IDLE) @(posedge clk);
                6'b010_100: while (dut.gen_row[2].gen_col[4].pe_inst.current_state != dut.gen_row[2].gen_col[4].pe_inst.IDLE) @(posedge clk);
                6'b011_000: while (dut.gen_row[3].gen_col[0].pe_inst.current_state != dut.gen_row[3].gen_col[0].pe_inst.IDLE) @(posedge clk);
                6'b011_001: while (dut.gen_row[3].gen_col[1].pe_inst.current_state != dut.gen_row[3].gen_col[1].pe_inst.IDLE) @(posedge clk);
                6'b011_010: while (dut.gen_row[3].gen_col[2].pe_inst.current_state != dut.gen_row[3].gen_col[2].pe_inst.IDLE) @(posedge clk);
                6'b011_011: while (dut.gen_row[3].gen_col[3].pe_inst.current_state != dut.gen_row[3].gen_col[3].pe_inst.IDLE) @(posedge clk);
                6'b011_100: while (dut.gen_row[3].gen_col[4].pe_inst.current_state != dut.gen_row[3].gen_col[4].pe_inst.IDLE) @(posedge clk);
                6'b100_000: while (dut.gen_row[4].gen_col[0].pe_inst.current_state != dut.gen_row[4].gen_col[0].pe_inst.IDLE) @(posedge clk);
                6'b100_001: while (dut.gen_row[4].gen_col[1].pe_inst.current_state != dut.gen_row[4].gen_col[1].pe_inst.IDLE) @(posedge clk);
                6'b100_010: while (dut.gen_row[4].gen_col[2].pe_inst.current_state != dut.gen_row[4].gen_col[2].pe_inst.IDLE) @(posedge clk);
                6'b100_011: while (dut.gen_row[4].gen_col[3].pe_inst.current_state != dut.gen_row[4].gen_col[3].pe_inst.IDLE) @(posedge clk);
                6'b100_100: while (dut.gen_row[4].gen_col[4].pe_inst.current_state != dut.gen_row[4].gen_col[4].pe_inst.IDLE) @(posedge clk);
                default: $display("ERROR: Invalid PE coordinates [%0d][%0d]", row, col);
            endcase

            $display("PE[%0d][%0d] reached IDLE state", row, col);
        end
    endtask

    // Verify accumulator value for a specific PE
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
            total_tests++;
            $display("Verifying %s accumulator for %s...", pe_name, test_name);

            // Ensure PE is ready
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
                test_pass_count++;
            end else begin
                $display("FAIL: %s %s - Expected: 0x%08x, Actual: 0x%08x, Valid: %b", pe_name, test_name, expected_value, actual_value, valid_flag);
                test_fail_count++;
            end
        end
    endtask

    // Execute systolic cycle - following the 2x2 pattern
    task execute_systolic_cycle(
        input [DATA_WIDTH-1:0] weights [0:N-1],
        input [DATA_WIDTH-1:0] data [0:N-1],
        input string cycle_name
    );
        begin
            $display("=== %s ===", cycle_name);

            // Set up inputs using for loop
            for (int i = 0; i < N; i++) begin
                weight_in_north[i] = weights[i];
                data_in_west[i] = data[i];
            end

            inputs_valid = 0;
            @(posedge clk);

            inputs_valid = 1;
            @(posedge clk);
            inputs_valid = 0;

            $display("Waiting for all PEs to complete operations...");

            // Wait for diagonal PEs to complete (they finish last)
            for (int i = 0; i < N; i++) begin
                wait(passthrough_valid[i][i]);
                @(posedge clk);
            end

            $display("All PEs completed for %s", cycle_name);
        end
    endtask

    // Initialize 5x5 identity matrix test
    task init_identity_test();
        begin
            $display("Initializing 5x5 Identity Test Matrices:");

            // Initialize matrix A with sequential values 1-25
            for (int i = 0; i < N; i++) begin
                for (int j = 0; j < N; j++) begin
                    case (i*N + j)
                        0:  matrix_a[i][j] = FP32_CONST.val_1_0;
                        1:  matrix_a[i][j] = FP32_CONST.val_2_0;
                        2:  matrix_a[i][j] = FP32_CONST.val_3_0;
                        3:  matrix_a[i][j] = FP32_CONST.val_4_0;
                        4:  matrix_a[i][j] = FP32_CONST.val_5_0;
                        5:  matrix_a[i][j] = FP32_CONST.val_6_0;
                        6:  matrix_a[i][j] = FP32_CONST.val_7_0;
                        7:  matrix_a[i][j] = FP32_CONST.val_8_0;
                        8:  matrix_a[i][j] = FP32_CONST.val_9_0;
                        9:  matrix_a[i][j] = FP32_CONST.val_10_0;
                        10: matrix_a[i][j] = FP32_CONST.val_11_0;
                        11: matrix_a[i][j] = FP32_CONST.val_12_0;
                        12: matrix_a[i][j] = FP32_CONST.val_13_0;
                        13: matrix_a[i][j] = FP32_CONST.val_14_0;
                        14: matrix_a[i][j] = FP32_CONST.val_15_0;
                        15: matrix_a[i][j] = FP32_CONST.val_16_0;
                        16: matrix_a[i][j] = FP32_CONST.val_17_0;
                        17: matrix_a[i][j] = FP32_CONST.val_18_0;
                        18: matrix_a[i][j] = FP32_CONST.val_19_0;
                        19: matrix_a[i][j] = FP32_CONST.val_20_0;
                        20: matrix_a[i][j] = FP32_CONST.val_21_0;
                        21: matrix_a[i][j] = FP32_CONST.val_22_0;
                        22: matrix_a[i][j] = FP32_CONST.val_23_0;
                        23: matrix_a[i][j] = FP32_CONST.val_24_0;
                        24: matrix_a[i][j] = FP32_CONST.val_25_0;
                    endcase
                end
            end

            // Initialize identity matrix B
            for (int i = 0; i < N; i++) begin
                for (int j = 0; j < N; j++) begin
                    matrix_b[i][j] = (i == j) ? FP32_CONST.val_1_0 : FP32_CONST.val_0_0;
                end
            end

            // Expected result = A (since A * I = A)
            for (int i = 0; i < N; i++) begin
                for (int j = 0; j < N; j++) begin
                    expected_result[i][j] = matrix_a[i][j];
                end
            end

            display_matrices("Identity Test");
        end
    endtask

    // Initialize random matrices for multiplication test
    task init_random_matrices();
        // Pre-defined 5x5 matrices for testing
        static logic [31:0] a_values [0:24] = '{
            FP32_CONST.val_2_0, FP32_CONST.val_1_0, FP32_CONST.val_3_0, FP32_CONST.val_0_0, FP32_CONST.val_4_0,
            FP32_CONST.val_1_0, FP32_CONST.val_2_0, FP32_CONST.val_0_0, FP32_CONST.val_3_0, FP32_CONST.val_1_0,
            FP32_CONST.val_0_0, FP32_CONST.val_1_0, FP32_CONST.val_2_0, FP32_CONST.val_1_0, FP32_CONST.val_3_0,
            FP32_CONST.val_3_0, FP32_CONST.val_0_0, FP32_CONST.val_1_0, FP32_CONST.val_2_0, FP32_CONST.val_0_0,
            FP32_CONST.val_1_0, FP32_CONST.val_3_0, FP32_CONST.val_0_0, FP32_CONST.val_1_0, FP32_CONST.val_2_0
        };

        static logic [31:0] b_values [0:24] = '{
            FP32_CONST.val_1_0, FP32_CONST.val_2_0, FP32_CONST.val_1_0, FP32_CONST.val_0_0, FP32_CONST.val_3_0,
            FP32_CONST.val_2_0, FP32_CONST.val_1_0, FP32_CONST.val_0_0, FP32_CONST.val_3_0, FP32_CONST.val_1_0,
            FP32_CONST.val_0_0, FP32_CONST.val_3_0, FP32_CONST.val_2_0, FP32_CONST.val_1_0, FP32_CONST.val_0_0,
            FP32_CONST.val_3_0, FP32_CONST.val_0_0, FP32_CONST.val_1_0, FP32_CONST.val_2_0, FP32_CONST.val_3_0,
            FP32_CONST.val_1_0, FP32_CONST.val_1_0, FP32_CONST.val_3_0, FP32_CONST.val_0_0, FP32_CONST.val_2_0
        };

        // Pre-calculated expected results for A * B (corrected values)
        static logic [31:0] expected_values [0:24] = '{
            // Row 0: [8, 18, 20, 6, 15]
            32'h41000000, 32'h41900000, 32'h41A00000, 32'h40C00000, 32'h41700000,
            // Row 1: [15, 5, 7, 12, 16]
            32'h41700000, 32'h40A00000, 32'h40E00000, 32'h41400000, 32'h41800000,
            // Row 2: [8, 10, 14, 7, 10]
            32'h41000000, 32'h41200000, 32'h41600000, 32'h40E00000, 32'h41200000,
            // Row 3: [9, 9, 7, 5, 15]
            32'h41100000, 32'h41100000, 32'h40E00000, 32'h40A00000, 32'h41700000,
            // Row 4: [12, 7, 8, 11, 13]
            32'h41400000, 32'h40E00000, 32'h41000000, 32'h41300000, 32'h41500000
        };


        begin
            $display("Initializing 5x5 Random Test Matrices:");

            // Initialize matrices using for loops
            for (int i = 0; i < N; i++) begin
                for (int j = 0; j < N; j++) begin
                    matrix_a[i][j] = a_values[i*N + j];
                    matrix_b[i][j] = b_values[i*N + j];
                    expected_result[i][j] = expected_values[i*N + j];
                end
            end

            display_matrices("Random Test");
        end
    endtask

    // Display matrices for debugging
    task display_matrices(input string test_type);
        begin
            $display("Matrix A (%s):", test_type);
            for (int i = 0; i < N; i++) begin
                $write("  [");
                for (int j = 0; j < N; j++) begin
                    $write("%h", matrix_a[i][j]);
                    if (j < N-1) $write(", ");
                end
                $display("]%s", (i < N-1) ? "," : "");
            end

            $display("Matrix B (%s):", test_type);
            for (int i = 0; i < N; i++) begin
                $write("  [");
                for (int j = 0; j < N; j++) begin
                    $write("%h", matrix_b[i][j]);
                    if (j < N-1) $write(", ");
                end
                $display("]%s", (i < N-1) ? "," : "");
            end

            $display("Expected Result (%s):", test_type);
            for (int i = 0; i < N; i++) begin
                $write("  [");
                for (int j = 0; j < N; j++) begin
                    $write("%h", expected_result[i][j]);
                    if (j < N-1) $write(", ");
                end
                $display("]%s", (i < N-1) ? "," : "");
            end
        end
    endtask

    // Execute matrix test following 2x2 pattern
    task execute_matrix_test(input string test_name, input bit is_identity);
        reg [DATA_WIDTH-1:0] temp_weights [0:N-1];
        reg [DATA_WIDTH-1:0] temp_data [0:N-1];
        begin
            $display("\n=== %s ===", test_name);

            // Initialize matrices based on test type
            if (is_identity) init_identity_test();
            else init_random_matrices();

            apply_reset();

            // Execute systolic cycles
            for (int step = 0; step < N; step++) begin
                $display("--- Time Step %0d ---", step + 1);

                for (int i = 0; i < N; i++) begin
                    temp_weights[i] = matrix_b[step][i];
                    temp_data[i] = matrix_a[i][step];
                end

                execute_systolic_cycle(temp_weights, temp_data, $sformatf("Step %0d", step + 1));
                repeat(5) @(posedge clk);
            end

            repeat(10) @(posedge clk);

            // Verify all results
            $display("--- Verifying Results ---");
            for (int i = 0; i < N; i++) begin
                for (int j = 0; j < N; j++) begin
                    verify_accumulator(i, j, $sformatf("PE[%0d][%0d]", i, j),
                                     expected_result[i][j], $sformatf("%s C[%0d][%0d]", test_name, i, j));
                end
            end

            $display("=== %s COMPLETED ===\n", test_name);
        end
    endtask

    // Print test summary
    task print_test_summary();
        automatic real pass_rate = (total_tests > 0) ? (test_pass_count * 100.0) / total_tests : 0.0;
        begin
            $display("\n" + "="*60);
            $display("5x5 SYSTOLIC ARRAY TEST SUMMARY");
            $display("="*60);
            $display("Total Tests: %0d", total_tests);
            $display("Passed: %0d", test_pass_count);
            $display("Failed: %0d", test_fail_count);
            $display("Pass Rate: %.1f%%", pass_rate);
            $display("STATUS: %s", (test_fail_count == 0) ? "ALL TESTS PASSED!" : $sformatf("%0d TEST(S) FAILED!", test_fail_count));
            $display("="*60);
        end
    endtask

    // Main test sequence
    initial begin
        $display("Testing 5x5 matrix multiplication with identity and random matrices\n");

        initialize_signals();
        apply_reset();

        execute_matrix_test("5x5 IDENTITY MATRIX TEST", 1'b1);
        repeat(10) @(posedge clk);

        execute_matrix_test("5x5 RANDOM MATRIX TEST", 1'b0);
        repeat(10) @(posedge clk);

        print_test_summary();
        $finish;
    end

    // Timeout watchdog
    initial begin
        #500000;
        $display("ERROR: Testbench timeout!");
        print_test_summary();
        $finish;
    end

    initial begin
        $dumpfile("TB_Mesh_5x5.vcd");
        $dumpvars(0, TB_Mesh_5x5);
    end

endmodule
