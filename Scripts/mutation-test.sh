#!/usr/bin/env bash
set -euo pipefail

# Mutation testing runner for the BordersCore library.
#
# For every generated mutant: swap it over the working-tree file, run the test
# suite, restore immediately. INT and TERM restore and then exit; a plain EXIT
# trap restores as the shell leaves. A hard kill (SIGKILL) runs no trap at all,
# so if a run is killed that way, check `git status` before trusting the tree.
#
# A line carrying a `mutation:skip` comment is left alone. Use it only where a
# mutant provably cannot change observable behaviour, and say why on the line.
#
# A mutant is killed when the suite fails to build, fails to pass, or hangs.
# Survivors
# are listed with their diff so weak assertions can be strengthened.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${REPO_ROOT:-$(cd "${SCRIPT_DIR}/.." && pwd)}"

SOURCE_DIR="Sources/BordersCore"
REPORT_DIR="${REPO_ROOT}/.run/mutation"
EXECUTE=0
NO_FAIL=0
MAX_MUTANTS=600
TIMEOUT_SECS=180
declare -a FILE_FILTERS=()

usage() {
  cat <<'EOF'
Usage: mutation-test.sh [--file PATH]... [--execute] [--no-fail]
                        [--max-mutants N] [--report-dir DIR]

Generate Swift mutants for Sources/BordersCore and run `swift test` against
each one. Mutants are applied to the working-tree file one at a time and
restored after every run.

Mutation operators:
  LOGICAL_AND_OR    && <-> ||
  EQUALITY          == <-> !=
  BOUNDARY_CHECK    < <-> <=, > <-> >=
  BOOLEAN_LITERAL   true <-> false
  BIT_SHIFT         >> <-> <<
  STRING_PREDICATE  hasPrefix <-> hasSuffix
  RANGE_BOUND       ... <-> ..<
  SEQUENCE_END      first <-> last, dropFirst <-> dropLast

A line containing `mutation:skip` is excluded from mutation.
  CLAMP_DIRECTION   min( <-> max(
  ARITHMETIC        + <-> -, * <-> /

Options:
  --file PATH       Restrict to one source file; repeatable
  --execute         Run the mutation cycle (default is a dry-run plan)
  --no-fail         Exit 0 even when mutants survive
  --max-mutants N   Safety cap on generated mutants (default 600)
  --timeout SECONDS Per-suite timeout; a timeout counts as killed (default 180)
  --report-dir DIR  Work and report directory (default .run/mutation)
  -h, --help        Show this message
EOF
}

die() {
  printf 'mutation-test.sh: %s\n' "$1" >&2
  exit 2
}

while [ $# -gt 0 ]; do
  case "$1" in
    --file) [ $# -ge 2 ] || die "--file needs a path"; FILE_FILTERS+=("$2"); shift 2 ;;
    --execute) EXECUTE=1; shift ;;
    --no-fail) NO_FAIL=1; shift ;;
    --max-mutants) [ $# -ge 2 ] || die "--max-mutants needs a number"; MAX_MUTANTS="$2"; shift 2 ;;
    --timeout) [ $# -ge 2 ] || die "--timeout needs a number"; TIMEOUT_SECS="$2"; shift 2 ;;
    --report-dir) [ $# -ge 2 ] || die "--report-dir needs a path"; REPORT_DIR="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown argument: $1" ;;
  esac
done

cd "${REPO_ROOT}"

declare -a SOURCES=()
if [ ${#FILE_FILTERS[@]} -gt 0 ]; then
  for candidate in "${FILE_FILTERS[@]}"; do
    [ -f "${candidate}" ] || die "no such file: ${candidate}"
    SOURCES+=("${candidate}")
  done
else
  while IFS= read -r candidate; do
    SOURCES+=("${candidate}")
  done < <(find "${SOURCE_DIR}" -name '*.swift' | sort)
fi
[ ${#SOURCES[@]} -gt 0 ] || die "no Swift sources found under ${SOURCE_DIR}"

mkdir -p "${REPORT_DIR}"
PLAN="${REPORT_DIR}/plan.tsv"
KILLED="${REPORT_DIR}/killed.tsv"
SURVIVED="${REPORT_DIR}/survived.tsv"
LOG="${REPORT_DIR}/last-run.log"
: >"${PLAN}"

# Emit one plan row per mutable occurrence. Comment lines are skipped; string
# literals are not detected, so an occasional equivalent mutant is expected and
# is reported as a survivor for a human to judge.
plan_file() {
  local file="$1"
  awk -v file="${file}" '
    function emit(from, to, op,   rest, offset, occurrence, position) {
      rest = $0
      offset = 0
      occurrence = 0
      while ((position = index(rest, from)) > 0) {
        occurrence++
        printf "%s\t%d\t%d\t%s\t%s\t%s\n", file, FNR, occurrence, from, to, op
        offset = position + length(from)
        rest = substr(rest, offset)
      }
    }
    {
      line = $0
      sub(/^[ \t]+/, "", line)
      if (line ~ /^\/\//) next
      if ($0 ~ /mutation:skip/) next
      emit(" && ", " || ", "LOGICAL_AND_OR")
      emit(" || ", " && ", "LOGICAL_AND_OR")
      emit(" == ", " != ", "EQUALITY")
      emit(" != ", " == ", "EQUALITY")
      emit(" <= ", " < ", "BOUNDARY_CHECK")
      emit(" >= ", " > ", "BOUNDARY_CHECK")
      emit("min(", "max(", "CLAMP_DIRECTION")
      emit("max(", "min(", "CLAMP_DIRECTION")
      emit(" + ", " - ", "ARITHMETIC")
      emit(" * ", " / ", "ARITHMETIC")
      emit("true", "false", "BOOLEAN_LITERAL")
      emit("false", "true", "BOOLEAN_LITERAL")
      emit(" >> ", " << ", "BIT_SHIFT")
      emit(" << ", " >> ", "BIT_SHIFT")
      emit("hasPrefix(", "hasSuffix(", "STRING_PREDICATE")
      emit("hasSuffix(", "hasPrefix(", "STRING_PREDICATE")
      emit("...", "..<", "RANGE_BOUND")
      emit("..<", "...", "RANGE_BOUND")
      emit("dropFirst(", "dropLast(", "SEQUENCE_END")
      emit("dropLast(", "dropFirst(", "SEQUENCE_END")
      emit(".first", ".last", "SEQUENCE_END")
      emit(".last", ".first", "SEQUENCE_END")
    }
  ' "${file}"
  # " < " and " > " are handled separately so a generic comparison is not
  # rewritten inside a generic parameter list such as Array<Int>.
  awk -v file="${file}" '
    function emit(from, to, op,   rest, occurrence, position) {
      rest = $0
      occurrence = 0
      while ((position = index(rest, from)) > 0) {
        occurrence++
        printf "%s\t%d\t%d\t%s\t%s\t%s\n", file, FNR, occurrence, from, to, op
        rest = substr(rest, position + length(from))
      }
    }
    {
      line = $0
      sub(/^[ \t]+/, "", line)
      if (line ~ /^\/\//) next
      if ($0 ~ /mutation:skip/) next
      if ($0 ~ /</ && $0 ~ />/ && $0 ~ /[A-Za-z]</) next
      emit(" < ", " <= ", "BOUNDARY_CHECK")
      emit(" > ", " >= ", "BOUNDARY_CHECK")
    }
  ' "${file}"
}

for source in "${SOURCES[@]}"; do
  plan_file "${source}" >>"${PLAN}"
done

TOTAL=$(wc -l <"${PLAN}" | tr -d ' ')
[ "${TOTAL}" -le "${MAX_MUTANTS}" ] || die "generated ${TOTAL} mutants, above the cap of ${MAX_MUTANTS}"
echo "Planned ${TOTAL} mutants across ${#SOURCES[@]} file(s)."

if [ "${EXECUTE}" -eq 0 ]; then
  cut -f6 "${PLAN}" | sort | uniq -c | sort -rn | sed 's/^/  /'
  echo "Dry run only. Re-run with --execute to run the suite against each mutant."
  exit 0
fi

# Apply one occurrence of a fixed string on one line, leaving the rest alone.
apply_mutant() {
  local file="$1" line="$2" occurrence="$3" from="$4" to="$5" destination="$6"
  awk -v target="${line}" -v want="${occurrence}" -v from="${from}" -v to="${to}" '
    NR != target { print; next }
    {
      out = ""
      rest = $0
      seen = 0
      while ((position = index(rest, from)) > 0) {
        seen++
        if (seen == want) {
          out = out substr(rest, 1, position - 1) to
          rest = substr(rest, position + length(from))
          break
        }
        out = out substr(rest, 1, position + length(from) - 1)
        rest = substr(rest, position + length(from))
      }
      print out rest
    }
  ' "${file}" >"${destination}"
}

BACKUP_DIR="${REPORT_DIR}/backup"
rm -rf "${BACKUP_DIR}"
mkdir -p "${BACKUP_DIR}"
for source in "${SOURCES[@]}"; do
  mkdir -p "${BACKUP_DIR}/$(dirname "${source}")"
  cp "${source}" "${BACKUP_DIR}/${source}"
done

restore() {
  for source in "${SOURCES[@]}"; do
    cp "${BACKUP_DIR}/${source}" "${source}"
  done
}
trap restore EXIT
trap 'restore; exit 130' INT
trap 'restore; exit 143' TERM

: >"${KILLED}"
: >"${SURVIVED}"
: >"${LOG}"

# Run the suite with a wall-clock limit. A mutant can turn a loop or a socket
# read into one that never finishes, and an unbounded run would stall the whole
# cycle behind it.
run_suite() {
  # Job control gives the suite its own process group, so a timeout can kill
  # the whole tree. Killing only the driver used to orphan the test binary,
  # which then held the build lock and hung every later mutant.
  set -m
  swift test >>"${LOG}" 2>&1 &
  local suite=$!
  set +m
  local deadline=$(( SECONDS + TIMEOUT_SECS ))
  while :; do
    # A completed background child can remain as a zombie until wait() reaps
    # it. kill -0 still succeeds for that state, so inspect the process state
    # as well or every fast test run looks like a timeout.
    local process_state
    process_state=$(ps -o stat= -p "${suite}" 2>/dev/null | tr -d '[:space:]')
    if [ -z "${process_state}" ] || [[ "${process_state}" == Z* ]]; then
      wait "${suite}"
      return $?
    fi
    if [ "${SECONDS}" -ge "${deadline}" ]; then
      kill -TERM -- "-${suite}" 2>/dev/null || kill -TERM "${suite}" 2>/dev/null || true
      sleep 2
      kill -KILL -- "-${suite}" 2>/dev/null || kill -KILL "${suite}" 2>/dev/null || true
      wait "${suite}" 2>/dev/null || true
      await_quiet
      return 124
    fi
    sleep 1
  done
  wait "${suite}"
}

# Wait for the test binary to disappear. A run that starts while an older one
# still holds the package lock waits forever instead of failing.
await_quiet() {
  local attempts=0
  while pgrep -f 'bordersPackageTests.xctest' >/dev/null 2>&1; do
    pkill -KILL -f 'bordersPackageTests.xctest' 2>/dev/null || true
    attempts=$(( attempts + 1 ))
    if [ "${attempts}" -gt 30 ]; then
      die "a previous test process will not exit; kill it and re-run"
    fi
    sleep 1
  done
}

echo "Establishing the baseline."
if ! run_suite; then
  die "the suite fails or times out before any mutation; fix that first (see ${LOG})"
fi

index=0
while IFS=$'\t' read -r file line occurrence from to operator; do
  index=$((index + 1))
  printf '[%d/%d] %s:%s %s %q -> %q ... ' "${index}" "${TOTAL}" "${file}" "${line}" "${operator}" "${from}" "${to}"
  apply_mutant "${file}" "${line}" "${occurrence}" "${from}" "${to}" "${REPORT_DIR}/mutant.swift"
  if cmp -s "${file}" "${REPORT_DIR}/mutant.swift"; then
    echo "no change, skipped"
    continue
  fi
  cp "${REPORT_DIR}/mutant.swift" "${file}"
  if run_suite; then
    echo "SURVIVED"
    printf '%s\t%s\t%s\t%s\t%s\n' "${file}" "${line}" "${operator}" "${from}" "${to}" >>"${SURVIVED}"
  else
    status=$?
    [ "${status}" -eq 124 ] && echo "killed (timeout)" || echo "killed"
    printf '%s\t%s\t%s\t%s\t%s\n' "${file}" "${line}" "${operator}" "${from}" "${to}" >>"${KILLED}"
  fi
  cp "${BACKUP_DIR}/${file}" "${file}"
done <"${PLAN}"

restore
rm -f "${REPORT_DIR}/mutant.swift"

KILLED_COUNT=$(wc -l <"${KILLED}" | tr -d ' ')
SURVIVED_COUNT=$(wc -l <"${SURVIVED}" | tr -d ' ')
RUN_COUNT=$((KILLED_COUNT + SURVIVED_COUNT))
echo
echo "Mutants run: ${RUN_COUNT}  killed: ${KILLED_COUNT}  survived: ${SURVIVED_COUNT}"
if [ "${RUN_COUNT}" -gt 0 ]; then
  awk -v killed="${KILLED_COUNT}" -v run="${RUN_COUNT}" \
    'BEGIN { printf "Mutation score: %.1f%%\n", 100 * killed / run }'
fi

if [ "${SURVIVED_COUNT}" -gt 0 ]; then
  echo
  echo "Survivors:"
  awk -F'\t' '{ printf "  %s:%s  %s  %s -> %s\n", $1, $2, $3, $4, $5 }' "${SURVIVED}"
  [ "${NO_FAIL}" -eq 1 ] || exit 1
fi
