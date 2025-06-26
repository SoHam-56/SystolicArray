`timescale 1ns / 100ps

module TB_SystolicArray;

    localparam N = 3;
    localparam DATA_WIDTH = 32;
    localparam CLK_PERIOD = 10;

    // Test tracking variables
    integer test_pass_count = 0;
    integer test_fail_count = 0;
    integer total_tests = 0;

    reg clk;
    reg rstn;
    reg start_matrix_mult;

    // DUT selection
    reg use_identity_dut;

    // DUT outputs for identity test
    wire [DATA_WIDTH-1:0] south_o_identity [0:N-1];
    wire [DATA_WIDTH-1:0] east_o_identity [0:N-1];
    wire passthrough_valid_o_identity [0:N-1][0:N-1];
    wire accumulator_valid_o_identity [0:N-1][0:N-1];
    wire north_queue_empty_o_identity;
    wire west_queue_empty_o_identity;
    wire matrix_mult_complete_o_identity;

    // DUT outputs for random test
    wire [DATA_WIDTH-1:0] south_o_random [0:N-1];
    wire [DATA_WIDTH-1:0] east_o_random [0:N-1];
    wire passthrough_valid_o_random [0:N-1][0:N-1];
    wire accumulator_valid_o_random [0:N-1][0:N-1];
    wire north_queue_empty_o_random;
    wire west_queue_empty_o_random;
    wire matrix_mult_complete_o_random;

    // Multiplexed outputs (selected based on current test)
    logic [DATA_WIDTH-1:0] south_o [0:N-1];
    logic [DATA_WIDTH-1:0] east_o [0:N-1];
    logic passthrough_valid_o [0:N-1][0:N-1];
    logic accumulator_valid_o [0:N-1][0:N-1];
    logic north_queue_empty_o;
    logic west_queue_empty_o;
    logic matrix_mult_complete_o;

    // Expected results storage
    reg [DATA_WIDTH-1:0] expected_result [0:N-1][0:N-1];
    reg [DATA_WIDTH-1:0] expected_result_identity [0:N-1][0:N-1];
    reg [DATA_WIDTH-1:0] expected_result_random [0:N-1][0:N-1];

    // Test control
    logic select_accumulator [0:N-1][0:N-1];
    string current_test_type;

    // FP32 constant values
    typedef struct packed {
        logic [31:0] val_0_0;  // 0.0
        logic [31:0] val_1_0;  // 1.0
        logic [31:0] val_2_0;  // 2.0
        logic [31:0] val_3_0;  // 3.0
        logic [31:0] val_4_0;  // 4.0
        logic [31:0] val_5_0;  // 5.0
        logic [31:0] val_6_0;  // 6.0
        logic [31:0] val_7_0;  // 7.0
        logic [31:0] val_8_0;  // 8.0
        logic [31:0] val_9_0;  // 9.0
    } fp32_constants_t;

    localparam fp32_constants_t FP32_CONST = '{
        val_0_0: 32'h00000000,  // 0.0
        val_1_0: 32'h3F800000,  // 1.0
        val_2_0: 32'h40000000,  // 2.0
        val_3_0: 32'h40400000,  // 3.0
        val_4_0: 32'h40800000,  // 4.0
        val_5_0: 32'h40A00000,  // 5.0
        val_6_0: 32'h40C00000,  // 6.0
        val_7_0: 32'h40E00000,  // 7.0
        val_8_0: 32'h41000000,  // 8.0
        val_9_0: 32'h41100000   // 9.0
    };

    // Clock generation
    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end

    // DUT instantiation for identity test
    SystolicArray #(
        .N(N),
        .DATA_WIDTH(DATA_WIDTH),
        .ROWS("identity.mem"),
        .COLS("weights.mem")
    ) dut_identity (
        .clk_i(clk),
        .rstn_i(rstn),
        .start_matrix_mult_i(start_matrix_mult & use_identity_dut),
        .south_o(south_o_identity),
        .east_o(east_o_identity),
        .passthrough_valid_o(passthrough_valid_o_identity),
        .accumulator_valid_o(accumulator_valid_o_identity),
        .north_queue_empty_o(north_queue_empty_o_identity),
        .west_queue_empty_o(west_queue_empty_o_identity),
        .matrix_mult_complete_o(matrix_mult_complete_o_identity)
    );

    // DUT instantiation for random test
    SystolicArray #(
        .N(N),
        .DATA_WIDTH(DATA_WIDTH),
        .ROWS("data.mem"),
        .COLS("weights.mem")
    ) dut_random (
        .clk_i(clk),
        .rstn_i(rstn),
        .start_matrix_mult_i(start_matrix_mult & ~use_identity_dut),
        .south_o(south_o_random),
        .east_o(east_o_random),
        .passthrough_valid_o(passthrough_valid_o_random),
        .accumulator_valid_o(accumulator_valid_o_random),
        .north_queue_empty_o(north_queue_empty_o_random),
        .west_queue_empty_o(west_queue_empty_o_random),
        .matrix_mult_complete_o(matrix_mult_complete_o_random)
    );

    // Output multiplexing based on current test
    always_comb begin
        if (use_identity_dut) begin
            for (int i = 0; i < N; i++) begin
                south_o[i] = south_o_identity[i];
                east_o[i] = east_o_identity[i];
                for (int j = 0; j < N; j++) begin
                    passthrough_valid_o[i][j] = passthrough_valid_o_identity[i][j];
                    accumulator_valid_o[i][j] = accumulator_valid_o_identity[i][j];
                end
            end
            north_queue_empty_o = north_queue_empty_o_identity;
            west_queue_empty_o = west_queue_empty_o_identity;
            matrix_mult_complete_o = matrix_mult_complete_o_identity;
        end else begin
            for (int i = 0; i < N; i++) begin
                south_o[i] = south_o_random[i];
                east_o[i] = east_o_random[i];
                for (int j = 0; j < N; j++) begin
                    passthrough_valid_o[i][j] = passthrough_valid_o_random[i][j];
                    accumulator_valid_o[i][j] = accumulator_valid_o_random[i][j];
                end
            end
            north_queue_empty_o = north_queue_empty_o_random;
            west_queue_empty_o = west_queue_empty_o_random;
            matrix_mult_complete_o = matrix_mult_complete_o_random;
        end
    end

    // Override the select_accumulator signal for both DUTs
    always_comb begin
        for (int i = 0; i < N; i++) begin
            for (int j = 0; j < N; j++) begin
                dut_identity.select_accumulator[i][j] = select_accumulator[i][j] & use_identity_dut;
                dut_random.select_accumulator[i][j] = select_accumulator[i][j] & ~use_identity_dut;
            end
        end
    end

    // Task to initialize signals
    task initialize_signals();
        begin
            rstn = 0;
            start_matrix_mult = 0;
            use_identity_dut = 1;  // Start with identity DUT
            current_test_type = "identity";

            // Initialize select_accumulator
            for (int i = 0; i < N; i++) begin
                for (int j = 0; j < N; j++) begin
                    select_accumulator[i][j] = 0;
                end
            end
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

    // Task to wait for PE to reach IDLE state
    task wait_for_pe_idle(input integer row, input integer col);
        begin
            $display("Waiting for PE[%0d][%0d] to reach IDLE state...", row, col);

            if (use_identity_dut) begin
                case ({row, col})
                    {2'd0, 2'd0}: while (dut_identity.systolic_array_inst.gen_row[0].gen_col[0].pe_inst.current_state != dut_identity.systolic_array_inst.gen_row[0].gen_col[0].pe_inst.IDLE) @(posedge clk);
                    {2'd0, 2'd1}: while (dut_identity.systolic_array_inst.gen_row[0].gen_col[1].pe_inst.current_state != dut_identity.systolic_array_inst.gen_row[0].gen_col[1].pe_inst.IDLE) @(posedge clk);
                    {2'd0, 2'd2}: while (dut_identity.systolic_array_inst.gen_row[0].gen_col[2].pe_inst.current_state != dut_identity.systolic_array_inst.gen_row[0].gen_col[2].pe_inst.IDLE) @(posedge clk);
                    {2'd1, 2'd0}: while (dut_identity.systolic_array_inst.gen_row[1].gen_col[0].pe_inst.current_state != dut_identity.systolic_array_inst.gen_row[1].gen_col[0].pe_inst.IDLE) @(posedge clk);
                    {2'd1, 2'd1}: while (dut_identity.systolic_array_inst.gen_row[1].gen_col[1].pe_inst.current_state != dut_identity.systolic_array_inst.gen_row[1].gen_col[1].pe_inst.IDLE) @(posedge clk);
                    {2'd1, 2'd2}: while (dut_identity.systolic_array_inst.gen_row[1].gen_col[2].pe_inst.current_state != dut_identity.systolic_array_inst.gen_row[1].gen_col[2].pe_inst.IDLE) @(posedge clk);
                    {2'd2, 2'd0}: while (dut_identity.systolic_array_inst.gen_row[2].gen_col[0].pe_inst.current_state != dut_identity.systolic_array_inst.gen_row[2].gen_col[0].pe_inst.IDLE) @(posedge clk);
                    {2'd2, 2'd1}: while (dut_identity.systolic_array_inst.gen_row[2].gen_col[1].pe_inst.current_state != dut_identity.systolic_array_inst.gen_row[2].gen_col[1].pe_inst.IDLE) @(posedge clk);
                    {2'd2, 2'd2}: while (dut_identity.systolic_array_inst.gen_row[2].gen_col[2].pe_inst.current_state != dut_identity.systolic_array_inst.gen_row[2].gen_col[2].pe_inst.IDLE) @(posedge clk);
                    default: $display("ERROR: Invalid PE coordinates [%0d][%0d]", row, col);
                endcase
            end else begin
                case ({row, col})
                    {2'd0, 2'd0}: while (dut_random.systolic_array_inst.gen_row[0].gen_col[0].pe_inst.current_state != dut_random.systolic_array_inst.gen_row[0].gen_col[0].pe_inst.IDLE) @(posedge clk);
                    {2'd0, 2'd1}: while (dut_random.systolic_array_inst.gen_row[0].gen_col[1].pe_inst.current_state != dut_random.systolic_array_inst.gen_row[0].gen_col[1].pe_inst.IDLE) @(posedge clk);
                    {2'd0, 2'd2}: while (dut_random.systolic_array_inst.gen_row[0].gen_col[2].pe_inst.current_state != dut_random.systolic_array_inst.gen_row[0].gen_col[2].pe_inst.IDLE) @(posedge clk);
                    {2'd1, 2'd0}: while (dut_random.systolic_array_inst.gen_row[1].gen_col[0].pe_inst.current_state != dut_random.systolic_array_inst.gen_row[1].gen_col[0].pe_inst.IDLE) @(posedge clk);
                    {2'd1, 2'd1}: while (dut_random.systolic_array_inst.gen_row[1].gen_col[1].pe_inst.current_state != dut_random.systolic_array_inst.gen_row[1].gen_col[1].pe_inst.IDLE) @(posedge clk);
                    {2'd1, 2'd2}: while (dut_random.systolic_array_inst.gen_row[1].gen_col[2].pe_inst.current_state != dut_random.systolic_array_inst.gen_row[1].gen_col[2].pe_inst.IDLE) @(posedge clk);
                    {2'd2, 2'd0}: while (dut_random.systolic_array_inst.gen_row[2].gen_col[0].pe_inst.current_state != dut_random.systolic_array_inst.gen_row[2].gen_col[0].pe_inst.IDLE) @(posedge clk);
                    {2'd2, 2'd1}: while (dut_random.systolic_array_inst.gen_row[2].gen_col[1].pe_inst.current_state != dut_random.systolic_array_inst.gen_row[2].gen_col[1].pe_inst.IDLE) @(posedge clk);
                    {2'd2, 2'd2}: while (dut_random.systolic_array_inst.gen_row[2].gen_col[2].pe_inst.current_state != dut_random.systolic_array_inst.gen_row[2].gen_col[2].pe_inst.IDLE) @(posedge clk);
                    default: $display("ERROR: Invalid PE coordinates [%0d][%0d]", row, col);
                endcase
            end

            $display("PE[%0d][%0d] reached IDLE state", row, col);
        end
    endtask

    // Task to verify accumulator (using multiplexed outputs)
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
            while (!accumulator_valid_o[row][col]) @(posedge clk);

            // Read accumulator value
            if (use_identity_dut) begin
                actual_value = (col == N-1) ? east_o_identity[row] : dut_identity.systolic_array_inst.data_connections[row][col+1];
            end else begin
                actual_value = (col == N-1) ? east_o_random[row] : dut_random.systolic_array_inst.data_connections[row][col+1];
            end
            valid_flag = accumulator_valid_o[row][col];

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

    // Task to initialize expected results
    task initialize_expected_results();
        begin
            // Identity test expected results (A * I = A, where A is sequential 1-9)
            expected_result_identity[0][0] = FP32_CONST.val_1_0;
            expected_result_identity[0][1] = FP32_CONST.val_2_0;
            expected_result_identity[0][2] = FP32_CONST.val_3_0;
            expected_result_identity[1][0] = FP32_CONST.val_4_0;
            expected_result_identity[1][1] = FP32_CONST.val_5_0;
            expected_result_identity[1][2] = FP32_CONST.val_6_0;
            expected_result_identity[2][0] = FP32_CONST.val_7_0;
            expected_result_identity[2][1] = FP32_CONST.val_8_0;
            expected_result_identity[2][2] = FP32_CONST.val_9_0;

            // Random test expected results (pre-calculated)
            expected_result_random[0][0] = 32'h41700000;  // 15.0
            expected_result_random[0][1] = 32'h41D00000;  // 26.0
            expected_result_random[0][2] = 32'h42140000;  // 37.0
            expected_result_random[1][0] = 32'h42340000;  // 45.0
            expected_result_random[1][1] = 32'h428E0000;  // 71.0
            expected_result_random[1][2] = 32'h42C20000;  // 97.0
            expected_result_random[2][0] = 32'h42960000;  // 75.0
            expected_result_random[2][1] = 32'h42E80000;  // 116.0
            expected_result_random[2][2] = 32'h431D0000;  // 157.0
        end
    endtask

    // Task to set expected results based on test type
    task set_expected_results(input string test_type);
        begin
            if (test_type == "identity") begin
                for (int i = 0; i < N; i++) begin
                    for (int j = 0; j < N; j++) begin
                        expected_result[i][j] = expected_result_identity[i][j];
                    end
                end
            end else if (test_type == "random") begin
                for (int i = 0; i < N; i++) begin
                    for (int j = 0; j < N; j++) begin
                        expected_result[i][j] = expected_result_random[i][j];
                    end
                end
            end
        end
    endtask

    // Task to execute matrix test
    task execute_matrix_test(input string test_name, input string test_type);
        begin
            $display("\n=== %s ===", test_name);

            // Set current test type and DUT selection
            current_test_type = test_type;
            use_identity_dut = (test_type == "identity");
            set_expected_results(test_type);

            // Apply reset to reinitialize the DUTs
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
                for (int j = 0; j < N; j++) verify_accumulator(i, j, $sformatf("PE[%0d][%0d]", i, j), expected_result[i][j], $sformatf("%s C[%0d][%0d]", test_name, i, j));
            end

            $display("=== %s COMPLETED ===\n", test_name);
        end
    endtask

    // Task to print test summary
    task print_test_summary();
        automatic real pass_rate = (total_tests > 0) ? (test_pass_count * 100.0) / total_tests : 0.0;
        begin
            $display("\n" + "="*50);
            $display("SYSTOLIC ARRAY WITH QUEUES TEST SUMMARY");
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
        $display("Testing SystolicArrayWithQueues module\n");

        initialize_signals();
        initialize_expected_results();
        apply_reset();

        // Run identity test
        execute_matrix_test("3x3 IDENTITY MATRIX TEST", "identity");
        repeat(10) @(posedge clk);

        // Run random test
        execute_matrix_test("3x3 RANDOM MATRIX TEST", "random");
        repeat(10) @(posedge clk);

        print_test_summary();
        $finish;
    end

    // Timeout
    initial begin
        #100000;
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
