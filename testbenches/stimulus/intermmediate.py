import struct
import sys

import numpy as np

MATRIX_SIZE = 4  # Global Matrix Size (M)
TILE_SIZE = 2  # Tile Size (N)

DATA_TYPE = (
    "float"  # Data Interpretation: 'int' (signed 32-bit) or 'float' (IEEE-754 FP32)
)

FILE_A = "matrixA.mem"
FILE_B = "matrixB.mem"
OUTPUT_FILE = "debug_intermediates.txt"


def val_to_hex(val, dtype):
    """Converts a number (float or int) back to an 8-char Hex string."""
    if dtype == "float":
        try:
            packed = struct.pack("!f", val)
            return packed.hex()
        except:
            return "00000000"
    else:
        # Handle signed 32-bit integer
        val = int(val)
        if val < 0:
            val = (val + (1 << 32)) & 0xFFFFFFFF
        return f"{val:08x}"


def hex_to_val(hex_str, dtype):
    """Converts a hex string to the specified data type value."""
    hex_str = hex_str.strip()
    if not hex_str:
        return 0
    hex_str = hex_str.zfill(8)

    if dtype == "float":
        try:
            return struct.unpack("!f", bytes.fromhex(hex_str))[0]
        except:
            return 0.0
    else:
        try:
            val = int(hex_str, 16)
            if val & 0x80000000:
                return val - 0x100000000
            return val
        except:
            return 0


def load_matrix_from_mem(filename, size, dtype):
    """Reads a .mem file and returns a 2D numpy array."""
    data = []
    print(f"Loading {filename}...")
    try:
        with open(filename, "r") as f:
            for line in f:
                line = line.split("//")[0].strip()
                if line:
                    parts = line.split()
                    for part in parts:
                        data.append(hex_to_val(part, dtype))
    except FileNotFoundError:
        print(f"Error: File {filename} not found.")
        sys.exit(1)

    expected_len = size * size
    if len(data) < expected_len:
        print(f"Warning: {filename} under-filled. Padding with 0.")
        data.extend([0] * (expected_len - len(data)))
    elif len(data) > expected_len:
        data = data[:expected_len]

    return np.array(data).reshape(size, size)


def format_matrix_hex(matrix, dtype, indent="    "):
    """Formats a matrix showing only Hex values."""
    rows, cols = matrix.shape
    lines = []
    for r in range(rows):
        row_str = []
        for c in range(cols):
            val = matrix[r, c]
            h_str = val_to_hex(val, dtype)
            row_str.append(f"{h_str:>8s}")
        lines.append(indent + "  ".join(row_str))
    return "\n".join(lines)


def main():
    print(
        f"Processing... Matrix: {MATRIX_SIZE}x{MATRIX_SIZE}, Tile: {TILE_SIZE}x{TILE_SIZE}"
    )
    print(f"Mode: Fully Parallel (P^3 Tiles)")
    print(f"Writing output to: {OUTPUT_FILE}")

    A = load_matrix_from_mem(FILE_A, MATRIX_SIZE, DATA_TYPE)
    B = load_matrix_from_mem(FILE_B, MATRIX_SIZE, DATA_TYPE)

    P = MATRIX_SIZE // TILE_SIZE
    C_global = np.zeros((MATRIX_SIZE, MATRIX_SIZE))

    with open(OUTPUT_FILE, "w") as f:
        f.write(f"SYSTOLIC MESH (PARALLEL MODE) DEBUG LOG\n")
        f.write(
            f"Global: {MATRIX_SIZE}x{MATRIX_SIZE} | Tile: {TILE_SIZE}x{TILE_SIZE} | Type: {DATA_TYPE}\n"
        )
        f.write(f"Total Tiles: {P}x{P}x{P} = {P**3}\n")
        f.write("=" * 80 + "\n\n")

        # Loop through target output blocks (i, j)
        for i in range(P):
            for j in range(P):
                f.write(f"{'='*80}\n")
                f.write(
                    f"CALCULATING OUTPUT BLOCK C[{i},{j}] (Summation of Depth Dimension)\n"
                )
                f.write(f"{'='*80}\n")

                # Buffer for spatial summation of this block
                spatial_sum_block = np.zeros((TILE_SIZE, TILE_SIZE))

                # Iterate through the Depth Dimension 'k' (The parallel tiles)
                for k in range(P):
                    # 1. Slice Inputs for Tile[i][j][k]
                    # Tile uses Row 'i' from A (col 'k') and Col 'j' from B (row 'k')
                    row_start_A = i * TILE_SIZE
                    col_start_A = k * TILE_SIZE
                    block_A = A[
                        row_start_A : row_start_A + TILE_SIZE,
                        col_start_A : col_start_A + TILE_SIZE,
                    ]

                    row_start_B = k * TILE_SIZE
                    col_start_B = j * TILE_SIZE
                    block_B = B[
                        row_start_B : row_start_B + TILE_SIZE,
                        col_start_B : col_start_B + TILE_SIZE,
                    ]

                    # 2. Compute Partial Product (What this specific tile outputs)
                    partial_product = np.dot(block_A, block_B)

                    # 3. Add to spatial sum
                    spatial_sum_block += partial_product

                    # 4. Log Tile Details
                    f.write(f"\n[Tile ({i}, {j}, {k})] Contribution:\n")
                    f.write(f"  Input West (A[{i},{k}]):\n")
                    f.write(
                        f"{format_matrix_hex(block_A, DATA_TYPE, indent='      ')}\n"
                    )

                    f.write(f"  Input North (B[{k},{j}]):\n")
                    f.write(
                        f"{format_matrix_hex(block_B, DATA_TYPE, indent='      ')}\n"
                    )

                    f.write(f"  -> Partial Result:\n")
                    f.write(
                        f"{format_matrix_hex(partial_product, DATA_TYPE, indent='      ')}\n"
                    )
                    f.write("-" * 40 + "\n")

                # 5. Log Final Spatial Sum for this Block
                f.write(f"\n*** SPATIAL SUM for BLOCK C[{i},{j}] ***\n")
                f.write(
                    f"{format_matrix_hex(spatial_sum_block, DATA_TYPE, indent='    ')}\n"
                )
                f.write("\n")

                # 6. Store in Global C for final readout
                row_start_C = i * TILE_SIZE
                col_start_C = j * TILE_SIZE
                C_global[
                    row_start_C : row_start_C + TILE_SIZE,
                    col_start_C : col_start_C + TILE_SIZE,
                ] = spatial_sum_block

        f.write(f"\n{'='*80}\nFINAL RESULT MATRIX (Global C)\n{'='*80}\n")
        f.write(format_matrix_hex(C_global, DATA_TYPE, indent="  "))
        f.write("\n")

    print(f"Done! Check {OUTPUT_FILE}")


if __name__ == "__main__":
    main()
