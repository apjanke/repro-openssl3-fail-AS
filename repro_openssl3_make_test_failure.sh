#!/bin/bash
#
# repro_openssl3_make_test_failure.sh [-n <num_rebuilds>] [-f <formula>] [--dry-run]
#
# Reproduce the "failure in make test" openssl@3 build failure that apjanke
# was observing on his M1 MacBook Pro "eilonwy" in 2024-02 and which made him
# worried about possible hardware memory problems. In his experience, the rebuild
# would fail its 'make test' stage about 1 in 3 times.
#
# On apjanke's M1 Max MBP, each openssl rebuild takes about 6 minutes to run.
# With the default 16 rebuilds, this script could take about an hour and a half
# to do a full run.

default_n_rebuilds=16
default_formula='openssl@3'

set -o errexit
set -o nounset
set -o pipefail

function die () {
  echo >&2 "error: $*"
  exit 1
}

# Arg parsing
formula="$default_formula"
n_rebuilds="$default_n_rebuilds"
DRY_RUN=0
while [[ $# -gt 0 ]]; do
  arg="$1"; shift
  case "$arg" in
    -f) formula="$1"; shift ;;
    -n) n_rebuilds="$1"; shift ;;
    --dry-run)
        DRY_RUN=1 ;;
    *)  die "invalid argument: $arg" ;;
  esac
done

script_timestamp=$(date +%Y-%M-%d_%H-%M-%S)
script_timestamp_friendly=$(date)
host=$(hostname -s)
# Each script run gets a fresh output dir
outdir="repro-logs/${host}_${script_timestamp}_${formula}"
log_file_prefix="${outdir}/repro-openssl_${script_timestamp}"
host_info_file="${log_file_prefix}_host-info.txt"
script_log_file="${log_file_prefix}_rebuild.log"
failsdir="${outdir}/failures"
n_fails=0

mkdir -p "$outdir"
mkdir -p "$failsdir"

function record_host_info () {
  echo "Host and env info:

Testing formula: ${formula}
Date: ${script_timestamp_friendly}

hostname: $(hostname)

CPU: $(sysctl -n machdep.cpu.brand_string) ($(sysctl -n hw.ncpu) cores)
arch: $(uname -m)
RAM: $(sysctl -n hw.memsize) bytes
uname: $(uname -a)
sw_vers:
$(sw_vers)

brew info for formula ${formula}:
$(brew info ${formula})

Installed Homebrew formulae:
$(brew list --versions)

Hardware info details:
$(sysctl hw)
" > "$host_info_file"

  # Capture this script itself for reference, so we know exactly what
  # version of it was used for that run.
  mkdir -p "${outdir}/code-reference"
  cp "$0" "${outdir}/code-reference"
}

function is_dry_run () {
  if [[ $DRY_RUN == 1 ]]; then
    return 0
  else
    return 1
  fi
}

function is_formula_installed () {
  local check_formula="$1"
  brew list | grep -x "$check_formula" &> /dev/null
}

function run_rebuilds () {
  if ! brew list | grep -x "$formula" &> /dev/null; then
    echo "Installing ${formula} because it is absent."
    brew install "$formula"
    echo "Installed formulae after installing ${formula}:"
    brew list --versions
  fi

  t0=$(date +%s)
  echo "Running ${n_rebuilds} rebuilds, capturing to ${outdir}"
  for i in $(seq 1 "$n_rebuilds"); do
    echo ""
    echo ""
    echo "Running rebuild attempt ${i} of ${n_rebuilds} ($(date))..."
    echo ""
    rebuild_timestamp=$(date +%Y-%M-%d_%H-%M-%S)
    if is_dry_run; then
      echo "DRY RUN: would do: brew reinstall --build-from-source ${formula}"
    else
      if brew reinstall --build-from-source "$formula"; then
        build_status="$?"
        echo "brew reinstall OK for ${formula}"
      else
        build_status="$?"
        echo "brew reinstall FAILED for ${formula}"
        n_fails=$(( n_fails + 1 ))
        echo "Got a build failure on attempt ${i} at ${rebuild_timestamp}."
        savedir="${failsdir}/fail_${i}_${rebuild_timestamp}"
        mkdir -p "$savedir"
        mkdir -p "${savedir}/brew-logs"
        cp -R "${HOME}/Library/Logs/Homebrew/${formula}" "${savedir}/brew-logs"
        echo "Captured failure info and logs to ${savedir}"
      fi
    fi
  done
  t1=$(date +%s)
  te=$(( t1 - t0 ))
  te_per=$(( te / n_rebuilds ))

  echo ""
  echo "All done with repro attempts for ${formula}"
  echo "Ran ${n_rebuilds} rebuilds in ${te} s, ${te_per} s/attempt"
  echo "Num failed rebuilds: ${n_fails} out of ${n_rebuilds} attempts"
  echo ""
}

function run_rebuilds_logged () {
  echo "Logging rebuilds to ${script_log_file}"
  run_rebuilds 2>&1 | tee "$script_log_file"
}


# Main script logic

# For stability across runs:
export HOMEBREW_NO_AUTO_UPDATE=1
# To reduce brew output clutter:
export HOMEBREW_NO_ENV_HINTS=1

record_host_info
run_rebuilds_logged
