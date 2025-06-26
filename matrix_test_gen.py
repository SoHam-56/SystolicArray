import numpy as np
import struct
import argparse
import os

def float_to_hex(f):
    """Convert a float32 to an 8-character hex string (big-endian)."""
    return ''.join(f'{b:02x}' for b in struct.pack('>f', f))

def generate_test_vectors(rows_A, cols_A, cols_B, src_dir="src", testbench_dir="testbench", seed=None, matrix_type="random", value_range=(-1.0, 1.0)):
    """
    Generate test vectors for matrix multiplication A * B = C

    Parameters:
    - rows_A: Number of rows in matrix A
    - cols_A: Number of columns in matrix A (must equal rows in matrix B)
    - cols_B: Number of columns in matrix B
    - src_dir: Directory to save input matrices A and B (.mem files)
    - testbench_dir: Directory to save expected result matrix C (.mem file)
    - seed: Random seed for reproducible results
    - matrix_type: "random", "identity", "ones", "small_int"
    - value_range: Tuple (min, max) for random values
    """

    if seed is not None:
        np.random.seed(seed)

    # Create output directories if they don't exist
    os.makedirs(src_dir, exist_ok=True)
    os.makedirs(testbench_dir, exist_ok=True)

    # Generate Matrix A
    if matrix_type == "identity" and rows_A == cols_A:
        A = np.eye(rows_A, dtype=np.float32)
    elif matrix_type == "ones":
        A = np.ones((rows_A, cols_A), dtype=np.float32)
    elif matrix_type == "small_int":
        A = np.random.randint(-5, 6, size=(rows_A, cols_A)).astype(np.float32)
    else:  # random
        A = np.random.uniform(value_range[0], value_range[1],
                             size=(rows_A, cols_A)).astype(np.float32)

    # Generate Matrix B (always random unless specified)
    if matrix_type == "identity" and cols_A == cols_B:
        B = np.eye(cols_A, dtype=np.float32)
    elif matrix_type == "ones":
        B = np.ones((cols_A, cols_B), dtype=np.float32)
    elif matrix_type == "small_int":
        B = np.random.randint(-5, 6, size=(cols_A, cols_B)).astype(np.float32)
    else:  # random
        B = np.random.uniform(value_range[0], value_range[1],
                             size=(cols_A, cols_B)).astype(np.float32)

    # Compute matrix multiplication C = A * B
    C = np.matmul(A, B).astype(np.float32)

    # Write matrices to .mem files (row-major order)
    filenames = {
        'A': os.path.join(src_dir, 'matrixA.mem'),
        'B': os.path.join(src_dir, 'matrixB.mem'),
        'C': os.path.join(testbench_dir, 'matrixC.mem')
    }

    # Write Matrix A
    with open(filenames['A'], 'w') as f:
        for val in A.flatten():  # Row-major flattening
            f.write(float_to_hex(val) + '\n')

    # Write Matrix B
    with open(filenames['B'], 'w') as f:
        for val in B.flatten():  # Row-major flattening
            f.write(float_to_hex(val) + '\n')

    # Write Matrix C (result)
    with open(filenames['C'], 'w') as f:
        for val in C.flatten():  # Row-major flattening
            f.write(float_to_hex(val) + '\n')

    # Print summary
    print(f"Generated test vectors:")
    print(f"  Matrix A: {rows_A}x{cols_A} -> {filenames['A']}")
    print(f"  Matrix B: {cols_A}x{cols_B} -> {filenames['B']}")
    print(f"  Matrix C: {rows_A}x{cols_B} -> {filenames['C']}")
    print(f"  Total elements: A={rows_A*cols_A}, B={cols_A*cols_B}, C={rows_A*cols_B}")

    # Display preview of matrices
    print(f"\nPreview (first 5 elements of each matrix):")
    print(f"Matrix A: {[f'{val:.4f}' for val in A.flatten()[:5]]}")
    print(f"Matrix B: {[f'{val:.4f}' for val in B.flatten()[:5]]}")
    print(f"Matrix C: {[f'{val:.4f}' for val in C.flatten()[:5]]}")

    # Display hex preview
    print(f"\nHex preview (first 3 elements):")
    print(f"Matrix A: {[float_to_hex(val) for val in A.flatten()[:3]]}")
    print(f"Matrix B: {[float_to_hex(val) for val in B.flatten()[:3]]}")
    print(f"Matrix C: {[float_to_hex(val) for val in C.flatten()[:3]]}")

    return A, B, C, filenames

def verify_multiplication(A, B, C, tolerance=1e-5):
    """Verify that C = A * B within tolerance"""
    expected_C = np.matmul(A, B)
    diff = np.abs(C - expected_C)
    max_error = np.max(diff)

    print(f"\nVerification:")
    print(f"  Maximum error: {max_error:.2e}")
    print(f"  Tolerance: {tolerance:.2e}")
    print(f"  Test {'PASSED' if max_error < tolerance else 'FAILED'}")

    return max_error < tolerance

def main():
    """Command line interface for test vector generation"""
    parser = argparse.ArgumentParser(description='Generate matrix multiplication test vectors')
    parser.add_argument('--rows-A', type=int, default=4, help='Rows in matrix A')
    parser.add_argument('--cols-A', type=int, default=4, help='Columns in matrix A')
    parser.add_argument('--cols-B', type=int, default=4, help='Columns in matrix B')
    parser.add_argument('--src-dir', type=str, default='src', help='Directory for input matrices A and B')
    parser.add_argument('--testbench-dir', type=str, default='testbenches', help='Directory for expected result matrix C')
    parser.add_argument('--seed', type=int, default=42, help='Random seed')
    parser.add_argument('--matrix-type', choices=['random', 'identity', 'ones', 'small_int'], default='random', help='Type of matrices to generate')
    parser.add_argument('--min-val', type=float, default=-1.0, help='Minimum random value')
    parser.add_argument('--max-val', type=float, default=1.0, help='Maximum random value')
    parser.add_argument('--verify', action='store_true', help='Verify multiplication result')

    args = parser.parse_args()

    # Generate test vectors
    A, B, C, filenames = generate_test_vectors(
        rows_A=args.rows_A,
        cols_A=args.cols_A,
        cols_B=args.cols_B,
        src_dir=args.src_dir,
        testbench_dir=args.testbench_dir,
        seed=args.seed,
        matrix_type=args.matrix_type,
        value_range=(args.min_val, args.max_val)
    )

    # Verify if requested
    if args.verify:
        verify_multiplication(A, B, C)

# Example usage functions
def generate_small_test():
    """Generate a small 4x4 test case for debugging"""
    print("Generating 4x4 test case...")
    generate_test_vectors(4, 4, 4, seed=42, matrix_type="small_int")

def generate_medium_test():
    """Generate a medium 16x16 test case"""
    print("Generating 16x16 test case...")
    generate_test_vectors(16, 16, 16, seed=123, matrix_type="random")

def generate_large_test():
    """Generate a large 64x64 test case like your original"""
    print("Generating 64x64 test case...")
    generate_test_vectors(64, 64, 64, seed=456, matrix_type="random")

def generate_rectangular_test():
    """Generate rectangular matrices (8x12) * (12x6)"""
    print("Generating rectangular test case...")
    generate_test_vectors(8, 12, 6, seed=789, matrix_type="random")

if __name__ == "__main__":
    # If run as script, use command line interface
    main()

    # Uncomment below to run specific test cases
    # generate_small_test()
    # generate_medium_test()
    # generate_large_test()
    # generate_rectangular_test()
