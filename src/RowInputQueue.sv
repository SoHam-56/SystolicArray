`timescale 1ns / 100ps

module RowInputQueue #(
    parameter N = 8,                    // Systolic array dimension
    parameter DATA_WIDTH = 32,          // Data width
    parameter MEM_FILE = "default.mem"  // Memory initialization file
) (
    input logic clk_i,
    input logic rstn_i,

    // Control signals
    input logic start_i,                            // Start signal to begin queue operation
    input logic [N-1:0] passthrough_valid_i,        // passthrough_valid from edge PEs

    // Data outputs to systolic array
    output logic [DATA_WIDTH-1:0] data_o [0:N-1],   // Data outputs to N PEs
    output logic data_valid_o,                      // Valid signal for first PE (generates N pulses)

    // Status
    output logic queue_empty_o                      // All data has been read
);

    localparam SRAM_DEPTH = N * N;                  // Total SRAM depth (N elements per PE, N PEs)

    logic [DATA_WIDTH-1:0] sram [0:SRAM_DEPTH-1];

    // Address pointers for each PE
    logic [$clog2(SRAM_DEPTH)-1:0] read_addr [0:N-1];

    // Passthrough valid delay registers (2 cycle delay as specified)
    logic [N-1:0] passthrough_valid_d1;
    logic [N-1:0] passthrough_valid_d2;

    // State tracking
    logic queue_active;
    logic first_data_sent;
    logic first_data_pulse;  // Tracks the single pulse for first data
    logic pe0_data_valid;    // Added: tracks when PE[0] gets new valid data
    logic [N-1:0] pe_data_count;  // Count of data sent to each PE

    // Initialize SRAM from memory file
    initial begin
        if (MEM_FILE != "default.mem") begin
            $readmemh(MEM_FILE, sram);
        end else begin
            // Default initialization with zeros
            for (int i = 0; i < SRAM_DEPTH; i++) begin
                sram[i] = '0;
            end
        end
    end

    // Reset and initialization logic
    always_ff @(posedge clk_i or negedge rstn_i) begin
        if (!rstn_i) begin
            for (int i = 0; i < N; i++) begin
                read_addr[i] <= i * N;  // Each PE starts at its base address (0, N, 2N, 3N, ...)
                pe_data_count[i] <= '0;
            end
            passthrough_valid_d1 <= '0;
            passthrough_valid_d2 <= '0;
            queue_active <= 1'b0;
            first_data_sent <= 1'b0;
            first_data_pulse <= 1'b0;
            pe0_data_valid <= 1'b0;  // Added: initialize PE0 valid signal
        end else begin
            // Delay passthrough_valid by 2 cycles
            passthrough_valid_d1 <= passthrough_valid_i;
            passthrough_valid_d2 <= passthrough_valid_d1;

            // Default: clear the pulse signals
            first_data_pulse <= 1'b0;
            pe0_data_valid <= 1'b0;   // Added: clear PE0 valid by default

            // Start queue operation
            if (start_i && !queue_active) begin
                queue_active <= 1'b1;
                first_data_sent <= 1'b0;
            end

            // Send first data immediately when started
            if (queue_active && !first_data_sent) begin
                first_data_sent <= 1'b1;
                first_data_pulse <= 1'b1;
                pe0_data_valid <= 1'b1;  // Added: PE0 gets valid data
                for (int i = 0; i < N; i++) begin
                    pe_data_count[i] <= pe_data_count[i] + 1'b1;
                end
            end

            // Advance read addresses when passthrough_valid is detected (after 2 cycle delay)
            if (queue_active) begin
                for (int i = 0; i < N; i++) begin
                    if (passthrough_valid_d2[i] && pe_data_count[i] < N) begin
                        read_addr[i] <= read_addr[i] + 1'b1;
                        pe_data_count[i] <= pe_data_count[i] + 1'b1;

                        // Added: Generate valid pulse for PE[0] when it gets new data
                        if (i == 0) begin
                            pe0_data_valid <= 1'b1;
                        end
                    end
                end
            end

            // Stop queue when all data has been sent
            if (queue_active && (&(pe_data_count == N))) begin
                queue_active <= 1'b0;
            end
        end
    end

    // Combinational output logic
    always_comb begin
        // Default outputs
        for (int i = 0; i < N; i++) begin
            if (pe_data_count[i] < N) begin
                data_o[i] = sram[read_addr[i]];
            end else begin
                data_o[i] = '0;  // Send zeros when no more data
            end
        end

        // Valid signal for first PE - pulses N times (once for each data element)
        data_valid_o = pe0_data_valid;

        // Queue empty when all PEs have read all their data
        queue_empty_o = &(pe_data_count == N);
    end

endmodule
