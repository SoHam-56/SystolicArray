"""
gen_conv_im2col.py  —  Single-channel 2D convolution via im2col for SystolicMesh
==================================================================================

Maps a 2D convolution to one square matrix multiply so the existing SystolicMesh
testbench and .mem infrastructure can be used without modification.

Layout
------
  Image   : H × W  (single channel, float32)
  Kernel  : K × K  (single filter, float32)
  Stride  : S       (default = K, non-overlapping patches)

  Patches : P = ((H-K)//S + 1) * ((W-K)//S + 1)  output positions
  Constraint: P == K*K == MATRIX_SIZE  (all must be equal for square matmul)

  A  [P × P]  — each row is one flattened patch  (im2col output)
  B  [P × P]  — kernel.flatten() repeated in every column
  C  [P × P]  — C[i, j] = dot(patch_i, kernel) for all j
                Conv result for position i  =  C[i, 0]  =  SRAM[i * P]

TB parameters to use
---------------------
  MATRIX_SIZE = P   (= number of patches = kernel elements = K*K)
  TILE_SIZE   = any valid divisor of MATRIX_SIZE
  NUM_TEST_SETS as generated

Usage
-----
  python gen_conv_im2col.py                          # defaults
  python gen_conv_im2col.py --img 16 --kernel 4      # 16x16 image, 4x4 kernel
  python gen_conv_im2col.py --num-tests 3 --no-debug
"""

import argparse
import os
import struct
import textwrap

import numpy as np


# ─────────────────────────────────────────────
#  Helpers
# ─────────────────────────────────────────────

def float_to_hex(f: float) -> str:
    return "".join(f"{b:02x}" for b in struct.pack(">f", f))


def hex_to_float(h: str) -> float:
    return struct.unpack(">f", bytes.fromhex(h))[0]


def write_mem(path: str, data):
    with open(path, "w") as f:
        for v in data:
            f.write(float_to_hex(float(v)) + "\n")


def fmt_matrix(m, title="", indent=4, decimals=4):
    pad = " " * indent
    rows, cols = m.shape
    bar = "─" * (cols * (decimals + 8))
    lines = ([f"{pad}{title}  [{rows}×{cols}]"] if title else []) + [f"{pad}{bar}"]
    for row in m:
        lines.append(pad + "| " + "  ".join(f"{v:+.{decimals}f}" for v in row) + " |")
    lines.append(f"{pad}{bar}")
    return "\n".join(lines)


def fmt_hex_block(arr, cols=8, indent=4):
    pad = " " * indent
    flat = [float_to_hex(float(v)) for v in np.asarray(arr).flatten()]
    lines = []
    for i in range(0, len(flat), cols):
        chunk = "  ".join(flat[i:i + cols])
        lines.append(f"{pad}[{i:4d}..{min(i+cols-1,len(flat)-1):4d}]  {chunk}")
    return "\n".join(lines)


def section(title, width=62):
    return f"\n{'═'*width}\n  {title}\n{'═'*width}"


# ─────────────────────────────────────────────
#  im2col
# ─────────────────────────────────────────────

def im2col(image: np.ndarray, K: int, stride: int):
    """
    Extract non-overlapping (or strided) K×K patches from a 2D image.
    Returns:
      patches   — list of K×K arrays in row-major scan order
      positions — list of (row, col) top-left corners
    """
    H, W = image.shape
    patches, positions = [], []
    for r in range(0, H - K + 1, stride):
        for c in range(0, W - K + 1, stride):
            patches.append(image[r:r+K, c:c+K].copy())
            positions.append((r, c))
    return patches, positions


# ─────────────────────────────────────────────
#  Core generator
# ─────────────────────────────────────────────

