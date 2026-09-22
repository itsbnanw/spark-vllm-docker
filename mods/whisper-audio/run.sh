#!/bin/bash
set -euo pipefail

prefix='[whisper-audio]'

if ! command -v python3 >/dev/null 2>&1; then
  echo "$prefix python3 is required for Whisper audio support." >&2
  exit 1
fi
python_executable="$(command -v python3)"

# These are the vLLM audio decoding and resampling packages Whisper needs.
if "$python_executable" -c 'import av, scipy, soundfile, soxr' >/dev/null 2>&1; then
  echo "$prefix Audio dependencies are already available."
  exit 0
fi

if ! torch_version="$("$python_executable" -c 'import torch; print(torch.__version__)' 2>/dev/null)"; then
  echo "$prefix Could not read the installed Torch version; refusing to change the image's Torch build." >&2
  exit 1
fi

constraints="$(mktemp)"
trap 'rm -f "$constraints"' EXIT
printf 'torch==%s\n' "$torch_version" > "$constraints"
for package in torchvision torchaudio; do
  version="$("$python_executable" -c "import importlib.metadata as m; print(m.version('$package'))" 2>/dev/null || true)"
  if [ -n "$version" ]; then
    printf '%s==%s\n' "$package" "$version" >> "$constraints"
  fi
done

packages=(av scipy soundfile soxr)
echo "$prefix Installing vLLM audio dependencies with the existing Torch versions pinned."
if command -v uv >/dev/null 2>&1; then
  if ! uv pip install --python "$python_executable" "${packages[@]}" --override "$constraints"; then
    echo "$prefix Audio dependency installation failed." >&2
    exit 1
  fi
elif "$python_executable" -m pip --version >/dev/null 2>&1; then
  if ! "$python_executable" -m pip install --constraint "$constraints" "${packages[@]}"; then
    echo "$prefix Audio dependency installation failed." >&2
    exit 1
  fi
else
  echo "$prefix Neither uv nor Python pip is available to install audio dependencies." >&2
  exit 1
fi

if ! "$python_executable" -c 'import av, scipy, soundfile, soxr' >/dev/null 2>&1; then
  echo "$prefix Audio packages were installed but could not be imported." >&2
  exit 1
fi
if ! "$python_executable" -c 'import torch; print(torch.__version__)' 2>/dev/null | grep -Fxq "$torch_version"; then
  echo "$prefix Torch changed during audio dependency installation; refusing to launch Whisper." >&2
  exit 1
fi
echo "$prefix Audio dependencies are ready."
