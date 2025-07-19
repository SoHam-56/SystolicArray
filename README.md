# Systolic Array for Matrix Multiplication

## 1. System Overview

This systolic array implementation performs matrix multiplication using a 2D grid of Processing Elements (PEs) arranged in an N×N configuration. For this analysis, we'll use N=3 as the example, creating a 3×3 systolic array that multiplies two 3×3 matrices.

The system consists of five major components:
- **Input Queue System**: Two specialized queues that feed data into the array
- **Processing Element Mesh**: 3×3 grid of computational units
- **Wave Control System**: Manages result collection timing
- **Output Collection System**: Gathers and stores final results
- **Control and Status Logic**: Coordinates overall operation

## 2. Data Organization and Memory Layout

### 2.1 Input Matrix Storage

**Matrix A (Rows - West Input)**
```
Matrix A = [a00 a01 a02]    Stored as: PE0: [a00, a01, a02]
           [a10 a11 a12] ────────────→ PE1: [a10, a11, a12]
           [a20 a21 a22]               PE2: [a20, a21, a22]

Memory Layout: [a00, a01, a02, a10, a11, a12, a20, a21, a22]
Addresses:     [ 0,   1,   2,   3,   4,   5,   6,   7,   8]
```

**Matrix B (Columns - North Input)**
```
Matrix B = [b00 b01 b02]    Stored as: PE0: [b00, b10, b20]
           [b10 b11 b12] ────────────→ PE1: [b01, b11, b21]
           [b20 b21 b22]               PE2: [b02, b12, b22]

Memory Layout: [b00, b01, b02, b10, b11, b12, b20, b21, b22]
Addresses:     [ 0,   1,   2,   3,   4,   5,   6,   7,   8]
```

### 2.2 Processing Element Grid Layout

```
     North Inputs (Weights from Matrix B)
        ↓b00  ↓b01  ↓b02
       ┌─────┬─────┬─────┐
  a00→ │PE00 │PE01 │PE02 │ → East Output
       ├─────┼─────┼─────┤
  a10→ │PE10 │PE11 │PE12 │ → East Output
       ├─────┼─────┼─────┤
  a20→ │PE20 │PE21 │PE22 │ → East Output
       └─────┴─────┴─────┘
         ↓     ↓     ↓
    South Outputs (Data Passthrough)
```

## 3. Processing Element (PE) Architecture

### 3.1 PE State Machine

Each PE operates as a 4-state finite state machine:

```
IDLE ──inputs_valid_i──→ LOAD_DATA ──→ MAC_COMPUTE ──mac_done──→ OUTPUT ──→ IDLE
 ↑                                                                 │
 └─────────────────────────────────────────────────────────────────┘
 ↑
 └──accumulator_valid_i (for result draining)
```

**State Descriptions:**
- **IDLE**: Waiting for new data or accumulator drain signal
- **LOAD_DATA**: Capturing north_i (weight) and west_i (data) inputs
- **MAC_COMPUTE**: Performing multiply-accumulate operation
- **OUTPUT**: Forwarding data and optionally outputting accumulator result

### 3.2 PE Internal Data Flow

Each PE contains:
- **Input Buffers**: `buffered_north`, `buffered_west`
- **Accumulator Buffer**: `buffered_accumulator`
- **MAC Unit**: Dedicated multiply-accumulate hardware
- **Output Mux**: Selects between data passthrough and accumulator output

```
north_i ──┐    ┌─── MAC Unit ─── mac_result ──→ buffered_accumulator
          ├──→ │                                        │
         buffer └─ west_i (direct)                      │
          │                                             ↓
west_i ───┼────────────────────────────────────→ Output Mux ──→ east_o
          │                                             ↑
          └─────────────────────────────────────→ south_o
                                                select_accumulator_i
```

## 4. Input Queue Operation

### 4.1 Row Input Queue (West Side)

The row input queue distributes matrix A data to PE rows with precise timing:

**Initial State (t=0):**
```
PE Addresses: PE0→0, PE1→3, PE2→6  (base addresses for each row)
Data Ready:   [a00, -, -], [a10, -, -], [a20, -, -]
```

