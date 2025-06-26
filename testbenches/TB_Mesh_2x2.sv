`timescale 1ns / 100ps

module TB_Mesh_2x2;

    localparam N = 2;
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

    // Matrix storage
    reg [DATA_WIDTH-1:0] matrix_a [0:N-1][0:N-1];
    reg [DATA_WIDTH-1:0] matrix_b [0:N-1][0:N-1];
    reg [DATA_WIDTH-1:0] expected_result [0:N-1][0:N-1];

    // FP32 constant values (following 3x3 pattern)
    typedef struct packed {
        logic [31:0] val_0_0;  // 0.0
        logic [31:0] val_1_0;  // 1.0
        logic [31:0] val_2_0;  // 2.0
        logic [31:0] val_3_0;  // 3.0
        logic [31:0] val_4_0;  // 4.0
        logic [31:0] val_5_0;  // 5.0
        logic [31:0] val_0_5;  // 0.5
        logic [31:0] val_1_5;  // 1.5
        logic [31:0] val_2_5;  // 2.5
        logic [31:0] val_3_5;  // 3.5
    } fp32_constants_t;

    localparam fp32_constants_t FP32_CONST = '{
        val_0_0: 32'h00000000,  // 0.0
        val_1_0: 32'h3F800000,  // 1.0
        val_2_0: 32'h40000000,  // 2.0
        val_3_0: 32'h40400000,  // 3.0
        val_4_0: 32'h40800000,  // 4.0
        val_5_0: 32'h40A00000,  // 5.0
        val_0_5: 32'h3F000000,  // 0.5
        val_1_5: 32'h3FC00000,  // 1.5
        val_2_5: 32'h40200000,  // 2.5
        val_3_5: 32'h40600000   // 3.5
    };

    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end

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

    task initialize_signals();
        begin
            rstn = 0;
            inputs_valid = 0;

            // Initialize all arrays
            for (int i = 0; i < N; i++) begin
                weight_in_north[i] = 32'h0;
                data_in_west[i] = 32'h0;
                for (int j = 0; j < N; j++) begin
                    select_accumulator[i][j] = 0;
                end
            end
        end
    endtask

    task apply_reset();
        begin
            $display("Applying reset sequence...");
            rstn = 0;
            repeat(2) @(posedge clk);
            rstn = 1;
            repeat(2) @(posedge clk);
            $display("Reset sequence completed.");
        end
    endtask

    task wait_for_pe_idle(input integer row, input integer col);
        begin
            $display("Waiting for PE[%0d][%0d] to reach IDLE state...", row, col);

            case ({row, col})
                {1'd0, 1'd0}: while (dut.gen_row[0].gen_col[0].pe_inst.current_state != dut.gen_row[0].gen_col[0].pe_inst.IDLE) @(posedge clk);
                {1'd0, 1'd1}: while (dut.gen_row[0].gen_col[1].pe_inst.current_state != dut.gen_row[0].gen_col[1].pe_inst.IDLE) @(posedge clk);
                {1'd1, 1'd0}: while (dut.gen_row[1].gen_col[0].pe_inst.current_state != dut.gen_row[1].gen_col[0].pe_inst.IDLE) @(posedge clk);
                {1'd1, 1'd1}: while (dut.gen_row[1].gen_col[1].pe_inst.current_state != dut.gen_row[1].gen_col[1].pe_inst.IDLE) @(posedge clk);
                default: $display("ERROR: Invalid PE coordinates [%0d][%0d]", row, col);
            endcase

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
            total_tests++;
            $display("Verifying %s accumulator for %s...", pe_name, test_name);

            wait_for_pe_idle(row, col);

            select_accumulator[row][col] = 1;
            @(posedge clk);

            // Wait for valid pulse
            while (!accumulator_valid[row][col]) @(posedge clk);

            // Read accumulator value
            actual_value = (col == N-1) ? data_out_east[row] : dut.data_connections[row][col+1];
            valid_flag = accumulator_valid[row][col];

            select_accumulator[row][col] = 0;
            @(posedge clk);

            // Verify and update counters
            if (valid_flag && (actual_value == expected_value)) begin
                $display("PASS: %s %s - Expected: 0x%08x, Actual: 0x%08x", pe_name, test_name, expected_value, actual_value);
                test_pass_count++;
            end else begin
                $display("FAIL: %s %s - Expected: 0x%08x, Actual: 0x%08x, Valid: %b", pe_name, test_name, expected_value, actual_value, valid_flag);
                test_fail_count++;
            end
        end
    endtask

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

    task init_identity_test();
        begin
            $display("Initializing 2x2 Identity Test Matrices:");

            // Initialize matrix A with sequential values 1-4
            for (int i = 0; i < N; i++) begin
                for (int j = 0; j < N; j++) begin
                    case (i*N + j)
                        0: matrix_a[i][j] = FP32_CONST.val_1_0;
                        1: matrix_a[i][j] = FP32_CONST.val_2_0;
                        2: matrix_a[i][j] = FP32_CONST.val_3_0;
                        3: matrix_a[i][j] = FP32_CONST.val_4_0;
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

    task init_random_matrices();
        // Pre-defined 2x2 matrices for testing
        static logic [31:0] a_values [0:3] = '{FP32_CONST.val_2_0, FP32_CONST.val_3_0,
                                               FP32_CONST.val_1_0, FP32_CONST.val_4_0};

        static logic [31:0] b_values [0:3] = '{FP32_CONST.val_0_5, FP32_CONST.val_1_5,
                                               FP32_CONST.val_2_5, FP32_CONST.val_3_5};

        // Pre-calculated expected results for A * B
        // A = [[2.0, 3.0], [1.0, 4.0]], B = [[0.5, 1.5], [2.5, 3.5]]
        // C[0][0] = 2.0*0.5 + 3.0*2.5 = 1.0 + 7.5 = 8.5 = 0x41080000
        // C[0][1] = 2.0*1.5 + 3.0*3.5 = 3.0 + 10.5 = 13.5 = 0x41580000
        // C[1][0] = 1.0*0.5 + 4.0*2.5 = 0.5 + 10.0 = 10.5 = 0x41280000
        // C[1][1] = 1.0*1.5 + 4.0*3.5 = 1.5 + 14.0 = 15.5 = 0x41780000
        static logic [31:0] expected_values [0:3] = '{32'h41080000, 32'h41580000,
                                                      32'h41280000, 32'h41780000};
        begin
            $display("Initializing 2x2 Random Test Matrices:");

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

    task print_test_summary();
        automatic real pass_rate = (total_tests > 0) ? (test_pass_count * 100.0) / total_tests : 0.0;
        begin
            $display("\n" + "="*50);
            $display("SYSTOLIC ARRAY TEST SUMMARY");
            $display("="*50);
            $display("Total Tests: %0d", total_tests);
            $display("Passed: %0d", test_pass_count);
            $display("Failed: %0d", test_fail_count);
            $display("Pass Rate: %.1f%%", pass_rate);
            $display("STATUS: %s", (test_fail_count == 0) ? "ALL TESTS PASSED!" : $sformatf("%0d TEST(S) FAILED!", test_fail_count));
            $display("="*50);
        end
    endtask

    // Main test stimulus
    initial begin
        $display("Testing 2x2 matrix multiplication with identity and random matrices\n");

        initialize_signals();
        apply_reset();

        execute_matrix_test("2x2 IDENTITY MATRIX TEST", 1'b1);
        repeat(10) @(posedge clk);

        execute_matrix_test("2x2 RANDOM MATRIX TEST", 1'b0);
        repeat(10) @(posedge clk);

        print_test_summary();
        $finish;
    end

    // Timeout
    initial begin
        #200000;
        $display("ERROR: Testbench timeout after 200us!");
        print_test_summary();
        $finish;
    end

    // VCD dump
    initial begin
        $dumpfile("TB_Mesh_2x2.vcd");
        $dumpvars(0, TB_Mesh_2x2);
    end

endmodule
