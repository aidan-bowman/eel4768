#!/usr/bin/env bash
# Local pass/fail check of a phase-1 submission, configuration 1 only.
#
# Usage:
#   ./run_test.sh <name> [submission_dir]
#
#   <name>            base name for the summary; it is written to
#                     phase_1/results/<name>.txt
#   [submission_dir]  submission to check; defaults to phase_1/submission/
#
# This is a self-check, not your grade: six checks (four assembly programs
# under configuration 1, two assembler tests), each PASS or FAIL, no points.
# It exits nonzero if any check failed. The real grader runs all three
# configurations and awards points.
#
# The checker itself is source_test/, which is self-contained -- see
# source_test/README.md to run it outside this repository.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ $# -lt 1 || $# -gt 2 ]]; then
    echo "usage: $0 <name> [submission_dir]" >&2
    exit 1
fi
SUMMARY_FILE="${SCRIPT_DIR}/results/$1.txt"
SUBMISSION_ARG="${2:-${SCRIPT_DIR}/submission}"

# Artifacts of THIS run only -- the spliced programs, the RARS dumps and the
# assembler's generated files -- so the directory is wiped first and never
# mixes two runs.
OUTPUT_DIR="${SCRIPT_DIR}/output"
rm -rf "${OUTPUT_DIR}"
mkdir -p "${OUTPUT_DIR}" "${SCRIPT_DIR}/results"

# --- Resolve the submission ------------------------------------------------
if [[ ! -d "${SUBMISSION_ARG}" ]]; then
    echo "ERROR: submission directory not found: ${SUBMISSION_ARG}" >&2
    echo "Put your assembler.py and your addition.s, gemm.s, mult.s and" >&2
    echo "sobel.s in ${SCRIPT_DIR}/submission/, or pass the directory that" >&2
    echo "holds them as the second argument." >&2
    exit 1
fi
SUBMISSION_DIR="$(cd "${SUBMISSION_ARG}" && pwd)"
echo "Submission under test: ${SUBMISSION_DIR}"

status=0
python3 "${SCRIPT_DIR}/source_test/grade_test.py" \
    "${SUBMISSION_DIR}" "${OUTPUT_DIR}" "${SUMMARY_FILE}" || status=$?

echo "Wrote ${SUMMARY_FILE}"
echo "Run artifacts (spliced programs, RARS dumps, gen/ files): ${OUTPUT_DIR}"
exit "${status}"