**Data Distribution Sequence:**
```
Clock 1: Release first column: a00→PE00, a10→PE10, a20→PE20
Clock 2: Wait for PE consumption (passthrough_valid feedback)
Clock 3: Release second column: a01→PE00, a11→PE10, a21→PE20
...
```

**Address Progression:**
```
PE0: 0 → 1 → 2  (sequential: a00, a01, a02)
PE1: 3 → 4 → 5  (sequential: a10, a11, a12)
PE2: 6 → 7 → 8  (sequential: a20, a21, a22)
```

### 4.2 Column Input Queue (North Side)

The column input queue distributes matrix B data to PE columns:

**Address Progression:**
```
PE0: 0 → 3 → 6  (column-wise: b00, b10, b20)
PE1: 1 → 4 → 7  (column-wise: b01, b11, b21)
PE2: 2 → 5 → 8  (column-wise: b02, b12, b22)
```

### 4.3 Passthrough Valid Mechanism

The input queues use a 2-cycle delayed feedback system:

```
PE generates passthrough_valid_o ──┐
                                  │ 2-cycle
                                  │ delay
                                  ↓
            Queue advances read_addr ←──┘
```

This delay ensures proper timing coordination between data availability and PE consumption.

## 5. Systolic Data Flow Progression

### 5.1 Wave-Front Propagation

Data flows through the array in diagonal wave-fronts. Here's the timing for our 3×3 example:

**Clock Cycle 1:**
```
inputs_valid propagation: PE00 gets valid
PE00: IDLE → LOAD_DATA (captures a00, b00)
```

**Clock Cycle 2:**
```
inputs_valid propagation: PE01, PE10 get valid
PE00: LOAD_DATA → MAC_COMPUTE (starts a00×b00)
PE01: IDLE → LOAD_DATA (captures a00, b01)
PE10: IDLE → LOAD_DATA (captures a10, b00)
```

**Clock Cycle 3:**
```
inputs_valid propagation: PE02, PE11, PE20 get valid
PE00: MAC_COMPUTE → OUTPUT (completes a00×b00, outputs a00→south, b00→east)
PE01: LOAD_DATA → MAC_COMPUTE (starts a00×b01)
PE10: LOAD_DATA → MAC_COMPUTE (starts a10×b00)
PE02: IDLE → LOAD_DATA (captures a00, b02)
PE11: IDLE → LOAD_DATA (captures a10, b01)
PE20: IDLE → LOAD_DATA (captures a20, b00)
```

### 5.2 Data Accumulation Pattern

Each PE accumulates products over multiple cycles:

**PE00 Computation Sequence:**
```
Cycle 1: acc = 0 + (a00 × b00)
Cycle 4: acc = (a00×b00) + (a01 × b10)
Cycle 7: acc = (a00×b00) + (a01×b10) + (a02 × b20) = Final Result C00
```

**PE11 Computation Sequence:**
```
Cycle 5: acc = 0 + (a10 × b01)
Cycle 8: acc = (a10×b01) + (a11 × b11)
Cycle 11: acc = (a10×b01) + (a11×b11) + (a12 × b21) = Final Result C11
```

## 6. Result Collection and Wave Control

### 6.1 Matrix Multiplication Completion Detection

The completion detection logic in the Mesh module monitors PE22 (bottom-right):

1. **Last Element Detection**: When `last_element_i` pulse reaches PE22 via horizontal propagation
2. **Processing Completion**: When PE22 generates `passthrough_valid_o` after processing its final element
3. **Done Signal**: Combination of both conditions generates `done_o`

### 6.2 Wave-Based Result Collection

Upon `done_o`, the wave control system initiates result collection:

**Wave Control State:**
```
start_wave = done_o & ~matrix_mult_done_ff  (edge detection)

Initial: col_shift = 3'b100, wave_active = 1
Clock 1: col_shift = 3'b010
Clock 2: col_shift = 3'b001
Clock 3: col_shift = 3'b000, wave_active = 0
```

**PE Selection for Each Wave:**
```
Wave 1 (col_shift[2]): PE02, PE12, PE22 → select_accumulator_i = 1
Wave 2 (col_shift[1]): PE01, PE11, PE21 → select_accumulator_i = 1
Wave 3 (col_shift[0]): PE00, PE10, PE20 → select_accumulator_i = 1
```

