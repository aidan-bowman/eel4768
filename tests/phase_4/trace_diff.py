import argparse
import sys


def is_dont_care(val):
    """Check if a value is a don't-care (contains x or X)."""
    return "x" in val.lower()


def values_match(generated, expected):
    """Check if values match, accounting for don't-cares."""
    if is_dont_care(expected):
        return True
    return generated.lower() == expected.lower()


def read_trace(path):
    """Read a trace, ignoring comments and blank lines."""
    with open(path) as trace_file:
        return [
            line.strip()
            for line in trace_file
            if line.strip() and not line.strip().startswith("#")
        ]


def print_trace(label, lines):
    print(f"{label}:")
    if lines:
        for line in lines:
            print(f"  {line}")
    else:
        print("  <empty>")


def main():
    parser = argparse.ArgumentParser(
        description="Compare generated and expected Verilog traces."
    )
    parser.add_argument("generated_trace", help="Path to the generated trace")
    parser.add_argument("expected_trace", help="Path to the expected trace")
    args = parser.parse_args()

    try:
        gen_lines = read_trace(args.generated_trace)
        exp_lines = read_trace(args.expected_trace)
    except OSError as error:
        print(f"Error: {error}", file=sys.stderr)
        return 1

    failed = False

    if not gen_lines:
        print("FAIL: Generated trace is empty.")

    if not exp_lines:
        print("FAIL: Expected trace is empty.")
        

    if len(gen_lines) != len(exp_lines):
        print(
            f"FAIL: Line count mismatch "
            f"(generated: {len(gen_lines)}, expected: {len(exp_lines)})."
        )
        failed = True

    for i, (g, e) in enumerate(zip(gen_lines, exp_lines), start=1):
        gen_fields = g.split()
        exp_fields = e.split()

        if len(gen_fields) != len(exp_fields):
            print(f"Line {i}: Field count mismatch")
            print(f"Got:      {g}")
            print(f"Expected: {e}")
            failed = True
            continue

        for j, (gf, ef) in enumerate(zip(gen_fields, exp_fields), start=1):
            if not values_match(gf, ef):
                print(f"Line {i}, Field {j}: Value mismatch")
                print(f"Got:      {g}")
                print(f"Expected: {e}")
                failed = True

    if failed:
        return 1

    print("PASS!")
    return 0


if __name__ == "__main__":
    sys.exit(main())
