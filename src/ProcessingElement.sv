`timescale 1ns / 100ps

module ProcessingElement #(parameter DATA_WIDTH = 32)
    (
        input wire clk_i,
        input wire rstn_i,

        // Data inputs from neighboring PEs
        input wire [DATA_WIDTH - 1:0] north_i,      // Data from north PE
        input wire [DATA_WIDTH - 1:0] west_i,       // Data from west PE

        input wire inputs_valid_i,                  // Unified control signal for inputs
        input wire last_element_i,

        // Control signal for accumulator output selection
        input wire select_accumulator_i,            // 1: output accumulator, 0: output data passthrough
        input wire accumulator_valid_i,             // Accumulator content of neighbour indicator

        // Data outputs to neighboring PEs
        output reg [DATA_WIDTH - 1:0] south_o,      // Pass data to south PE
        output reg [DATA_WIDTH - 1:0] east_o,       // Muxed: data passthrough OR accumulator output

        // Control outputs
        output reg passthrough_valid_o,             // Valid for south_o and east_o (passthrough mode)
        output reg accumulator_valid_o,             // Valid for east_o when in accumulator mode
        output reg last_element_east_o
    );

    reg [DATA_WIDTH - 1:0] buffered_north;
    reg [DATA_WIDTH - 1:0] buffered_west;
    reg [DATA_WIDTH - 1:0] buffered_accumulator;

    wire [DATA_WIDTH - 1:0] mac_result;
    wire mac_done;
    reg mac_start;

    wire select_accumulator_gated;

    reg last_element_captured;      // Track last element processing

    reg accumulator_drain_flag;     // Track if we came to OUTPUT state from IDLE due to accumulator_valid_i

    wire last_element_pulse;
    assign last_element_pulse = mac_done & last_element_captured;

    typedef enum reg [1:0] {
        IDLE        = 2'b00,
        LOAD_DATA   = 2'b01,
        MAC_COMPUTE = 2'b10,
        OUTPUT      = 2'b11
    } state_t;

    state_t current_state, next_state;

    assign select_accumulator_gated = select_accumulator_i & (current_state == IDLE);

    always @(posedge clk_i or negedge rstn_i) begin
        if (!rstn_i) begin
            current_state <= IDLE;
        end else begin
            current_state <= next_state;
        end
    end

    always @(*) begin
        case (current_state)
            IDLE: begin
                if (inputs_valid_i)
                    next_state = LOAD_DATA;
                else if (accumulator_valid_i)
                    next_state = OUTPUT;
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

    // Track the transition from IDLE to OUTPUT due to accumulator_valid_i
    always @(posedge clk_i or negedge rstn_i) begin
        if (!rstn_i) begin
            accumulator_drain_flag <= 1'b0;
        end else begin
            if (current_state == IDLE && accumulator_valid_i && next_state == OUTPUT) begin
                accumulator_drain_flag <= 1'b1;
            end else if (current_state == OUTPUT) begin
                accumulator_drain_flag <= 1'b0;  // Clear after OUTPUT state
            end
        end
    end

    // Last element capture logic
    always @(posedge clk_i or negedge rstn_i) begin
        if (!rstn_i) begin
            last_element_captured <= 1'b0;
        end else begin
            // Capture last_element_i pulse (independent of FSM state)
            if (last_element_i) begin
                last_element_captured <= 1'b1;
            end

            // Clear the captured flag when last element pulse is generated
            if (last_element_pulse) begin
                last_element_captured <= 1'b0;  // Clear for next operation
            end
        end
    end

    always @(posedge clk_i or negedge rstn_i) begin
        if (!rstn_i) begin
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
                    last_element_east_o <= 1'b0;

                    // Handle accumulator draining in IDLE state
                    if (select_accumulator_gated) begin
                        east_o <= buffered_accumulator;
                        accumulator_valid_o <= 1'b1;
                    end else begin
                        accumulator_valid_o <= 1'b0;
                    end
                end

                LOAD_DATA: begin
                    buffered_north <= north_i;
                    buffered_west <= west_i;

                    mac_start <= 1'b1;
                    passthrough_valid_o <= 1'b0;
                    accumulator_valid_o <= 1'b0;
                    last_element_east_o <= 1'b0;
                end

                MAC_COMPUTE: begin

                    mac_start <= 1'b0;
                    passthrough_valid_o <= 1'b0;
                    accumulator_valid_o <= 1'b0;
                    last_element_east_o <= 1'b0;

                    if (mac_done) begin                             // Buffer the MAC result and generate last_element pulse when MAC is done
                        buffered_accumulator <= mac_result;
                        last_element_east_o <= last_element_pulse;
                    end
                end

                OUTPUT: begin
                    south_o <= buffered_north;

                    if (accumulator_drain_flag) begin
                        accumulator_valid_o <= 1'b1;
                        passthrough_valid_o <= 1'b0;
                        east_o <= west_i;
                    end else begin
                        passthrough_valid_o <= 1'b1;
                        accumulator_valid_o <= 1'b0;
                        east_o <= buffered_west;
                    end
                    last_element_east_o <= 1'b0;
                end
            endcase
        end
    end

    MAC #(
        .DATA_WIDTH(DATA_WIDTH)
    ) MAC_UNIT (
        .clk_i(clk_i),
        .rstn_i(rstn_i),
        .data_i(west_i),
        .weight_i(north_i),
        .start_i(mac_start),
        .mac_done_o(mac_done),
        .result_o(mac_result)
    );

endmodule
