import argparse
import os
import struct

import numpy as np


def float_to_hex(f):
    """Convert a float32 to an 8-character hex string (big-endian)."""
    return "".join(f"{b:02x}" for b in struct.pack(">f", f))


def generate_test_vectors(
    rows_A,
    cols_A,
    cols_B,
    testbench_dir="testbenches",
    seed=None,
    matrix_type="random",
    value_range=(-1.0, 1.0),
    suffix="",  # <--- NEW: Allows adding _0, _1, etc. to filenames
):
    """
    Generate test vectors for matrix multiplication A * B = C
    """

    if seed is not None:
        np.random.seed(seed)

    # Create output directories if they don't exist
    os.makedirs(testbench_dir, exist_ok=True)

    # Generate Matrix A
    if matrix_type == "identity" and rows_A == cols_A:
        A = np.eye(rows_A, dtype=np.float32)
    elif matrix_type == "ones":
        A = np.ones((rows_A, cols_A), dtype=np.float32)
    elif matrix_type == "small_int":
        A = np.random.randint(-5, 6, size=(rows_A, cols_A)).astype(np.float32)
    else:  # random
        A = np.random.uniform(
            value_range[0], value_range[1], size=(rows_A, cols_A)
        ).astype(np.float32)

    # Generate Matrix B
    if matrix_type == "identity" and cols_A == cols_B:
        B = np.eye(cols_A, dtype=np.float32)
    elif matrix_type == "ones":
        B = np.ones((cols_A, cols_B), dtype=np.float32)
    elif matrix_type == "small_int":
        B = np.random.randint(-5, 6, size=(cols_A, cols_B)).astype(np.float32)
    else:  # random
        B = np.random.uniform(
            value_range[0], value_range[1], size=(cols_A, cols_B)
        ).astype(np.float32)

    # Compute matrix multiplication C = A * B
    C = np.matmul(A, B).astype(np.float32)

    # Write matrices to .mem files (row-major order)
    # <--- MODIFIED: Includes suffix in filename
    filenames = {
        "A": os.path.join(testbench_dir, f"matrixA{suffix}.mem"),
        "B": os.path.join(testbench_dir, f"matrixB{suffix}.mem"),
        "C": os.path.join(testbench_dir, f"matrixC{suffix}.mem"),
    }

    # Write Matrix A
    with open(filenames["A"], "w") as f:
        for val in A.flatten():
            f.write(float_to_hex(val) + "\n")

    # Write Matrix B
    with open(filenames["B"], "w") as f:
        for val in B.flatten():
            f.write(float_to_hex(val) + "\n")

    # Write Matrix C (result)
    with open(filenames["C"], "w") as f:
        for val in C.flatten():
            f.write(float_to_hex(val) + "\n")

    # Only print verbose details for the first one or if explicitly asked,
    # otherwise keep it clean.
    print(
        f"Generated Set{suffix}: A[{rows_A}x{cols_A}] * B[{cols_A}x{cols_B}] -> {filenames['C']}"
    )

    return A, B, C, filenames


def verify_multiplication(A, B, C, tolerance=1e-5, test_id=""):
    """Verify that C = A * B within tolerance"""
    expected_C = np.matmul(A, B)
    diff = np.abs(C - expected_C)
    max_error = np.max(diff)

    status = "PASSED" if max_error < tolerance else "FAILED"
    print(f"  [Verify {test_id}] Max Error: {max_error:.2e} -> {status}")

    return max_error < tolerance


def main():
    """Command line interface for test vector generation"""
    parser = argparse.ArgumentParser(
        description="Generate matrix multiplication test vectors"
    )
    parser.add_argument("--rows-A", type=int, default=4, help="Rows in matrix A")
    parser.add_argument("--cols-A", type=int, default=4, help="Columns in matrix A")
    parser.add_argument("--cols-B", type=int, default=4, help="Columns in matrix B")
    parser.add_argument(
        "--testbench-dir",
        type=str,
        default="testbenches",
        help="Directory for expected result matrix C",
    )
    parser.add_argument("--seed", type=int, default=42, help="Base Random seed")
    parser.add_argument(
        "--matrix-type",
        choices=["random", "identity", "ones", "small_int"],
        default="random",
        help="Type of matrices to generate",
    )
    parser.add_argument(
        "--min-val", type=float, default=-1.0, help="Minimum random value"
    )
    parser.add_argument(
        "--max-val", type=float, default=1.0, help="Maximum random value"
    )
    parser.add_argument(
        "--verify", action="store_true", help="Verify multiplication result"
    )
    # <--- NEW ARGUMENT
    parser.add_argument(
        "--num-tests", type=int, default=1, help="Number of test sets to generate"
    )

    args = parser.parse_args()

    print(f"Generating {args.num_tests} test set(s)...")
    print("-" * 40)

    for i in range(args.num_tests):
        # Determine suffix and seed for this iteration
        # If we only want 1 test, keep filename clean (e.g., matrixA.mem)
        # If we want >1 tests, append index (e.g., matrixA_0.mem)
        file_suffix = f"_{i}" if args.num_tests > 1 else ""

        # Increment seed so each test case is different but reproducible
        current_seed = args.seed + i

        # Generate vectors
        A, B, C, _ = generate_test_vectors(
            rows_A=args.rows_A,
            cols_A=args.cols_A,
            cols_B=args.cols_B,
            testbench_dir=args.testbench_dir,
            seed=current_seed,
            matrix_type=args.matrix_type,
            value_range=(args.min_val, args.max_val),
            suffix=file_suffix,
        )

        # Verify if requested
        if args.verify:
            verify_multiplication(A, B, C, test_id=str(i))

    print("-" * 40)
    print("Done.")


# Wrapper functions for quick testing within code
def generate_batch_test():
    """Generate 5 sets of 8x8 matrices"""
    print("Batch Generation Test...")
    base_seed = 100
    for i in range(5):
        generate_test_vectors(
            8, 8, 8, seed=base_seed + i, suffix=f"_{i}", matrix_type="random"
        )


if __name__ == "__main__":
    main()