### 6.3 Result Output Sequence

**Wave 1 Output (Column 2):**
```
PE02 → east_o = C02 (accumulated result)
PE12 → east_o = C12 (accumulated result)
PE22 → east_o = C22 (accumulated result)
```

**Wave 2 Output (Column 1):**
```
PE01 → east_o = C01 (accumulated result)
PE11 → east_o = C11 (accumulated result)
PE21 → east_o = C21 (accumulated result)
```

**Wave 3 Output (Column 0):**
```
PE00 → east_o = C00 (accumulated result)
PE10 → east_o = C10 (accumulated result)
PE20 → east_o = C20 (accumulated result)
```

## 7. Accumulator Draining Mechanism

### 7.1 PE Drain State Transition

When `select_accumulator_i` is asserted for a PE in IDLE state:

```
IDLE state with select_accumulator_gated:
- east_o ← buffered_accumulator (output accumulated result)
- accumulator_valid_o ← 1 (signal valid accumulator output)
```

### 7.2 Drain Signal Propagation

The `accumulator_valid_o` signals propagate eastward:

```
PE02 accumulator_valid_o → PE01 accumulator_valid_i → PE00 accumulator_valid_i
PE12 accumulator_valid_o → PE11 accumulator_valid_i → PE10 accumulator_valid_i
PE22 accumulator_valid_o → PE21 accumulator_valid_i → PE20 accumulator_valid_i
```

When a PE receives `accumulator_valid_i` in IDLE state:
- Transitions directly to OUTPUT state
- Sets `accumulator_drain_flag = 1`
- Outputs `west_i` directly to `east_o` (passthrough mode)
- Generates `accumulator_valid_o = 1`

## 8. Output Collection System

### 8.1 Data Capture from East Boundary

The OutputSram module captures data from the rightmost column of PEs:

```
east_o[0] from PE02 → Result Memory
east_o[1] from PE12 → Result Memory
east_o[2] from PE22 → Result Memory
```

### 8.2 Collection Timing

Results are collected over 3 clock cycles corresponding to the wave progression:

```
Cycle 1: Collect C02, C12, C22
Cycle 2: Collect C01, C11, C21
Cycle 3: Collect C00, C10, C20
```

**Final Result Matrix Layout in Memory:**
```
Address 0: C02    Address 3: C01    Address 6: C00
Address 1: C12    Address 4: C11    Address 7: C10
Address 2: C22    Address 5: C21    Address 8: C20
```

## 9. Control Flow Summary

### 9.1 Complete Operation Sequence

1. **Initialization**: Load matrices into input queues
2. **Start Signal**: Assert `start_matrix_mult_i`
3. **Data Distribution**: Input queues begin feeding PEs based on passthrough_valid feedback
4. **Computation Phase**: PEs perform MAC operations in systolic fashion
5. **Completion Detection**: Monitor bottom-right PE for processing completion
6. **Wave Generation**: Initiate column-wise result collection
7. **Result Draining**: Collect accumulated results from each column
8. **Storage**: Store results in output memory for external access

### 9.2 Pipeline Characteristics

- **Latency**: ~9 clock cycles for 3×3 multiplication (3N cycles generally)
- **Throughput**: Results collected at 1 per clock cycle during collection phase
- **Overlapping**: Input distribution, computation, and result collection can overlap for back-to-back operations

## 10. Key Design Features

### 10.1 Flow Control
- Backpressure mechanism through passthrough_valid signals
- Prevents data corruption by ensuring proper PE readiness
- Maintains systolic timing relationships

### 10.2 Result Integrity
- Accumulator buffering prevents result corruption during collection
- Wave-based collection ensures all results are captured
- Last element tracking ensures computation completion

### 10.3 Scalability
- Parameterizable design supports arbitrary N×N dimensions
- Memory addressing scales automatically with array size
- Control logic adapts to different configurations

This architecture provides an efficient, pipelined solution for matrix multiplication with careful attention to timing, data flow, and result collection mechanisms.
