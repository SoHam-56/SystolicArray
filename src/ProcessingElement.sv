`timescale 1ns / 100ps

module ProcessingElement #(parameter DATA_WIDTH = 32)
    (
        input wire clk_i,
        input wire rstn_i,

        // Data inputs from neighboring PEs
        input wire [DATA_WIDTH - 1:0] north_i,  // Data from north PE
        input wire [DATA_WIDTH - 1:0] west_i,   // Data from west PE

        input wire inputs_valid_i,                // Unified control signal for inputs
        input wire last_element_i,

        // Control signal for accumulator output selection (only effective in IDLE state)
        input wire select_accumulator_i,  // 1: output accumulator, 0: output data passthrough

        // Data outputs to neighboring PEs
        output reg [DATA_WIDTH - 1:0] south_o,  // Pass data to south PE
        output reg [DATA_WIDTH - 1:0] east_o,   // Muxed: data passthrough OR accumulator output

        // Control outputs
        output reg passthrough_valid_o,    // Valid for south_o and east_o (passthrough mode)
        output reg accumulator_valid_o,    // Valid for east_o when in accumulator mode
        output reg done_o                  // Goes high and stays high after last_element processing completes
    );

    // Internal registers for buffering outputs
    reg [DATA_WIDTH - 1:0] buffered_north;
    reg [DATA_WIDTH - 1:0] buffered_west;
    reg [DATA_WIDTH - 1:0] buffered_accumulator;

    // MAC module signals
    wire [DATA_WIDTH - 1:0] mac_result;
    wire mac_done;
    reg mac_start;

    // Internal signal for controlled accumulator selection
    wire select_accumulator_gated;

    // Registers to track last element processing
    reg last_element_captured;

    // State machine for PE operation
    typedef enum reg [1:0] {
        IDLE = 2'b00,
        LOAD_DATA = 2'b01,
        MAC_COMPUTE = 2'b10,
        OUTPUT = 2'b11
    } state_t;

    state_t current_state, next_state;

    // Gate the select_accumulator signal - only allow it to be effective in IDLE state
    assign select_accumulator_gated = select_accumulator_i & (current_state == IDLE);

    // State machine logic
    always @(posedge clk_i or negedge rstn_i) begin
        if (!rstn_i) begin
            current_state <= IDLE;
        end else begin
            current_state <= next_state;
        end
    end

    // Next state logic
    always @(*) begin
        case (current_state)
            IDLE: begin
                if (inputs_valid_i)  // Unified input valid check
                    next_state = LOAD_DATA;
                else
                    next_state = IDLE;
            end
            LOAD_DATA: begin
                next_state = MAC_COMPUTE;
            end
            MAC_COMPUTE: begin
                if (mac_done)
                    next_state = OUTPUT;
                else
                    next_state = MAC_COMPUTE;
            end
            OUTPUT: begin
                next_state = IDLE;
            end
            default: next_state = IDLE;
        endcase
    end

    // Last element and done logic
    always @(posedge clk_i or negedge rstn_i) begin
        if (!rstn_i) begin
            last_element_captured <= 1'b0;
            done_o <= 1'b0;
        end else begin

            // Capture last_element_i pulse (comes after the data/valid)
            if (last_element_i) last_element_captured <= 1'b1;

            // Check for passthrough completion after last element was captured
            if (last_element_captured && passthrough_valid_o) done_o <= 1'b1;

        end
    end

    // Main PE logic
    always @(posedge clk_i or negedge rstn_i) begin
        if (!rstn_i) begin
            // Reset all registers
            south_o <= {DATA_WIDTH{1'b0}};
            east_o <= {DATA_WIDTH{1'b0}};

            buffered_north <= {DATA_WIDTH{1'b0}};
            buffered_west <= {DATA_WIDTH{1'b0}};
            buffered_accumulator <= {DATA_WIDTH{1'b0}};

            passthrough_valid_o <= 1'b0;
            accumulator_valid_o <= 1'b0;
            mac_start <= 1'b0;
        end else begin
            case (current_state)
                IDLE: begin
                    mac_start <= 1'b0;
                    passthrough_valid_o <= 1'b0;

                    // Handle accumulator draining in IDLE state
                    if (select_accumulator_gated) begin
                        east_o <= buffered_accumulator;
                        accumulator_valid_o <= 1'b1;
                    end else begin
                        accumulator_valid_o <= 1'b0;
                    end
                end

                LOAD_DATA: begin
                    // Buffer data for synchronized output later
                    buffered_north <= north_i;
                    buffered_west <= west_i;
                    // Note: accumulator result will be buffered when MAC completes

                    // Start MAC operation
                    mac_start <= 1'b1;
                    passthrough_valid_o <= 1'b0;
                    accumulator_valid_o <= 1'b0;

                end

                MAC_COMPUTE: begin
                    // Clear start signal after one cycle
                    mac_start <= 1'b0;
                    passthrough_valid_o <= 1'b0;
                    accumulator_valid_o <= 1'b0;

                    // Buffer the MAC result when it's ready
                    if (mac_done) begin
                        buffered_accumulator <= mac_result;
                    end
                end

                OUTPUT: begin
                    // Output data to south and east (passthrough mode only)
                    south_o <= buffered_north;
                    east_o <= buffered_west;
                    passthrough_valid_o <= 1'b1;
                    accumulator_valid_o <= 1'b0;
                end
            endcase
        end
    end

    MAC #(
        .DATA_WIDTH(DATA_WIDTH)
    ) MAC_UNIT (
        .clk_i(clk_i),
        .rstn_i(rstn_i),
        .data_i(west_i),    // Data from west
        .weight_i(north_i), // Data from north
        .start_i(mac_start),
        .mac_done_o(mac_done),
        .result_o(mac_result)       // This becomes buffered_accumulator
    );

endmodule
