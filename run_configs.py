#!/usr/bin/env python3
"""
run_configs.py — Multi-configuration test runner for SystolicMesh
Generates test data once, then compiles and runs the simulation for each
TILE_SIZE configuration, collecting pass/fail and tolerance stats.

Usage:
    python run_configs.py                        # default: 8x8 image, tile sizes [2,4,8]
    python run_configs.py --matrix 16            # 16x16, tile sizes [2,4,8,16]
    python run_configs.py --tiles 2 4            # only tile sizes 2 and 4
    python run_configs.py --num-tests 3          # 3 random test sets per config
    python run_configs.py --keep-going           # don't stop on first failure
"""

import argparse
import os
import re
import subprocess
import sys
import time

# ─────────────────────────────────────────────
#  Paths  (adjust if your layout differs)
# ─────────────────────────────────────────────
PROJECT_ROOT  = os.path.dirname(os.path.abspath(__file__))
GEN_SCRIPT    = os.path.join(PROJECT_ROOT, "gen_conv_tests.py")
VERILATOR_DIR = os.path.join(PROJECT_ROOT, "Verilator")
STIM_DIR      = os.path.join(PROJECT_ROOT, "testbenches", "stimulus")
RESULTS_DIR   = os.path.join(PROJECT_ROOT, "testbenches", "results")

# ─────────────────────────────────────────────
#  ANSI colours
# ─────────────────────────────────────────────
GRN  = "\033[92m"
RED  = "\033[91m"
YLW  = "\033[93m"
BLU  = "\033[94m"
BOLD = "\033[1m"
RST  = "\033[0m"

def ok(s):   return f"{GRN}{s}{RST}"
def err(s):  return f"{RED}{s}{RST}"
def warn(s): return f"{YLW}{s}{RST}"
def hdr(s):  return f"{BOLD}{BLU}{s}{RST}"


# ─────────────────────────────────────────────
#  Step 1 — Generate test data
# ─────────────────────────────────────────────

def generate_data(matrix_size, num_tests):
    """Call gen_conv_tests.py to produce .mem files for an NxN matmul."""
    print(hdr(f"\n{'═'*55}"))
    print(hdr(f"  GENERATING TEST DATA  ({matrix_size}×{matrix_size}, {num_tests} set(s))"))
    print(hdr(f"{'═'*55}"))

    cmd = [
        sys.executable, GEN_SCRIPT,
        "--img-h",     str(matrix_size),
        "--img-w",     str(matrix_size),
        "--kernel",    str(matrix_size),   # single window = clean 1:1 matmul
        "--stride",    str(matrix_size),
        "--num-tests", str(num_tests),
        "--dir",       STIM_DIR,
        "--no-debug",                      # suppress per-element output for cleanliness
    ]

    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        print(err("  [ERROR] Data generation failed:"))
        print(result.stderr)
        sys.exit(1)

    print(result.stdout.strip())
    print(ok(f"  ✓ Test data written to {STIM_DIR}"))


# ─────────────────────────────────────────────
#  Step 2 — Patch TB parameters
# ─────────────────────────────────────────────

TB_PATH = None   # set later based on project root search

def find_tb():
    """Locate TB_SystolicMesh.sv anywhere under the project root."""
    for root, _, files in os.walk(PROJECT_ROOT):
        for f in files:
            if f == "TB_SystolicMesh.sv":
                return os.path.join(root, f)
    return None


def patch_tb(matrix_size, tile_size, num_tests):
    """
    Rewrite the localparams in the testbench for the current config.
    Returns the original file content so it can be restored.
    """
    tb = find_tb()
    if not tb:
        print(err("  [ERROR] TB_SystolicMesh.sv not found under project root."))
        sys.exit(1)

    with open(tb) as f:
        original = f.read()

    patched = original
    patched = re.sub(r'(localparam\s+MATRIX_SIZE\s*=\s*)\d+',
                     rf'\g<1>{matrix_size}', patched)
    patched = re.sub(r'(localparam\s+TILE_SIZE\s*=\s*)\d+',
                     rf'\g<1>{tile_size}',   patched)
    patched = re.sub(r'(localparam\s+int\s+NUM_TEST_SETS\s*=\s*)\d+',
                     rf'\g<1>{num_tests}',   patched)

    with open(tb, "w") as f:
        f.write(patched)

    return tb, original


def restore_tb(tb_path, original_content):
    with open(tb_path, "w") as f:
        f.write(original_content)


# ─────────────────────────────────────────────
#  Step 3 — Build & run
# ─────────────────────────────────────────────

def run_make(target=""):
    """Run make (optionally with a target) from the project root."""
    cmd = ["make"] + ([target] if target else [])
    result = subprocess.run(cmd, cwd=PROJECT_ROOT,
                            capture_output=True, text=True)
    return result



