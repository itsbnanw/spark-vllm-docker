#!/bin/bash
# Focused, offline checks for the solo GGUF recipe and its selective download.
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TEST_DIR="$(mktemp -d)"
trap 'rm -rf "$TEST_DIR"' EXIT
mkdir -p "$TEST_DIR/bin"
export HF_HOME="$TEST_DIR/hf"
export TEST_LOG="$TEST_DIR/commands.log"
: > "$TEST_LOG"
: > "$TEST_DIR/empty.env"

cat > "$TEST_DIR/bin/docker" <<'MOCK_DOCKER'
#!/bin/bash
printf 'docker %s\n' "$*" >> "$TEST_LOG"
if [ "${1:-}" = image ] && [ "${2:-}" = inspect ]; then
    exit 1
fi
MOCK_DOCKER

cat > "$TEST_DIR/bin/uvx" <<'MOCK_UVX'
#!/bin/bash
printf 'uvx %s\n' "$*" >> "$TEST_LOG"
if [ "$1" != hf ] || [ "$2" != download ] || [ "$3" != 0bserverx/Qwen3.8-27B-Heretic-Abliterated-Uncensored-GGUF ] || \
   [ "$4" != RVN-Q8_0-multilingual.gguf ] || [ "$5" != --local-dir ]; then
    exit 1
fi
mkdir -p "$6"
printf 'mock GGUF\n' > "$6/$4"
MOCK_UVX

chmod +x "$TEST_DIR/bin/docker" "$TEST_DIR/bin/uvx"
export PATH="$TEST_DIR/bin:$PATH"
cd "$PROJECT_DIR"

DRY_RUN="$(./run-recipe.sh qwen3.8-27b-heretic-rvn-q8-gguf --solo --setup --dry-run --config /dev/null)"
[[ "$DRY_RUN" == *"Would build container: llama-node"* ]]
[[ "$DRY_RUN" == *"--name llama_node"* ]]
[[ "$DRY_RUN" == *"Would download model: 0bserverx/Qwen3.8-27B-Heretic-Abliterated-Uncensored-GGUF / RVN-Q8_0-multilingual.gguf"* ]]
[[ "$DRY_RUN" == *"exec llama-server"* ]]
[[ "$DRY_RUN" == *"--ctx-size 32768"* ]]
[[ "$DRY_RUN" == *"--n-gpu-layers 99"* ]]

./build-and-copy.sh --llama-cpp -t llama-node > /dev/null
grep -q '^docker build -t llama-node .* -f Dockerfile.llama ' "$TEST_LOG"
if grep -q '^docker pull ' "$TEST_LOG"; then
    echo "Unexpected prebuilt image pull" >&2
    exit 1
fi

./hf-download.sh 0bserverx/Qwen3.8-27B-Heretic-Abliterated-Uncensored-GGUF \
    --file RVN-Q8_0-multilingual.gguf --config "$TEST_DIR/empty.env" > "$TEST_DIR/download.out" || {
    cat "$TEST_DIR/download.out" >&2
    exit 1
}
grep -q '^uvx hf download 0bserverx/Qwen3.8-27B-Heretic-Abliterated-Uncensored-GGUF RVN-Q8_0-multilingual.gguf --local-dir ' "$TEST_LOG"
test -s "$HF_HOME/selected-models/0bserverx/Qwen3.8-27B-Heretic-Abliterated-Uncensored-GGUF/RVN-Q8_0-multilingual.gguf"

BEFORE="$(grep -c '^uvx ' "$TEST_LOG")"
SKIP_OUTPUT="$(./run-recipe.sh qwen3.8-27b-heretic-rvn-q8-gguf --solo --download-only --config /dev/null)"
[[ "$SKIP_OUTPUT" == *"already exists in cache"* ]]
AFTER="$(grep -c '^uvx ' "$TEST_LOG")"
test "$BEFORE" -eq "$AFTER"

./run-recipe.sh qwen3.8-27b-heretic-rvn-q8-gguf --solo --download-only --force-download --config /dev/null > /dev/null
grep -q '^uvx hf download .* --force-download$' "$TEST_LOG"

echo "GGUF recipe checks passed"
