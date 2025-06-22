`timescale 1ns / 100ps

module TB_SystolicArray_8x8;

    localparam N = 8;
    localparam DATA_WIDTH = 32;
    localparam CLK_PERIOD = 10;

    integer test_pass_count = 0;
    integer test_fail_count = 0;
    integer total_tests = 0;

    reg clk;
    reg rstn;

    reg [DATA_WIDTH-1:0] weight_in_north [0:N-1];
    reg [DATA_WIDTH-1:0] data_in_west [0:N-1];
    reg inputs_valid;
    reg select_accumulator [0:N-1][0:N-1];

    wire [DATA_WIDTH-1:0] weight_out_south [0:N-1];
    wire [DATA_WIDTH-1:0] data_out_east [0:N-1];
    wire passthrough_valid [0:N-1][0:N-1];
    wire accumulator_valid [0:N-1][0:N-1];

    reg [DATA_WIDTH-1:0] matrix_a [0:N-1][0:N-1];
    reg [DATA_WIDTH-1:0] matrix_b [0:N-1][0:N-1];
    reg [DATA_WIDTH-1:0] expected_result [0:N-1][0:N-1];

    typedef struct packed {
        logic [31:0] val_0_0;
        logic [31:0] val_1_0;
        logic [31:0] val_2_0;
        logic [31:0] val_3_0;
        logic [31:0] val_4_0;
        logic [31:0] val_5_0;
        logic [31:0] val_6_0;
        logic [31:0] val_7_0;
        logic [31:0] val_8_0;
        logic [31:0] val_9_0;
        logic [31:0] val_10_0;
        logic [31:0] val_11_0;
        logic [31:0] val_12_0;
        logic [31:0] val_13_0;
        logic [31:0] val_14_0;
        logic [31:0] val_15_0;
        logic [31:0] val_16_0;
        logic [31:0] val_17_0;
        logic [31:0] val_18_0;
        logic [31:0] val_19_0;
        logic [31:0] val_20_0;
        logic [31:0] val_21_0;
        logic [31:0] val_22_0;
        logic [31:0] val_23_0;
        logic [31:0] val_24_0;
        logic [31:0] val_25_0;
        logic [31:0] val_26_0;
        logic [31:0] val_27_0;
        logic [31:0] val_28_0;
        logic [31:0] val_29_0;
        logic [31:0] val_30_0;
        logic [31:0] val_31_0;
        logic [31:0] val_32_0;
        logic [31:0] val_33_0;
        logic [31:0] val_34_0;
        logic [31:0] val_35_0;
        logic [31:0] val_36_0;
        logic [31:0] val_37_0;
        logic [31:0] val_38_0;
        logic [31:0] val_39_0;
        logic [31:0] val_40_0;
        logic [31:0] val_41_0;
        logic [31:0] val_42_0;
        logic [31:0] val_43_0;
        logic [31:0] val_44_0;
        logic [31:0] val_45_0;
        logic [31:0] val_46_0;
        logic [31:0] val_47_0;
        logic [31:0] val_48_0;
        logic [31:0] val_49_0;
        logic [31:0] val_50_0;
        logic [31:0] val_51_0;
        logic [31:0] val_52_0;
        logic [31:0] val_53_0;
        logic [31:0] val_54_0;
        logic [31:0] val_55_0;
        logic [31:0] val_56_0;
        logic [31:0] val_57_0;
        logic [31:0] val_58_0;
        logic [31:0] val_59_0;
        logic [31:0] val_60_0;
        logic [31:0] val_61_0;
        logic [31:0] val_62_0;
        logic [31:0] val_63_0;
        logic [31:0] val_64_0;
    } fp32_constants_t;

    localparam fp32_constants_t FP32_CONST = '{
        val_0_0: 32'h00000000,   // 0.0
        val_1_0: 32'h3F800000,   // 1.0
        val_2_0: 32'h40000000,   // 2.0
        val_3_0: 32'h40400000,   // 3.0
        val_4_0: 32'h40800000,   // 4.0
        val_5_0: 32'h40A00000,   // 5.0
        val_6_0: 32'h40C00000,   // 6.0
        val_7_0: 32'h40E00000,   // 7.0
        val_8_0: 32'h41000000,   // 8.0
        val_9_0: 32'h41100000,   // 9.0
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
        val_26_0: 32'h41D00000,  // 26.0
        val_27_0: 32'h41D80000,  // 27.0
        val_28_0: 32'h41E00000,  // 28.0
        val_29_0: 32'h41E80000,  // 29.0
        val_30_0: 32'h41F00000,  // 30.0
        val_31_0: 32'h41F80000,  // 31.0
        val_32_0: 32'h42000000,  // 32.0
        val_33_0: 32'h42040000,  // 33.0
        val_34_0: 32'h42080000,  // 34.0
        val_35_0: 32'h420C0000,  // 35.0
        val_36_0: 32'h42100000,  // 36.0
        val_37_0: 32'h42140000,  // 37.0
        val_38_0: 32'h42180000,  // 38.0
        val_39_0: 32'h421C0000,  // 39.0
        val_40_0: 32'h42200000,  // 40.0
        val_41_0: 32'h42240000,  // 41.0
        val_42_0: 32'h42280000,  // 42.0
        val_43_0: 32'h422C0000,  // 43.0
        val_44_0: 32'h42300000,  // 44.0
        val_45_0: 32'h42340000,  // 45.0
        val_46_0: 32'h42380000,  // 46.0
        val_47_0: 32'h423C0000,  // 47.0
        val_48_0: 32'h42400000,  // 48.0
        val_49_0: 32'h42440000,  // 49.0
        val_50_0: 32'h42480000,  // 50.0
        val_51_0: 32'h424C0000,  // 51.0
        val_52_0: 32'h42500000,  // 52.0
        val_53_0: 32'h42540000,  // 53.0
        val_54_0: 32'h42580000,  // 54.0
        val_55_0: 32'h425C0000,  // 55.0
        val_56_0: 32'h42600000,  // 56.0
        val_57_0: 32'h42640000,  // 57.0
        val_58_0: 32'h42680000,  // 58.0
        val_59_0: 32'h426C0000,  // 59.0
        val_60_0: 32'h42700000,  // 60.0
        val_61_0: 32'h42740000,  // 61.0
        val_62_0: 32'h42780000,  // 62.0
        val_63_0: 32'h427C0000,  // 63.0
        val_64_0: 32'h42800000   // 64.0
    };

    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end

    SystolicArray #(
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
                {3'd0, 3'd0}: while (dut.gen_row[0].gen_col[0].pe_inst.current_state != dut.gen_row[0].gen_col[0].pe_inst.IDLE) @(posedge clk);
                {3'd0, 3'd1}: while (dut.gen_row[0].gen_col[1].pe_inst.current_state != dut.gen_row[0].gen_col[1].pe_inst.IDLE) @(posedge clk);
                {3'd0, 3'd2}: while (dut.gen_row[0].gen_col[2].pe_inst.current_state != dut.gen_row[0].gen_col[2].pe_inst.IDLE) @(posedge clk);
                {3'd0, 3'd3}: while (dut.gen_row[0].gen_col[3].pe_inst.current_state != dut.gen_row[0].gen_col[3].pe_inst.IDLE) @(posedge clk);
                {3'd0, 3'd4}: while (dut.gen_row[0].gen_col[4].pe_inst.current_state != dut.gen_row[0].gen_col[4].pe_inst.IDLE) @(posedge clk);
                {3'd0, 3'd5}: while (dut.gen_row[0].gen_col[5].pe_inst.current_state != dut.gen_row[0].gen_col[5].pe_inst.IDLE) @(posedge clk);
                {3'd0, 3'd6}: while (dut.gen_row[0].gen_col[6].pe_inst.current_state != dut.gen_row[0].gen_col[6].pe_inst.IDLE) @(posedge clk);
                {3'd0, 3'd7}: while (dut.gen_row[0].gen_col[7].pe_inst.current_state != dut.gen_row[0].gen_col[7].pe_inst.IDLE) @(posedge clk);
                {3'd1, 3'd0}: while (dut.gen_row[1].gen_col[0].pe_inst.current_state != dut.gen_row[1].gen_col[0].pe_inst.IDLE) @(posedge clk);
                {3'd1, 3'd1}: while (dut.gen_row[1].gen_col[1].pe_inst.current_state != dut.gen_row[1].gen_col[1].pe_inst.IDLE) @(posedge clk);
                {3'd1, 3'd2}: while (dut.gen_row[1].gen_col[2].pe_inst.current_state != dut.gen_row[1].gen_col[2].pe_inst.IDLE) @(posedge clk);
                {3'd1, 3'd3}: while (dut.gen_row[1].gen_col[3].pe_inst.current_state != dut.gen_row[1].gen_col[3].pe_inst.IDLE) @(posedge clk);
                {3'd1, 3'd4}: while (dut.gen_row[1].gen_col[4].pe_inst.current_state != dut.gen_row[1].gen_col[4].pe_inst.IDLE) @(posedge clk);
                {3'd1, 3'd5}: while (dut.gen_row[1].gen_col[5].pe_inst.current_state != dut.gen_row[1].gen_col[5].pe_inst.IDLE) @(posedge clk);
                {3'd1, 3'd6}: while (dut.gen_row[1].gen_col[6].pe_inst.current_state != dut.gen_row[1].gen_col[6].pe_inst.IDLE) @(posedge clk);
                {3'd1, 3'd7}: while (dut.gen_row[1].gen_col[7].pe_inst.current_state != dut.gen_row[1].gen_col[7].pe_inst.IDLE) @(posedge clk);
                {3'd2, 3'd0}: while (dut.gen_row[2].gen_col[0].pe_inst.current_state != dut.gen_row[2].gen_col[0].pe_inst.IDLE) @(posedge clk);
                {3'd2, 3'd1}: while (dut.gen_row[2].gen_col[1].pe_inst.current_state != dut.gen_row[2].gen_col[1].pe_inst.IDLE) @(posedge clk);
                {3'd2, 3'd2}: while (dut.gen_row[2].gen_col[2].pe_inst.current_state != dut.gen_row[2].gen_col[2].pe_inst.IDLE) @(posedge clk);
                {3'd2, 3'd3}: while (dut.gen_row[2].gen_col[3].pe_inst.current_state != dut.gen_row[2].gen_col[3].pe_inst.IDLE) @(posedge clk);
                {3'd2, 3'd4}: while (dut.gen_row[2].gen_col[4].pe_inst.current_state != dut.gen_row[2].gen_col[4].pe_inst.IDLE) @(posedge clk);
                {3'd2, 3'd5}: while (dut.gen_row[2].gen_col[5].pe_inst.current_state != dut.gen_row[2].gen_col[5].pe_inst.IDLE) @(posedge clk);
                {3'd2, 3'd6}: while (dut.gen_row[2].gen_col[6].pe_inst.current_state != dut.gen_row[2].gen_col[6].pe_inst.IDLE) @(posedge clk);
                {3'd2, 3'd7}: while (dut.gen_row[2].gen_col[7].pe_inst.current_state != dut.gen_row[2].gen_col[7].pe_inst.IDLE) @(posedge clk);
                {3'd3, 3'd0}: while (dut.gen_row[3].gen_col[0].pe_inst.current_state != dut.gen_row[3].gen_col[0].pe_inst.IDLE) @(posedge clk);
                {3'd3, 3'd1}: while (dut.gen_row[3].gen_col[1].pe_inst.current_state != dut.gen_row[3].gen_col[1].pe_inst.IDLE) @(posedge clk);
                {3'd3, 3'd2}: while (dut.gen_row[3].gen_col[2].pe_inst.current_state != dut.gen_row[3].gen_col[2].pe_inst.IDLE) @(posedge clk);
                {3'd3, 3'd3}: while (dut.gen_row[3].gen_col[3].pe_inst.current_state != dut.gen_row[3].gen_col[3].pe_inst.IDLE) @(posedge clk);
                {3'd3, 3'd4}: while (dut.gen_row[3].gen_col[4].pe_inst.current_state != dut.gen_row[3].gen_col[4].pe_inst.IDLE) @(posedge clk);
                {3'd3, 3'd5}: while (dut.gen_row[3].gen_col[5].pe_inst.current_state != dut.gen_row[3].gen_col[5].pe_inst.IDLE) @(posedge clk);
                {3'd3, 3'd6}: while (dut.gen_row[3].gen_col[6].pe_inst.current_state != dut.gen_row[3].gen_col[6].pe_inst.IDLE) @(posedge clk);
                {3'd3, 3'd7}: while (dut.gen_row[3].gen_col[7].pe_inst.current_state != dut.gen_row[3].gen_col[7].pe_inst.IDLE) @(posedge clk);
                {3'd4, 3'd0}: while (dut.gen_row[4].gen_col[0].pe_inst.current_state != dut.gen_row[4].gen_col[0].pe_inst.IDLE) @(posedge clk);
                {3'd4, 3'd1}: while (dut.gen_row[4].gen_col[1].pe_inst.current_state != dut.gen_row[4].gen_col[1].pe_inst.IDLE) @(posedge clk);
                {3'd4, 3'd2}: while (dut.gen_row[4].gen_col[2].pe_inst.current_state != dut.gen_row[4].gen_col[2].pe_inst.IDLE) @(posedge clk);
                {3'd4, 3'd3}: while (dut.gen_row[4].gen_col[3].pe_inst.current_state != dut.gen_row[4].gen_col[3].pe_inst.IDLE) @(posedge clk);
                {3'd4, 3'd4}: while (dut.gen_row[4].gen_col[4].pe_inst.current_state != dut.gen_row[4].gen_col[4].pe_inst.IDLE) @(posedge clk);
                {3'd4, 3'd5}: while (dut.gen_row[4].gen_col[5].pe_inst.current_state != dut.gen_row[4].gen_col[5].pe_inst.IDLE) @(posedge clk);
                {3'd4, 3'd6}: while (dut.gen_row[4].gen_col[6].pe_inst.current_state != dut.gen_row[4].gen_col[6].pe_inst.IDLE) @(posedge clk);
                {3'd4, 3'd7}: while (dut.gen_row[4].gen_col[7].pe_inst.current_state != dut.gen_row[4].gen_col[7].pe_inst.IDLE) @(posedge clk);
                {3'd5, 3'd0}: while (dut.gen_row[5].gen_col[0].pe_inst.current_state != dut.gen_row[5].gen_col[0].pe_inst.IDLE) @(posedge clk);
                {3'd5, 3'd1}: while (dut.gen_row[5].gen_col[1].pe_inst.current_state != dut.gen_row[5].gen_col[1].pe_inst.IDLE) @(posedge clk);
                {3'd5, 3'd2}: while (dut.gen_row[5].gen_col[2].pe_inst.current_state != dut.gen_row[5].gen_col[2].pe_inst.IDLE) @(posedge clk);
                {3'd5, 3'd3}: while (dut.gen_row[5].gen_col[3].pe_inst.current_state != dut.gen_row[5].gen_col[3].pe_inst.IDLE) @(posedge clk);
                {3'd5, 3'd4}: while (dut.gen_row[5].gen_col[4].pe_inst.current_state != dut.gen_row[5].gen_col[4].pe_inst.IDLE) @(posedge clk);
                {3'd5, 3'd5}: while (dut.gen_row[5].gen_col[5].pe_inst.current_state != dut.gen_row[5].gen_col[5].pe_inst.IDLE) @(posedge clk);
                {3'd5, 3'd6}: while (dut.gen_row[5].gen_col[6].pe_inst.current_state != dut.gen_row[5].gen_col[6].pe_inst.IDLE) @(posedge clk);
                {3'd5, 3'd7}: while (dut.gen_row[5].gen_col[7].pe_inst.current_state != dut.gen_row[5].gen_col[7].pe_inst.IDLE) @(posedge clk);
                {3'd6, 3'd0}: while (dut.gen_row[6].gen_col[0].pe_inst.current_state != dut.gen_row[6].gen_col[0].pe_inst.IDLE) @(posedge clk);
                {3'd6, 3'd1}: while (dut.gen_row[6].gen_col[1].pe_inst.current_state != dut.gen_row[6].gen_col[1].pe_inst.IDLE) @(posedge clk);
                {3'd6, 3'd2}: while (dut.gen_row[6].gen_col[2].pe_inst.current_state != dut.gen_row[6].gen_col[2].pe_inst.IDLE) @(posedge clk);
                {3'd6, 3'd3}: while (dut.gen_row[6].gen_col[3].pe_inst.current_state != dut.gen_row[6].gen_col[3].pe_inst.IDLE) @(posedge clk);
                {3'd6, 3'd4}: while (dut.gen_row[6].gen_col[4].pe_inst.current_state != dut.gen_row[6].gen_col[4].pe_inst.IDLE) @(posedge clk);
                {3'd6, 3'd5}: while (dut.gen_row[6].gen_col[5].pe_inst.current_state != dut.gen_row[6].gen_col[5].pe_inst.IDLE) @(posedge clk);
                {3'd6, 3'd6}: while (dut.gen_row[6].gen_col[6].pe_inst.current_state != dut.gen_row[6].gen_col[6].pe_inst.IDLE) @(posedge clk);
                {3'd6, 3'd7}: while (dut.gen_row[6].gen_col[7].pe_inst.current_state != dut.gen_row[6].gen_col[7].pe_inst.IDLE) @(posedge clk);
                {3'd7, 3'd0}: while (dut.gen_row[7].gen_col[0].pe_inst.current_state != dut.gen_row[7].gen_col[0].pe_inst.IDLE) @(posedge clk);
                {3'd7, 3'd1}: while (dut.gen_row[7].gen_col[1].pe_inst.current_state != dut.gen_row[7].gen_col[1].pe_inst.IDLE) @(posedge clk);
                {3'd7, 3'd2}: while (dut.gen_row[7].gen_col[2].pe_inst.current_state != dut.gen_row[7].gen_col[2].pe_inst.IDLE) @(posedge clk);
                {3'd7, 3'd3}: while (dut.gen_row[7].gen_col[3].pe_inst.current_state != dut.gen_row[7].gen_col[3].pe_inst.IDLE) @(posedge clk);
                {3'd7, 3'd4}: while (dut.gen_row[7].gen_col[4].pe_inst.current_state != dut.gen_row[7].gen_col[4].pe_inst.IDLE) @(posedge clk);
                {3'd7, 3'd5}: while (dut.gen_row[7].gen_col[5].pe_inst.current_state != dut.gen_row[7].gen_col[5].pe_inst.IDLE) @(posedge clk);
                {3'd7, 3'd6}: while (dut.gen_row[7].gen_col[6].pe_inst.current_state != dut.gen_row[7].gen_col[6].pe_inst.IDLE) @(posedge clk);
                {3'd7, 3'd7}: while (dut.gen_row[7].gen_col[7].pe_inst.current_state != dut.gen_row[7].gen_col[7].pe_inst.IDLE) @(posedge clk);
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

            while (!accumulator_valid[row][col]) @(posedge clk);

            actual_value = (col == N-1) ? data_out_east[row] : dut.data_connections[row][col+1];
            valid_flag = accumulator_valid[row][col];

            select_accumulator[row][col] = 0;
            @(posedge clk);

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

            for (int i = 0; i < N; i++) begin
                wait(passthrough_valid[i][i]);
                @(posedge clk);
            end

            $display("All PEs completed for %s", cycle_name);
        end
    endtask

    task init_identity_test();
        begin
            $display("Initializing 8x8 Identity Test Matrices:");

            for (int i = 0; i < N; i++) begin
                for (int j = 0; j < N; j++) begin
                    case (i*N + j)
                        0: matrix_a[i][j] = FP32_CONST.val_1_0;
                        1: matrix_a[i][j] = FP32_CONST.val_2_0;
                        2: matrix_a[i][j] = FP32_CONST.val_3_0;
                        3: matrix_a[i][j] = FP32_CONST.val_4_0;
                        4: matrix_a[i][j] = FP32_CONST.val_5_0;
                        5: matrix_a[i][j] = FP32_CONST.val_6_0;
                        6: matrix_a[i][j] = FP32_CONST.val_7_0;
                        7: matrix_a[i][j] = FP32_CONST.val_8_0;
                        8: matrix_a[i][j] = FP32_CONST.val_9_0;
                        9: matrix_a[i][j] = FP32_CONST.val_10_0;
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
                        25: matrix_a[i][j] = FP32_CONST.val_26_0;
                        26: matrix_a[i][j] = FP32_CONST.val_27_0;
                        27: matrix_a[i][j] = FP32_CONST.val_28_0;
                        28: matrix_a[i][j] = FP32_CONST.val_29_0;
                        29: matrix_a[i][j] = FP32_CONST.val_30_0;
                        30: matrix_a[i][j] = FP32_CONST.val_31_0;
                        31: matrix_a[i][j] = FP32_CONST.val_32_0;
                        32: matrix_a[i][j] = FP32_CONST.val_33_0;
                        33: matrix_a[i][j] = FP32_CONST.val_34_0;
                        34: matrix_a[i][j] = FP32_CONST.val_35_0;
                        35: matrix_a[i][j] = FP32_CONST.val_36_0;
                        36: matrix_a[i][j] = FP32_CONST.val_37_0;
                        37: matrix_a[i][j] = FP32_CONST.val_38_0;
                        38: matrix_a[i][j] = FP32_CONST.val_39_0;
                        39: matrix_a[i][j] = FP32_CONST.val_40_0;
                        40: matrix_a[i][j] = FP32_CONST.val_41_0;
                        41: matrix_a[i][j] = FP32_CONST.val_42_0;
                        42: matrix_a[i][j] = FP32_CONST.val_43_0;
                        43: matrix_a[i][j] = FP32_CONST.val_44_0;
                        44: matrix_a[i][j] = FP32_CONST.val_45_0;
                        45: matrix_a[i][j] = FP32_CONST.val_46_0;
                        46: matrix_a[i][j] = FP32_CONST.val_47_0;
                        47: matrix_a[i][j] = FP32_CONST.val_48_0;
                        48: matrix_a[i][j] = FP32_CONST.val_49_0;
                        49: matrix_a[i][j] = FP32_CONST.val_50_0;
                        50: matrix_a[i][j] = FP32_CONST.val_51_0;
                        51: matrix_a[i][j] = FP32_CONST.val_52_0;
                        52: matrix_a[i][j] = FP32_CONST.val_53_0;
                        53: matrix_a[i][j] = FP32_CONST.val_54_0;
                        54: matrix_a[i][j] = FP32_CONST.val_55_0;
                        55: matrix_a[i][j] = FP32_CONST.val_56_0;
                        56: matrix_a[i][j] = FP32_CONST.val_57_0;
                        57: matrix_a[i][j] = FP32_CONST.val_58_0;
                        58: matrix_a[i][j] = FP32_CONST.val_59_0;
                        59: matrix_a[i][j] = FP32_CONST.val_60_0;
                        60: matrix_a[i][j] = FP32_CONST.val_61_0;
                        61: matrix_a[i][j] = FP32_CONST.val_62_0;
                        62: matrix_a[i][j] = FP32_CONST.val_63_0;
                        63: matrix_a[i][j] = FP32_CONST.val_64_0;
                    endcase
                end
            end

            for (int i = 0; i < N; i++) begin
                for (int j = 0; j < N; j++) begin
                    matrix_b[i][j] = (i == j) ? FP32_CONST.val_1_0 : FP32_CONST.val_0_0;
                end
            end

            for (int i = 0; i < N; i++) begin
                for (int j = 0; j < N; j++) begin
                    expected_result[i][j] = matrix_a[i][j];
                end
            end

            display_matrices("Identity Test");
        end
    endtask

    task init_random_matrices();
        static logic [31:0] a_values [0:63] = '{
            FP32_CONST.val_1_0, FP32_CONST.val_2_0, FP32_CONST.val_3_0, FP32_CONST.val_4_0,
            FP32_CONST.val_5_0, FP32_CONST.val_6_0, FP32_CONST.val_7_0, FP32_CONST.val_8_0,
            FP32_CONST.val_9_0, FP32_CONST.val_10_0, FP32_CONST.val_11_0, FP32_CONST.val_12_0,
            FP32_CONST.val_13_0, FP32_CONST.val_14_0, FP32_CONST.val_15_0, FP32_CONST.val_16_0,
            FP32_CONST.val_17_0, FP32_CONST.val_18_0, FP32_CONST.val_19_0, FP32_CONST.val_20_0,
            FP32_CONST.val_21_0, FP32_CONST.val_22_0, FP32_CONST.val_23_0, FP32_CONST.val_24_0,
            FP32_CONST.val_25_0, FP32_CONST.val_26_0, FP32_CONST.val_27_0, FP32_CONST.val_28_0,
            FP32_CONST.val_29_0, FP32_CONST.val_30_0, FP32_CONST.val_31_0, FP32_CONST.val_32_0,
            FP32_CONST.val_33_0, FP32_CONST.val_34_0, FP32_CONST.val_35_0, FP32_CONST.val_36_0,
            FP32_CONST.val_37_0, FP32_CONST.val_38_0, FP32_CONST.val_39_0, FP32_CONST.val_40_0,
            FP32_CONST.val_41_0, FP32_CONST.val_42_0, FP32_CONST.val_43_0, FP32_CONST.val_44_0,
            FP32_CONST.val_45_0, FP32_CONST.val_46_0, FP32_CONST.val_47_0, FP32_CONST.val_48_0,
            FP32_CONST.val_49_0, FP32_CONST.val_50_0, FP32_CONST.val_51_0, FP32_CONST.val_52_0,
            FP32_CONST.val_53_0, FP32_CONST.val_54_0, FP32_CONST.val_55_0, FP32_CONST.val_56_0,
            FP32_CONST.val_57_0, FP32_CONST.val_58_0, FP32_CONST.val_59_0, FP32_CONST.val_60_0,
            FP32_CONST.val_61_0, FP32_CONST.val_62_0, FP32_CONST.val_63_0, FP32_CONST.val_64_0
        };

        static logic [31:0] b_values [0:63] = '{
            FP32_CONST.val_2_0, FP32_CONST.val_1_0, FP32_CONST.val_4_0, FP32_CONST.val_3_0,
            FP32_CONST.val_6_0, FP32_CONST.val_5_0, FP32_CONST.val_8_0, FP32_CONST.val_7_0,
            FP32_CONST.val_10_0, FP32_CONST.val_9_0, FP32_CONST.val_12_0, FP32_CONST.val_11_0,
            FP32_CONST.val_14_0, FP32_CONST.val_13_0, FP32_CONST.val_16_0, FP32_CONST.val_15_0,
            FP32_CONST.val_18_0, FP32_CONST.val_17_0, FP32_CONST.val_20_0, FP32_CONST.val_19_0,
            FP32_CONST.val_22_0, FP32_CONST.val_21_0, FP32_CONST.val_24_0, FP32_CONST.val_23_0,
            FP32_CONST.val_26_0, FP32_CONST.val_25_0, FP32_CONST.val_28_0, FP32_CONST.val_27_0,
            FP32_CONST.val_30_0, FP32_CONST.val_29_0, FP32_CONST.val_32_0, FP32_CONST.val_31_0,
            FP32_CONST.val_34_0, FP32_CONST.val_33_0, FP32_CONST.val_36_0, FP32_CONST.val_35_0,
            FP32_CONST.val_38_0, FP32_CONST.val_37_0, FP32_CONST.val_40_0, FP32_CONST.val_39_0,
            FP32_CONST.val_42_0, FP32_CONST.val_41_0, FP32_CONST.val_44_0, FP32_CONST.val_43_0,
            FP32_CONST.val_46_0, FP32_CONST.val_45_0, FP32_CONST.val_48_0, FP32_CONST.val_47_0,
            FP32_CONST.val_50_0, FP32_CONST.val_49_0, FP32_CONST.val_52_0, FP32_CONST.val_51_0,
            FP32_CONST.val_54_0, FP32_CONST.val_53_0, FP32_CONST.val_56_0, FP32_CONST.val_55_0,
            FP32_CONST.val_58_0, FP32_CONST.val_57_0, FP32_CONST.val_60_0, FP32_CONST.val_59_0,
            FP32_CONST.val_62_0, FP32_CONST.val_61_0, FP32_CONST.val_64_0, FP32_CONST.val_63_0
        };

        static logic [31:0] expected_values [0:63] = '{
            32'h44B10000, 32'h44AC8000, 32'h44BA0000, 32'h44B58000, 32'h44C30000, 32'h44BE8000, 32'h44CC0000, 32'h44C78000,
            32'h45508000, 32'h454A4000, 32'h455D0000, 32'h4556C000, 32'h45698000, 32'h45634000, 32'h45760000, 32'h456FC000,
            32'h45A44000, 32'h459F2000, 32'h45AE8000, 32'h45A96000, 32'h45B8C000, 32'h45B3A000, 32'h45C30000, 32'h45BDE000,
            32'h45E04000, 32'h45D92000, 32'h45EE8000, 32'h45E76000, 32'h45FCC000, 32'h45F5A000, 32'h46058000, 32'h4601F000,
            32'h460E2000, 32'h46099000, 32'h46174000, 32'h4612B000, 32'h46206000, 32'h461BD000, 32'h46298000, 32'h4624F000,
            32'h462C2000, 32'h46269000, 32'h46374000, 32'h4631B000, 32'h46426000, 32'h463CD000, 32'h464D8000, 32'h4647F000,
            32'h464A2000, 32'h46439000, 32'h46574000, 32'h4650B000, 32'h46646000, 32'h465DD000, 32'h46718000, 32'h466AF000,
            32'h46682000, 32'h46609000, 32'h46774000, 32'h466FB000, 32'h46833000, 32'h467ED000, 32'h468AC000, 32'h4686F800
        };

        begin
            $display("Initializing 8x8 Random Test Matrices:");

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

            if (is_identity) init_identity_test();
            else init_random_matrices();

            apply_reset();

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

    initial begin
        $display("Testing matrix multiplication with identity and random matrices\n");

        initialize_signals();
        apply_reset();

        execute_matrix_test("8x8 IDENTITY MATRIX TEST", 1'b1);
        repeat(10) @(posedge clk);

        execute_matrix_test("8x8 RANDOM MATRIX TEST", 1'b0);
        repeat(10) @(posedge clk);

        print_test_summary();
        $finish;
    end

    initial begin
        #1000000;
        $display("ERROR: Testbench timeout after 1ms!");
        print_test_summary();
        $finish;
    end

    initial begin
        $dumpfile("TB_SystolicArray_8x8.vcd");
        $dumpvars(0, TB_SystolicArray_8x8);
    end

endmodule
