`timescale 1ns / 100ps

module ColumnInputQueue #(
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
    output logic [N-1:0] last_o,                    // Last signal for each channel (pulse after last element)

    // Status
    output logic queue_empty_o                      // All data has been read
);

    localparam SRAM_DEPTH = N * N;                  // Total SRAM depth (N elements per PE, N PEs)
    localparam COUNT_WIDTH = $clog2(N+1);           // Width needed to count from 0 to N

    logic [DATA_WIDTH-1:0] sram [0:SRAM_DEPTH-1];

    // Address pointers for each PE
    logic [$clog2(SRAM_DEPTH)-1:0] read_addr [0:N-1];

    // Passthrough valid delay registers (2 cycle delay as specified)
    logic passthrough_valid_d1 [0:N-1];
    logic passthrough_valid_d2 [0:N-1];

    // State tracking
    logic queue_active;
    logic first_data_sent;
    logic first_data_pulse;  // Tracks the single pulse for first data
    logic pe0_data_valid;    // tracks when PE[0] gets new valid data
    
    // FIXED: Proper array of counters for each PE
    logic [COUNT_WIDTH-1:0] pe_data_count [0:N-1];  // Count of data sent to each PE

    // Last signal generation
    logic last_element_read [0:N-1];     // Tracks when last element was read for each PE
    logic last_element_read_d1 [0:N-1];  // Delayed by one cycle to generate pulse

    // Initialize SRAM from memory file
    initial begin
        if (MEM_FILE != "default.mem") $readmemh(MEM_FILE, sram);
        else for (int i = 0; i < SRAM_DEPTH; i++) sram[i] = '0;
    end

    // Reset and initialization logic
    always_ff @(posedge clk_i or negedge rstn_i) begin
        if (!rstn_i) begin
            for (int i = 0; i < N; i++) begin
                read_addr[i] <= i;  // Each PE starts at its column index (0, 1, 2, 3, ...)
                pe_data_count[i] <= '0;
            end
            queue_active <= 1'b0;
            first_data_sent <= 1'b0;
            first_data_pulse <= 1'b0;
            pe0_data_valid <= 1'b0;
            for (int i = 0; i < N; i++) begin
                last_element_read[i] <= '0;
                last_element_read_d1[i] <= '0;
                passthrough_valid_d1[i] <= '0;
                passthrough_valid_d2[i] <= '0;
            end
        end else begin

            // Default: clear the pulse signals
            first_data_pulse <= 1'b0;
            pe0_data_valid <= 1'b0;
            for (int i = 0; i < N; i++) begin
                last_element_read[i] <= '0;  // Clear last element read flags
                
                // Delay passthrough_valid by 2 cycles
                passthrough_valid_d1[i] <= passthrough_valid_i[i];
                passthrough_valid_d2[i] <= passthrough_valid_d1[i];
                
                // Delay last_element_read by one cycle to generate pulse
                last_element_read_d1[i] <= last_element_read[i];
            end

            // Start queue operation
            if (start_i && !queue_active) begin
                queue_active <= 1'b1;
                first_data_sent <= 1'b0;
            end

            // Send first data immediately when started
            if (queue_active && !first_data_sent) begin
                first_data_sent <= 1'b1;
                first_data_pulse <= 1'b1;
                pe0_data_valid <= 1'b1;
                for (int i = 0; i < N; i++) pe_data_count[i] <= pe_data_count[i] + 1'b1;
            end

            // Advance read addresses when passthrough_valid is detected (after 2 cycle delay)
            if (queue_active) begin
                for (int i = 0; i < N; i++) begin
                    if (passthrough_valid_d2[i] && pe_data_count[i] < N) begin
                        // Check if this is the last element for this PE BEFORE incrementing
                        if (pe_data_count[i] == (N - 1)) last_element_read[i] <= 1'b1;

                        // Column-wise increment: add N to get next element in same column
                        read_addr[i] <= read_addr[i] + N;
                        pe_data_count[i] <= pe_data_count[i] + 1'b1;

                        // Generate valid pulse for PE[0] when it gets new data
                        if (i == 0) pe0_data_valid <= 1'b1;
                    end
                end
            end

            // Stop queue when all data has been sent
            if (queue_active) begin
                logic all_pes_done;
                all_pes_done = 1'b1;
                for (int i = 0; i < N; i++) if (pe_data_count[i] < N) all_pes_done = 1'b0;
                if (all_pes_done) queue_active <= 1'b0;
            end
        end
    end

    // Combinational output logic
    always_comb begin
        // Data outputs - always output current SRAM data at read address
        // The counter controls when we stop advancing, not when we output zeros
        for (int i = 0; i < N; i++) data_o[i] = sram[read_addr[i]];

        // Valid signal for first PE - pulses N times (once for each data element)
        data_valid_o = pe0_data_valid;

        // Last signal - pulse one cycle after last element is read for each channel
        for (int i = 0; i < N; i++) last_o[i] = last_element_read_d1[i];

        // Queue empty when all PEs have read all their data
        queue_empty_o = 1'b1;
        for (int i = 0; i < N; i++) if (pe_data_count[i] < N) queue_empty_o = 1'b0;
    end

endmodule