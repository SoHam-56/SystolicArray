import argparse
import os
import struct
import textwrap

import numpy as np

# ─────────────────────────────────────────────
#  Hex / Float helpers
# ─────────────────────────────────────────────


def float_to_hex(f):
    """Convert a float32 to an 8-character hex string (big-endian IEEE-754)."""
    return "".join(f"{b:02x}" for b in struct.pack(">f", f))


def hex_to_float(h):
    """Convert an 8-char big-endian hex string back to float32 (for verification display)."""
    return struct.unpack(">f", bytes.fromhex(h))[0]


# ─────────────────────────────────────────────
#  Pretty-print helpers
# ─────────────────────────────────────────────


def fmt_matrix(m, title="", indent=4, decimals=4):
    """Return a human-readable string for a 2-D numpy array."""
    pad = " " * indent
    lines = [f"{pad}{title}"] if title else []
    rows, cols = m.shape
    lines.append(f"{pad}Shape: {rows}×{cols}")
    lines.append(f"{pad}{'─' * (cols * (decimals + 7))}")
    for row in m:
        vals = "  ".join(f"{v:+.{decimals}f}" for v in row)
        lines.append(f"{pad}| {vals} |")
    lines.append(f"{pad}{'─' * (cols * (decimals + 7))}")
    return "\n".join(lines)


def fmt_hex_row(arr, cols_per_line=8, indent=4):
    """Print a flat array as grouped hex values."""
    pad = " " * indent
    hexvals = [float_to_hex(float(v)) for v in arr.flatten()]
    lines = []
    for i in range(0, len(hexvals), cols_per_line):
        chunk = "  ".join(hexvals[i : i + cols_per_line])
        lines.append(
            f"{pad}[{i:4d}..{min(i+cols_per_line-1, len(hexvals)-1):4d}]  {chunk}"
        )
    return "\n".join(lines)


def section(title, width=60):
    bar = "═" * width
    return f"\n{bar}\n  {title}\n{bar}"


# ─────────────────────────────────────────────
#  Core logic
# ─────────────────────────────────────────────


def get_sliding_windows(image, k_h, k_w, stride=1):
    """Extract sliding windows from a 2-D image."""
    rows, cols = image.shape
    windows, positions = [], []
    for y in range(0, rows - k_h + 1, stride):
        for x in range(0, cols - k_w + 1, stride):
            windows.append(image[y : y + k_h, x : x + k_w])
            positions.append((y, x))
    return windows, positions


