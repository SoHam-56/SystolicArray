`timescale 1ns / 100ps

module MAC #(parameter DATA_WIDTH = 32)
    (
        input wire clk_i,
        input wire rstn_i,
        input wire [DATA_WIDTH - 1:0] data_i,
        input wire [DATA_WIDTH - 1:0] weight_i,
        input wire start_i,          // Start MAC operation
        output reg mac_done_o,
        output reg [DATA_WIDTH - 1:0] result_o
    );
    // Internal registers
    reg [DATA_WIDTH - 1:0] mul_in1, mul_in2, add_in1, add_in2;
    reg [DATA_WIDTH - 1:0] accumulator;
    wire [DATA_WIDTH - 1:0] adder_result, mul_result;
    wire add_done, mul_done;

    // State machine for MAC operation
    typedef enum reg [1:0] {
        IDLE = 2'b00,
        MULTIPLY = 2'b01,
        ACCUMULATE = 2'b10,
        DONE = 2'b11
    } state_t;
    state_t current_state, next_state;

    // Previous state register to detect state transitions
    state_t prev_state;

    // State machine logic
    always @(posedge clk_i or negedge rstn_i) begin
        if (!rstn_i) begin
            current_state <= IDLE;
            prev_state <= IDLE;
        end else begin
            prev_state <= current_state;
            current_state <= next_state;
        end
    end

    // Next state logic
    always @(*) begin
        case (current_state)
            IDLE: begin
                if (start_i)
                    next_state = MULTIPLY;
                else
                    next_state = IDLE;
            end
            MULTIPLY: begin
                if (mul_done)
                    next_state = ACCUMULATE;
                else
                    next_state = MULTIPLY;
            end
            ACCUMULATE: begin
                if (add_done)
                    next_state = DONE;
                else
                    next_state = ACCUMULATE;
            end
            DONE: begin
                next_state = IDLE;
            end
            default: next_state = IDLE;
        endcase
    end

    // Generate single-cycle pulses for valid_i signals
    wire mul_valid_pulse = (current_state == MULTIPLY) && (prev_state != MULTIPLY);
    wire add_valid_pulse = (current_state == ACCUMULATE) && (prev_state != ACCUMULATE);

    // Control signals and data path
    always @(posedge clk_i or negedge rstn_i) begin
        if (!rstn_i) begin
            result_o <= {DATA_WIDTH{1'b0}};
            accumulator <= {DATA_WIDTH{1'b0}};
            mul_in1 <= {DATA_WIDTH{1'b0}};
            mul_in2 <= {DATA_WIDTH{1'b0}};
            add_in1 <= {DATA_WIDTH{1'b0}};
            add_in2 <= {DATA_WIDTH{1'b0}};
            mac_done_o <= 1'b0;
        end else begin
            case (current_state)
                IDLE: begin
                    mac_done_o <= 1'b0;
                    if (start_i) begin
                        mul_in1 <= data_i;
                        mul_in2 <= weight_i;
                    end
                end
                MULTIPLY: begin
                    // Wait for multiplication to complete
                    if (mul_done) begin
                        add_in1 <= accumulator;
                        add_in2 <= mul_result;
                    end
                end
                ACCUMULATE: begin
                    // Wait for addition to complete
                    if (add_done) begin
                        accumulator <= adder_result;
                        result_o <= adder_result;
                    end
                end
                DONE: begin
                    mac_done_o <= 1'b1;
                end
            endcase
        end
    end

    // Instantiate multiplier
    multiply_32 MUL (
        .clk_i(clk_i),
        .rstn_i(rstn_i),
        .valid_i(mul_valid_pulse),  // Single-cycle pulse
        .A(mul_in1),
        .B(mul_in2),
        .Result(mul_result),
        .done_o(mul_done)
    );

    // Instantiate adder
    Adder_32 ADD (
        .clk_i(clk_i),
        .rstn_i(rstn_i),
        .valid_i(add_valid_pulse),  // Single-cycle pulse
        .A(add_in1),
        .B(add_in2),
        .Result(adder_result),
        .done_o(add_done)
    );
endmodule