def generate(
    img_size: int,
    kernel_size: int,
    stride: int,
    stim_dir: str,
    debug_dir: str,
    seed: int,
    suffix: str,
    debug: bool,
    show_patches: int,
):
    np.random.seed(seed)
    os.makedirs(stim_dir,  exist_ok=True)
    os.makedirs(debug_dir, exist_ok=True)

    K   = kernel_size
    P   = K * K          # flattened patch length = matrix dimension

    # ── Compute patch count ───────────────────────────────────────────────
    out_side    = (img_size - K) // stride + 1
    num_patches = out_side * out_side
    padded      = num_patches < P   # True when we need zero-padding

    if num_patches > P:
        raise ValueError(
            f"num_patches={num_patches} > P={P}: too many patches for one pass.\n"
            f"Increase kernel size or reduce image/stride to get num_patches ≤ {P}."
        )

    if padded:
        pad_rows = P - num_patches
        print(f"  [Pad] {num_patches} real patches < P={P}  →  "
              f"padding A with {pad_rows} zero rows  "
              f"(utilisation: {num_patches}/{P} = {100*num_patches//P}%)")

    # ── Generate data ─────────────────────────────────────────────────────
    image  = np.random.uniform(-1.0, 1.0, (img_size, img_size)).astype(np.float32)
    kernel = np.random.uniform(-1.0, 1.0, (K, K)).astype(np.float32)

    patches, positions = im2col(image, K, stride)

    # ── Build A, B, C ─────────────────────────────────────────────────────
    # A [P×P] : rows 0..num_patches-1 = real patches, rest = zeros
    real_rows = np.stack([p.flatten() for p in patches], axis=0).astype(np.float32)
    if padded:
        A = np.zeros((P, P), dtype=np.float32)
        A[:num_patches] = real_rows
    else:
        A = real_rows   # already P×P when num_patches == P

    # B [P×P] : every column = kernel.flatten()
    k_vec = kernel.flatten()                                        # P,
    B     = np.tile(k_vec[:, np.newaxis], (1, P)).astype(np.float32)  # P×P

    # C [P×P] : A @ B
    #   real rows:   C[i,j] = dot(patch_i, kernel)  for i < num_patches
    #   padded rows: C[i,j] = 0                      for i >= num_patches
    C = (A @ B).astype(np.float32)

    # Conv ground truth: C[i, 0]  for i in 0..num_patches-1
    conv_out = C[:num_patches, 0].reshape(out_side, out_side)

    # ── Write .mem files ──────────────────────────────────────────────────
    fa = os.path.join(stim_dir, f"matrixA{suffix}.mem")
    fb = os.path.join(stim_dir, f"matrixB{suffix}.mem")
    fc = os.path.join(stim_dir, f"matrixC{suffix}.mem")
    write_mem(fa, A.flatten())
    write_mem(fb, B.flatten())
    write_mem(fc, C.flatten())

    util_pct = 100 * num_patches // P
    print(f"  ✓ MATRIX_SIZE={P}  |  {num_patches} real patches"
          f"{f' + {P-num_patches} zero rows' if padded else ''}  |  "
          f"utilisation {util_pct}%  |  A,B,C each {P*P} elements  →  {stim_dir}/")

    if not debug:
        return P   # return MATRIX_SIZE for caller

    # ─────────────────────────────────────────────────────────────────────
    #  Debug report
    # ─────────────────────────────────────────────────────────────────────
    lines = []
    lines.append(section("CONVOLUTION im2col DEBUG REPORT"))
    pad_note = (f"YES — {P - num_patches} zero rows added to A"
                if padded else "No — matrix fully utilised")
    pad_rows_note = (f"rows {num_patches}..{P-1} = zeros (padding)"
                     if padded else "(all rows real)")
    c_pad_note = (f"\n                   rows {num_patches}..{P-1} = zeros (from padded A)"
                  if padded else "")
    valid_tiles = ', '.join(str(2**i) for i in range(1, P.bit_length()) if P % (2**i) == 0)
    lines.append(f"""
    Configuration
    ─────────────
      Image         : {img_size} × {img_size}  (single channel)
      Kernel        : {K} × {K}
      Stride        : {stride}
      Output map    : {out_side} × {out_side}  ({num_patches} positions)
      Seed          : {seed}
      Padding mode  : {pad_note}
      Utilisation   : {num_patches}/{P} rows = {100*num_patches//P}%

    Matrix dimensions (MATRIX_SIZE = {P})
    ──────────────────────────────────────
      A  [{P}×{P}]  rows 0..{num_patches-1} = real patches
                   {pad_rows_note}
      B  [{P}×{P}]  kernel.flatten() repeated in every column
      C  [{P}×{P}]  A @ B
                   rows 0..{num_patches-1} = conv results{c_pad_note}

    Testbench parameters to use
    ────────────────────────────
      MATRIX_SIZE  = {P}
      TILE_SIZE    = any power-of-2 divisor of {P}
                     e.g. {valid_tiles}
      NUM_TEST_SETS = (as generated)

    How to read the convolution result from SRAM
    ─────────────────────────────────────────────
      Conv output for patch i  =  SRAM address  i × {P}
      Only addresses i = 0..{num_patches-1} are meaningful.
      {"Addresses i = " + str(num_patches) + ".." + str(P-1) + " read back zero (padded rows)." if padded else ""}

      Output map addresses:
    """)

    # Print address table for output map
    for r in range(out_side):
        row_addrs = [f"{(r*out_side + c)*P:4d}" for c in range(out_side)]
        lines.append(f"      row {r}: SRAM[{', '.join(row_addrs)}]")

    # Image
    lines.append(section("SOURCE IMAGE"))
    lines.append(fmt_matrix(image, "Image"))

    # Kernel
    lines.append(section("KERNEL"))
    lines.append(fmt_matrix(kernel, "Kernel"))
    lines.append(f"\n    Kernel hex (= every column of matrixB):")
    lines.append(fmt_hex_block(k_vec, cols=K))

    # Matrix A
    lines.append(section("MATRIX A  (im2col — rows are flattened patches)"))
    lines.append(fmt_matrix(A, "A"))
    lines.append(f"\n    matrixA.mem hex (row-major):")
    lines.append(fmt_hex_block(A, cols=P))

    # Matrix B
    lines.append(section("MATRIX B  (kernel repeated across columns)"))
    lines.append(fmt_matrix(B, "B"))

    # Convolution output map
    lines.append(section("CONVOLUTION OUTPUT MAP  (expected)"))
    lines.append(fmt_matrix(conv_out, f"Conv output [{out_side}×{out_side}]"))
    lines.append(f"\n    How this maps to SRAM (reading address i×{P}):")
    for r in range(out_side):
        for c in range(out_side):
            i    = r * out_side + c
            addr = i * P
            val  = conv_out[r, c]
            h    = float_to_hex(float(val))
            lines.append(f"      output[{r},{c}]  patch {i:2d}  SRAM[{addr:4d}]  "
                         f"{val:+.6f}  {h}")

    # Per-patch detail
    show_n = min(show_patches, num_patches)
    lines.append(section(f"PATCH DETAIL  (first {show_n} of {num_patches})"))
    for idx in range(show_n):
        r0, c0 = positions[idx]
        p      = patches[idx]
        result = float(C[idx, 0])
        addr   = idx * P
        lines.append(f"\n  ┌─ Patch {idx}  │  image[{r0}:{r0+K}, {c0}:{c0+K}]  "
                     f"│  SRAM addr {addr}")
        lines.append(fmt_matrix(p, "Patch"))
        lines.append(f"\n    Flattened (= row {idx} of A):")
        lines.append(fmt_hex_block(p.flatten(), cols=K))
        dot_terms = "  +  ".join(
            f"({p.flatten()[i]:+.3f}×{k_vec[i]:+.3f})" for i in range(P)
        )
        lines.append(f"\n    dot(patch, kernel) = {result:+.6f}  "
                     f"({float_to_hex(result)})")
        lines.append(f"    Breakdown: {dot_terms}")
        lines.append(f"\n    Expected SRAM[{addr}] = {float_to_hex(result)}  "
                     f"({result:+.6f})")

    # matrixC hex
    lines.append(section("MATRIX C  (expected SRAM content)"))
    lines.append(fmt_matrix(C, "C  (C[i,*] = conv output for patch i, repeated)"))
    lines.append(f"\n    matrixC.mem hex (row-major, full {P*P} elements):")
    lines.append(fmt_hex_block(C, cols=P))

    # Spot-checks
    lines.append(section("QUICK SPOT-CHECKS FOR WAVEFORM/MANUAL VERIFICATION"))
    spot_indices = list(range(min(4, num_patches)))
    for idx in spot_indices:
        addr = idx * P
        val  = float(C[idx, 0])
        h    = float_to_hex(val)
        r0, c0 = positions[idx]
        lines.append(f"  Patch {idx:2d}  output[{r0//stride},{c0//stride}]  "
                     f"→  SRAM[{addr:4d}]  =  {h}  ({val:+.6f})")

    report = "\n".join(lines)
    dbg_path = os.path.join(debug_dir, f"conv_debug{suffix}.txt")
    with open(dbg_path, "w") as f:
        f.write(report)

    print(report)
    print(f"\n  Debug report → {dbg_path}")

    return P   # MATRIX_SIZE