def generate_convolution_test(
    img_h,
    img_w,
    kernel_size,
    stride=1,
    testbench_dir="testbenches/stimulus",
    debug_dir="testbenches/debug",
    seed=None,
    suffix="",
    debug=True,
    num_windows_to_show=3,  # how many windows to print in detail
):
    if seed is not None:
        np.random.seed(seed)

    os.makedirs(testbench_dir, exist_ok=True)
    if debug:
        os.makedirs(debug_dir, exist_ok=True)

    tag = suffix if suffix else "0"

    # ── 1. Generate image + kernel ───────────────────────────────────────
    image = np.random.uniform(-1.0, 1.0, size=(img_h, img_w)).astype(np.float32)
    kernel = np.random.uniform(-1.0, 1.0, size=(kernel_size, kernel_size)).astype(
        np.float32
    )

    windows, positions = get_sliding_windows(image, kernel_size, kernel_size, stride)
    num_windows = len(windows)

    out_h = (img_h - kernel_size) // stride + 1
    out_w = (img_w - kernel_size) // stride + 1

    # ── 2. Build flat streams ────────────────────────────────────────────
    stream_A, stream_B, stream_C = [], [], []
    results = []

    for w in windows:
        stream_A.extend(w.flatten())
        stream_B.extend(kernel.flatten())
        res = np.matmul(w, kernel)
        stream_C.extend(res.flatten())
        results.append(res)

    # ── 3. Write .mem files ──────────────────────────────────────────────
    def write_mem(fname, data):
        with open(fname, "w") as f:
            for val in data:
                f.write(float_to_hex(float(val)) + "\n")

    f_a = os.path.join(testbench_dir, f"matrixA{suffix}.mem")
    f_b = os.path.join(testbench_dir, f"matrixB{suffix}.mem")
    f_c = os.path.join(testbench_dir, f"matrixC{suffix}.mem")
    write_mem(f_a, stream_A)
    write_mem(f_b, stream_B)
    write_mem(f_c, stream_C)

    # ── 4. Debug report ──────────────────────────────────────────────────
    if not debug:
        print(f"  [Success] Written {len(stream_A)} elements per stream.")
        return

    dbg_lines = []

    dbg_lines.append(section(f"TEST SET {tag}  —  CONVOLUTION DEBUG REPORT"))
    dbg_lines.append(textwrap.dedent(f"""
    Configuration
    ─────────────
      Image shape   : {img_h} × {img_w}
      Kernel shape  : {kernel_size} × {kernel_size}
      Stride        : {stride}
      Output shape  : {out_h} × {out_w}  ({num_windows} windows)
      Seed          : {seed}

    Stream sizes (elements)
      matrixA{suffix}.mem  : {len(stream_A)}   ({num_windows} windows × {kernel_size*kernel_size} elements)
      matrixB{suffix}.mem  : {len(stream_B)}   ({num_windows} repeats × {kernel_size*kernel_size} elements)
      matrixC{suffix}.mem  : {len(stream_C)}   ({num_windows} results × {kernel_size*kernel_size} elements)

    How your testbench sees this
    ─────────────────────────────
      West  queue ← matrixA  (image patches, row-major)
      North queue ← matrixB  (kernel, repeated per patch)
      Expected    ← matrixC  (Window @ Kernel result per patch)

      SRAM layout: patches are concatenated in row-major scan order.
      Addr of patch p, element (r,c) = p*{kernel_size*kernel_size} + r*{kernel_size} + c
    """))

    # Full image
    dbg_lines.append(section("SOURCE IMAGE  (float)"))
    dbg_lines.append(fmt_matrix(image, title=f"Image [{img_h}×{img_w}]", decimals=4))

    # Full image hex dump
    dbg_lines.append(section("SOURCE IMAGE  (hex stream → matrixA prefix)"))
    dbg_lines.append("  First 64 hex values of matrixA (stream_A):")
    dbg_lines.append(fmt_hex_row(np.array(stream_A[:64]), cols_per_line=8))

    # Kernel
    dbg_lines.append(section("KERNEL  (float)"))
    dbg_lines.append(
        fmt_matrix(kernel, title=f"Kernel [{kernel_size}×{kernel_size}]", decimals=4)
    )

    dbg_lines.append(section("KERNEL  (hex — what repeats in matrixB)"))
    dbg_lines.append(fmt_hex_row(kernel, cols_per_line=kernel_size))

    # Per-window detail
    show_n = min(num_windows_to_show, num_windows)
    dbg_lines.append(section(f"WINDOW DETAIL  (first {show_n} of {num_windows})"))

    for idx in range(show_n):
        w = windows[idx]
        res = results[idx]
        py, px = positions[idx]
        base_addr = idx * kernel_size * kernel_size

        dbg_lines.append(
            f"\n  ┌─ Window {idx}  │  Image position: row={py}, col={px}  │  SRAM base addr: {base_addr}"
        )
        dbg_lines.append(
            fmt_matrix(
                w, title=f"Input patch [{kernel_size}×{kernel_size}]", decimals=4
            )
        )
        dbg_lines.append("")
        dbg_lines.append(
            fmt_matrix(
                res,
                title=f"Result = patch @ kernel  [{kernel_size}×{kernel_size}]",
                decimals=4,
            )
        )

        # Hex for this window's A stream
        dbg_lines.append(f"\n    matrixA hex (window {idx}):")
        dbg_lines.append(fmt_hex_row(w, cols_per_line=kernel_size))

        # Hex for this window's C stream
        dbg_lines.append(
            f"\n    matrixC hex (window {idx}  →  expected SRAM at addr {base_addr}..{base_addr + kernel_size*kernel_size - 1}):"
        )
        dbg_lines.append(fmt_hex_row(res, cols_per_line=kernel_size))

        # Element-level verification table (useful for manual checking)
        dbg_lines.append(f"\n    Element-level manual check (window {idx}):")
        dbg_lines.append(
            f"    {'Addr':>6}  {'(r,c)':>6}  {'Expected (float)':>18}  {'Expected (hex)':>10}  {'Dot-product breakdown'}"
        )
        dbg_lines.append(f"    {'─'*90}")
        for r in range(kernel_size):
            for c in range(kernel_size):
                addr = base_addr + r * kernel_size + c
                exp_f = res[r, c]
                exp_h = float_to_hex(float(exp_f))
                # dot product: window row r · kernel col c
                dot_terms = "  +  ".join(
                    f"({w[r,kk]:+.3f}×{kernel[kk,c]:+.3f})" for kk in range(kernel_size)
                )
                dbg_lines.append(
                    f"    {addr:6d}  ({r},{c})  {exp_f:+18.6f}  {exp_h:>10}  {dot_terms}"
                )

    # Full expected output reshaped as output feature map (first result element per window)
    dbg_lines.append(
        section("OUTPUT FEATURE MAP  (element [0,0] of each window result)")
    )
    output_map = np.array([results[i][0, 0] for i in range(num_windows)]).reshape(
        out_h, out_w
    )
    dbg_lines.append(
        "  Note: this shows only result[0][0] per window — the top-left element of each patch result."
    )
    dbg_lines.append(
        fmt_matrix(
            output_map, title=f"Partial output map [{out_h}×{out_w}]", decimals=4
        )
    )

    # Testbench read sequence hint
    dbg_lines.append(section("TESTBENCH READ SEQUENCE HINT"))
    dbg_lines.append(textwrap.dedent(f"""
    To manually verify window 0 in simulation:
      1. After 'complete' fires, set r_en=1
      2. Read addresses 0 to {kernel_size*kernel_size - 1}
      3. Compare each r_data against the hex values in window 0 matrixC block above

    To verify window N:
      base_addr = N * {kernel_size * kernel_size}
      Read addresses base_addr to base_addr + {kernel_size*kernel_size - 1}

    Quick spot-check (window 0, element [0,0]):
      Expected float : {results[0][0,0]:+.6f}
      Expected hex   : {float_to_hex(float(results[0][0,0]))}
      SRAM addr      : 0

    {(
        f"Quick spot-check (window 1, element [0,0]):\\n"
        f"      Expected float : {results[1][0,0]:+.6f}\\n"
        f"      Expected hex   : {float_to_hex(float(results[1][0,0]))}\\n"
        f"      SRAM addr      : {kernel_size * kernel_size}"
    ) if num_windows > 1 else "    (Only 1 window — no window 1 spot-check)"}
    """))

    # Write debug file
    dbg_path = os.path.join(debug_dir, f"debug{suffix}.txt")
    report = "\n".join(dbg_lines)
    with open(dbg_path, "w") as f:
        f.write(report)

    print(report)
    print(f"\n  [Files] .mem → {testbench_dir}/  |  debug → {dbg_path}")