# ─────────────────────────────────────────────
#  Step 4 — Parse simulation output
# ─────────────────────────────────────────────

def parse_output(raw):
    """
    Extract key metrics from the simulation stdout.
    Returns a dict with pass/fail/tol counts and overall result.
    """
    stats = {
        "result":        "UNKNOWN",
        "sets_passed":   0,
        "sets_failed":   0,
        "total_elements": 0,
        "tol_elements":  0,
        "exact_elements": 0,
        "fail_elements": 0,
        "timeout":       False,
        "raw":           raw,
    }

    if "FATAL" in raw or "Timeout" in raw:
        stats["result"]  = "TIMEOUT"
        stats["timeout"] = True
        return stats

    m = re.search(r'Passed Sets:\s*(\d+)', raw)
    if m: stats["sets_passed"] = int(m.group(1))

    m = re.search(r'Failed Sets:\s*(\d+)', raw)
    if m: stats["sets_failed"] = int(m.group(1))

    m = re.search(r'Total Elements:\s*(\d+)', raw)
    if m: stats["total_elements"] = int(m.group(1))

    m = re.search(r'Tol Passed Els:\s*(\d+)', raw)
    if m: stats["tol_elements"] = int(m.group(1))

    # Count FAIL lines
    stats["fail_elements"] = raw.count("[FAIL]")

    stats["exact_elements"] = (stats["total_elements"]
                               - stats["tol_elements"]
                               - stats["fail_elements"])

    m = re.search(r'RESULT:\s*(SUCCESS|FAILURE)', raw)
    if m: stats["result"] = m.group(1)

    # Parse cycle counts from TB output
    cycle_matches = re.findall(r"Set\s+\d+\s*:\s*(\d+)\s*cycles", raw)
    stats["cycles"] = [int(c) for c in cycle_matches]
    stats["avg_cycles"] = (sum(stats["cycles"]) // len(stats["cycles"])
                           if stats["cycles"] else 0)
    return stats


def run_simulation(matrix_size, tile_size, num_tests):
    """
    Compile and run via make.
    The Makefile already:
      1. Compiles the design with Verilator
      2. Copies testbenches/stimulus/*.mem -> Verilator/
      3. Runs the simulation binary from Verilator/
    So a single 'make' call is all we need per config.
    """
    print(f"\n  {BOLD}► make (compile + copy + run)...{RST}", flush=True)
    t0 = time.time()
    result = run_make()
    elapsed = time.time() - t0

    # make stdout+stderr contains the full simulation output
    raw = result.stdout + result.stderr

    if result.returncode != 0 and "RESULT:" not in raw:
        # Genuine build failure — no simulation output present
        print(err(f"  BUILD FAILED  ({elapsed:.1f}s)"))
        print(raw[-2000:])
        return None, elapsed

    stats = parse_output(raw)
    stats["build_time"] = elapsed
    stats["sim_time"]   = elapsed   # make runs both; only wall total available

    # Save raw log
    os.makedirs(RESULTS_DIR, exist_ok=True)
    log_path = os.path.join(RESULTS_DIR, f"M{matrix_size}_T{tile_size}.log")
    with open(log_path, "w") as f:
        f.write(raw)
    stats["log"] = log_path

    result_str = ok("PASSED") if stats["result"] == "SUCCESS" else err("FAILED")
    print(f"  {result_str}  (wall time {elapsed:.1f}s)")
    return stats, elapsed


# ─────────────────────────────────────────────
#  Step 5 — Summary table
# ─────────────────────────────────────────────

def print_summary(matrix_size, all_stats):
    """Print a formatted summary table of all configurations."""
    print(hdr(f"\n{'═'*75}"))
    print(hdr(f"  SUMMARY  —  {matrix_size}×{matrix_size} matrix, varying TILE_SIZE"))
    print(hdr(f"{'═'*75}"))

    header = (f"  {'TILE':>6}  {'RESULT':>8}  {'Sets':>5}  "
              f"{'Elements':>9}  {'Exact':>7}  {'Tol-Pass':>9}  "
              f"{'Fail':>5}  {'Cycles(avg)':>12}  Log")
    print(header)
    print(f"  {'─'*76}")

    all_passed = True
    for tile_size, stats in all_stats:
        if stats is None:
            row = (f"  {tile_size:>6}  {err('BUILD ERR'):>8}")
            print(row)
            all_passed = False
            continue

        r      = stats["result"]
        passed = r == "SUCCESS"
        all_passed = all_passed and passed

        res_str  = ok("PASS") if passed else err("FAIL")
        sets_str = f"{stats['sets_passed']}/{stats['sets_passed']+stats['sets_failed']}"
        tol_pct  = (stats["tol_elements"] / max(stats["total_elements"], 1)) * 100
        exact_pct = (stats["exact_elements"] / max(stats["total_elements"], 1)) * 100

        cyc = str(stats.get("avg_cycles", "n/a"))
        print(
            f"  {tile_size:>6}  {res_str:>8}  {sets_str:>5}  "
            f"{stats['total_elements']:>9}  "
            f"{stats['exact_elements']:>5} ({exact_pct:4.1f}%)  "
            f"{stats['tol_elements']:>5} ({tol_pct:4.1f}%)  "
            f"{stats['fail_elements']:>5}  "
            f"{cyc:>12}  "
            f"{os.path.basename(stats['log'])}"
        )

    print(f"  {'─'*75}")
    overall = ok("ALL PASSED") if all_passed else err("SOME FAILED")
    print(f"\n  Overall: {overall}")
    print(f"  Logs saved to: {RESULTS_DIR}/")
    print(hdr(f"{'═'*75}\n"))


