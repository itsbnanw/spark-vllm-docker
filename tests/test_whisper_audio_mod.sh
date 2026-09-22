#!/bin/bash
set -euo pipefail

project_dir="$(cd "$(dirname "$0")/.." && pwd)"
test_dir="$(mktemp -d)"
trap 'rm -rf "$test_dir"' EXIT
mkdir -p "$test_dir/bin"
export MOCK_READY="$test_dir/audio-ready"
export MOCK_INSTALL_LOG="$test_dir/install.log"
export MOCK_CONSTRAINTS_LOG="$test_dir/constraints.log"

cat > "$test_dir/bin/python3" <<'MOCK_PYTHON'
#!/bin/bash
if [ "${1:-}" = '-c' ]; then
  case "$2" in
    'import av, scipy, soundfile, soxr') [ -f "$MOCK_READY" ]; exit $? ;;
    'import torch; print(torch.__version__)') echo '2.13.0+cu130'; exit 0 ;;
    *"m.version('torchvision')"*) echo '0.28.0+cu130'; exit 0 ;;
    *"m.version('torchaudio')"*) echo '2.11.0+cu130'; exit 0 ;;
  esac
fi
echo "Unexpected mock Python call: $*" >&2
exit 1
MOCK_PYTHON

cat > "$test_dir/bin/uv" <<'MOCK_UV'
#!/bin/bash
printf '%s\n' "$*" > "$MOCK_INSTALL_LOG"
for ((i = 1; i <= $#; i++)); do
  if [ "${!i}" = '--override' ]; then
    next=$((i + 1))
    cp "${!next}" "$MOCK_CONSTRAINTS_LOG"
    break
  fi
done
if [ "${MOCK_INSTALL_FAIL:-0}" = 1 ]; then
  exit 42
fi
touch "$MOCK_READY"
MOCK_UV

chmod +x "$test_dir/bin/python3" "$test_dir/bin/uv"
export PATH="$test_dir/bin:$PATH"

# Existing packages must avoid a redundant installer call.
touch "$MOCK_READY"
output="$(bash "$project_dir/mods/whisper-audio/run.sh")"
[[ "$output" == *'already available'* ]]
[ ! -e "$MOCK_INSTALL_LOG" ]

# Missing packages must be installed with the image's Torch versions pinned.
rm "$MOCK_READY"
output="$(bash "$project_dir/mods/whisper-audio/run.sh")"
[[ "$output" == *'Audio dependencies are ready'* ]]
for package in av scipy soundfile soxr; do
  grep -Fq "$package" "$MOCK_INSTALL_LOG"
done
grep -Fxq 'torch==2.13.0+cu130' "$MOCK_CONSTRAINTS_LOG"
grep -Fxq 'torchvision==0.28.0+cu130' "$MOCK_CONSTRAINTS_LOG"
grep -Fxq 'torchaudio==2.11.0+cu130' "$MOCK_CONSTRAINTS_LOG"

# Installer failure must stop the launch with a useful error.
rm "$MOCK_READY"
export MOCK_INSTALL_FAIL=1
if output="$(bash "$project_dir/mods/whisper-audio/run.sh" 2>&1)"; then
  echo 'Expected audio dependency installation to fail.' >&2
  exit 1
fi
[[ "$output" == *'Audio dependency installation failed'* ]]

echo 'Whisper audio mod tests passed.'
