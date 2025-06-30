`timescale 1ns / 100ps

module ProcessingElement #(parameter DATA_WIDTH = 32)
    (
        input wire clk_i,
        input wire rstn_i,

        // Data inputs from neighboring PEs
        input wire [DATA_WIDTH - 1:0] north_i,    // Data from north PE
        input wire [DATA_WIDTH - 1:0] west_i,     // Data from west PE

        input wire inputs_valid_i,                // Unified control signal for inputs
        input wire last_element_i,

        // Control signal for accumulator output selection
        input wire select_accumulator_i,          // 1: output accumulator, 0: output data passthrough
        
        // NEW: Drain mode control signal
        input wire drain_mode_i,                  // 1: drain mode (bypass MAC), 0: normal mode

        // Data outputs to neighboring PEs
        output reg [DATA_WIDTH - 1:0] south_o,    // Pass data to south PE
        output reg [DATA_WIDTH - 1:0] east_o,     // Muxed: data passthrough OR accumulator output

        // Control outputs
        output reg passthrough_valid_o,           // Unified valid for east_o (passthrough OR accumulator mode)
        output reg last_element_east_o
    );

    reg [DATA_WIDTH - 1:0] buffered_north;
    reg [DATA_WIDTH - 1:0] buffered_west;
    reg [DATA_WIDTH - 1:0] buffered_accumulator;

    wire [DATA_WIDTH - 1:0] mac_result;
    wire mac_done;
    reg mac_start;

    wire select_accumulator_gated;

    // Registers to track last element processing
    reg last_element_captured;

    wire last_element_pulse;
    assign last_element_pulse = mac_done & last_element_captured;

    typedef enum reg [2:0] {
        IDLE = 3'b000,
        LOAD_DATA = 3'b001,
        MAC_COMPUTE = 3'b010,
        OUTPUT = 3'b011,
        DRAIN_OUTPUT = 3'b100      // NEW: Drain mode output state
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
                if (inputs_valid_i) begin
                    if (drain_mode_i) begin
                        // In drain mode, go directly to DRAIN_OUTPUT to pass through data
                        next_state = DRAIN_OUTPUT;
                    end else begin
                        // Normal mode: go to LOAD_DATA for MAC operation
                        next_state = LOAD_DATA;
                    end
                end else begin
                    next_state = IDLE;
                end
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
            DRAIN_OUTPUT: begin
                // NEW: Drain mode output state - go back to IDLE after one cycle
                next_state = IDLE;
            end
            default: next_state = IDLE;
        endcase
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
            mac_start <= 1'b0;
            last_element_east_o <= 1'b0;
        end else begin
            case (current_state)
                IDLE: begin
                    mac_start <= 1'b0;
                    last_element_east_o <= 1'b0;

                    // Handle accumulator draining in IDLE state
                    if (select_accumulator_gated) begin
                        east_o <= buffered_accumulator;
                        passthrough_valid_o <= 1'b1;  // Use unified valid signal
                    end else begin
                        passthrough_valid_o <= 1'b0;
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
                    last_element_east_o <= 1'b0;
                end

                MAC_COMPUTE: begin
                    // Clear start signal after one cycle
                    mac_start <= 1'b0;
                    passthrough_valid_o <= 1'b0;
                    last_element_east_o <= 1'b0;

                    // Buffer the MAC result and generate last_element pulse when MAC is done
                    if (mac_done) begin
                        buffered_accumulator <= mac_result;
                        last_element_east_o <= last_element_pulse;
                    end
                end

                OUTPUT: begin
                    south_o <= buffered_north;
                    east_o <= buffered_west;
                    passthrough_valid_o <= 1'b1;  // Use unified valid signal
                    last_element_east_o <= 1'b0;
                end

                DRAIN_OUTPUT: begin
                    // NEW: Drain mode output state
                    // Pass through current inputs directly without MAC operation
                    south_o <= north_i;
                    east_o <= west_i;
                    passthrough_valid_o <= 1'b1;
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