# ─────────────────────────────────────────────
#  CLI
# ─────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(
        description="Generate im2col conv test vectors for SystolicMesh"
    )
    parser.add_argument("--img",        type=int, default=16,
                        help="Image size (square, default 16)")
    parser.add_argument("--kernel",     type=int, default=4,
                        help="Kernel size (square, default 4)")
    parser.add_argument("--stride",     type=int, default=None,
                        help="Stride (default = kernel size → non-overlapping)")
    parser.add_argument("--num-tests",  type=int, default=1,
                        help="Number of random test sets")
    parser.add_argument("--dir",        type=str,
                        default="testbenches/stimulus",
                        help="Output dir for .mem files")
    parser.add_argument("--debug-dir",  type=str,
                        default="testbenches/debug",
                        help="Output dir for debug reports")
    parser.add_argument("--no-debug",   action="store_true",
                        help="Skip debug report")
    parser.add_argument("--show-patches", type=int, default=2,
                        help="Number of patches to detail in debug report")
    args = parser.parse_args()

    stride = args.stride if args.stride is not None else args.kernel
    K      = args.kernel
    P      = K * K

    print("════════════════════════════════════════════════")
    print("  SystolicMesh  —  Conv im2col Test Generator")
    print("════════════════════════════════════════════════")
    print(f"  Image  : {args.img} × {args.img}")
    print(f"  Kernel : {K} × {K}")
    print(f"  Stride : {stride}")
    print(f"  MATRIX_SIZE will be : {P}")
    print(f"  Sets   : {args.num_tests}")
    print(f"  Debug  : {'off' if args.no_debug else 'on'}")
    print("════════════════════════════════════════════════")

    matrix_size = None
    for i in range(args.num_tests):
        suffix = f"_{i}" if args.num_tests > 1 else ""
        print(f"\n--- Test Set {i} ---")
        matrix_size = generate(
            img_size    = args.img,
            kernel_size = K,
            stride      = stride,
            stim_dir    = args.dir,
            debug_dir   = args.debug_dir,
            seed        = 42 + i,
            suffix      = suffix,
            debug       = not args.no_debug,
            show_patches= args.show_patches,
        )

    print("\n════════════════════════════════════════════════")
    print("  To run in your testbench:")
    print(f"    MATRIX_SIZE  = {matrix_size}")
    valid_tiles = [2**i for i in range(1, matrix_size.bit_length())
                   if matrix_size % (2**i) == 0]
    print(f"    TILE_SIZE    = one of {valid_tiles}")
    print(f"    NUM_TEST_SETS = {args.num_tests}")
    print("  Then run:  make")
    print("════════════════════════════════════════════════")
    print("\nDone.")


if __name__ == "__main__":
    main()