# ─────────────────────────────────────────────
#  CLI
# ─────────────────────────────────────────────


def main():
    parser = argparse.ArgumentParser(
        description="Generate convolution-style MatMul test vectors with debug output"
    )
    parser.add_argument("--img-h", type=int, default=8, help="Image height")
    parser.add_argument("--img-w", type=int, default=8, help="Image width")
    parser.add_argument("--kernel", type=int, default=4, help="Kernel size (square)")
    parser.add_argument(
        "--stride", type=int, default=4, help="Stride (= kernel for non-overlapping)"
    )
    parser.add_argument(
        "--num-tests", type=int, default=1, help="Number of test sets to generate"
    )
    parser.add_argument(
        "--dir",
        type=str,
        default="testbenches/stimulus",
        help="Output dir for .mem files",
    )
    parser.add_argument(
        "--debug-dir",
        type=str,
        default="testbenches/debug",
        help="Output dir for debug reports",
    )
    parser.add_argument(
        "--no-debug", action="store_true", help="Skip debug report generation"
    )
    parser.add_argument(
        "--show-windows",
        type=int,
        default=3,
        help="How many windows to detail in debug report",
    )
    args = parser.parse_args()

    print("════════════════════════════════════════════════")
    print("  Conv-style MatMul Test Generator")
    print("════════════════════════════════════════════════")
    print(f"  Image  : {args.img_h}×{args.img_w}")
    print(f"  Kernel : {args.kernel}×{args.kernel}")
    print(f"  Stride : {args.stride}")
    print(f"  Sets   : {args.num_tests}")
    print(f"  Debug  : {'off' if args.no_debug else 'on'}")
    print("════════════════════════════════════════════════")

    for i in range(args.num_tests):
        suffix = f"_{i}" if args.num_tests > 1 else ""
        generate_convolution_test(
            img_h=args.img_h,
            img_w=args.img_w,
            kernel_size=args.kernel,
            stride=args.stride,
            testbench_dir=args.dir,
            debug_dir=args.debug_dir,
            seed=42 + i,
            suffix=suffix,
            debug=not args.no_debug,
            num_windows_to_show=args.show_windows,
        )

    print("\nDone.")


if __name__ == "__main__":
    main()