# ─────────────────────────────────────────────
#  Main
# ─────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(description="Multi-config SystolicMesh test runner")
    parser.add_argument("--matrix",     type=int,   default=8,
                        help="Matrix size N for NxN multiply (default: 8)")
    parser.add_argument("--tiles",      type=int,   nargs="+", default=None,
                        help="Tile sizes to test (default: all powers of 2 up to --matrix)")
    parser.add_argument("--num-tests",  type=int,   default=1,
                        help="Number of random test sets per config (default: 1)")
    parser.add_argument("--keep-going", action="store_true",
                        help="Continue even if a config fails (default: stop on first failure)")
    parser.add_argument(
        "--no-gen",
        action="store_true",
        help="Skip data generation — use existing .mem files in testbenches/stimulus/",
    )
    args = parser.parse_args()

    matrix_size = args.matrix
    num_tests   = args.num_tests

    # Default tile sizes: all powers of 2 that evenly divide matrix_size
    if args.tiles:
        tile_sizes = args.tiles
    else:
        tile_sizes = [2**i for i in range(1, matrix_size.bit_length())
                      if matrix_size % (2**i) == 0]

    # Validate
    for t in tile_sizes:
        if matrix_size % t != 0:
            print(err(f"[ERROR] TILE_SIZE={t} does not divide MATRIX_SIZE={matrix_size} evenly."))
            sys.exit(1)
        if t > matrix_size:
            print(err(f"[ERROR] TILE_SIZE={t} > MATRIX_SIZE={matrix_size}."))
            sys.exit(1)

    print(hdr(f"\n{'═'*55}"))
    print(hdr(f"  SystolicMesh Multi-Config Test Runner"))
    print(hdr(f"{'═'*55}"))
    print(f"  Matrix size : {matrix_size}×{matrix_size}")
    print(f"  Tile sizes  : {tile_sizes}")
    print(f"  Test sets   : {num_tests}")
    print(f"  Keep going  : {args.keep_going}")
    print(f"  Data gen    : {'SKIPPED (--no-gen)' if args.no_gen else 'auto'}")

    # Generate test data once — skip if --no-gen is set
    if args.no_gen:
        print(warn(f"  [Skip] Using existing .mem files in {STIM_DIR}"))
    else:
        generate_data(matrix_size, num_tests)

    all_stats = []
    tb_path = find_tb()
    if not tb_path:
        print(err("[ERROR] Cannot find TB_SystolicMesh.sv"))
        sys.exit(1)

    with open(tb_path) as f:
        original_tb = f.read()

    try:
        for tile_size in tile_sizes:
            print(hdr(f"\n{'─'*55}"))
            print(hdr(f"  CONFIG: MATRIX_SIZE={matrix_size}, TILE_SIZE={tile_size}"))
            print(hdr(f"{'─'*55}"))

            # Patch TB
            print(f"  Patching TB: MATRIX_SIZE={matrix_size}, "
                  f"TILE_SIZE={tile_size}, NUM_TEST_SETS={num_tests}")
            patch_tb(matrix_size, tile_size, num_tests)

            stats, _ = run_simulation(matrix_size, tile_size, num_tests)
            all_stats.append((tile_size, stats))

            if not args.keep_going:
                if stats is None or stats["result"] != "SUCCESS":
                    print(err(f"\n  Stopping early — TILE_SIZE={tile_size} failed."))
                    print(f"  Use --keep-going to run all configs regardless.")
                    break

    finally:
        # Always restore the original TB
        restore_tb(tb_path, original_tb)
        print(f"\n  {ok('✓')} TB_SystolicMesh.sv restored to original.")

    print_summary(matrix_size, all_stats)


if __name__ == "__main__":
    main()
