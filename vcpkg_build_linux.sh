#!/bin/bash

# Exit immediately if a command exits with a non-zero status, 
# treat unset variables as an error, and catch errors in pipes.
set -euo pipefail

# 1. Input Parameter Validation
proj_path="${1:-}"
if [ -z "$proj_path" ]; then
    echo "❌ Error: Missing project file path (.csolution.yml)"
    echo "Usage: $0 <your_project.csolution.yml>"
    exit 1
fi

# Check if the file actually exists
if [ ! -f "$proj_path" ]; then
    echo "❌ Error: File not found: $proj_path"
    exit 1
fi

proj_dir=$(dirname "$proj_path")
proj=$(basename "$proj_path")

# 2. Environment Setup
cd "$proj_dir"
echo "Building: $proj_path in $(pwd)"

# Ensure required tools are installed
for tool in jq vcpkg; do
    if ! command -v "$tool" &> /dev/null; then
        echo "❌ Error: '$tool' is not installed or not in PATH."
        exit 1
    fi
done

# 3. Activate vcpkg Environment
echo "🔧 Activating vcpkg environment..."
# Use ${GITHUB_WORKSPACE:-$(pwd)} to handle both Local and CI paths
DOWNLOADS_ROOT="~/.vcpkg/downloads"
echo $"Using vcpkg downloads root: $DOWNLOADS_ROOT"

#vcpkg activate --downloads-root="$DOWNLOADS_ROOT" --json=env.json
vcpkg activate --json=env.json

# 4. Preserve Environment Variables
# Write to GitHub Actions environment files if available, otherwise to temp files
ENV_OUT="${GITHUB_ENV:-./.github_env_tmp}"
PATH_OUT="${GITHUB_PATH:-./.github_path_tmp}"

echo "Preserving vcpkg environment to $ENV_OUT and $PATH_OUT..."
jq -r '.tools | to_entries[] | "\(.key)=\(.value)"' env.json >> "$ENV_OUT"
jq -r '.paths.PATH[]' env.json >> "$PATH_OUT"

# 5. Apply Environment to Current Shell
echo "🔧 Applying toolchain environment to current shell..."
eval "$(jq -r '.tools | to_entries[] | "export \(.key)=\"\(.value)\""' env.json)"
VCPKG_PATH_STR=$(jq -r '.paths.PATH[]' env.json | paste -sd ':' -)
export PATH="$VCPKG_PATH_STR:$PATH"

# 6. Verify Toolchain
echo "✅ Compiler check..."
if command -v arm-none-eabi-gcc &> /dev/null; then
    arm-none-eabi-gcc --version | head -n 1
else
    echo "⚠️ Warning: arm-none-eabi-gcc not found after activation!"
fi

# 7. Execute Build Process
echo "📦 Running cbuild (update-rte & packs)..."

# Extract project name without extension for filtering contexts
proj_name="${proj%.csolution.yml}"
# Use mapfile to handle contexts safely (avoids issues with spaces)
mapfile -t contexts < <(cbuild list contexts "$proj" 2>/dev/null | grep "$proj_name")

if [ ${#contexts[@]} -eq 0 ]; then
    echo "⚠️ No contexts found for $proj"
    exit 0
fi

for cxt in "${contexts[@]}"; do
    echo "----------------------------------------------------"
    echo "🚀 Building Context: $cxt"
    
    # Run cbuild with:
    # --packs: Download missing CMSIS Packs
    # --update-rte: Update Run-Time Environment config files
    # -d: Generate build log
    # -v: Verbose output
    cbuild "$proj" --context "$cxt" --packs --update-rte -d -v
done

# 8. Cleanup
if vcpkg help | grep -q "deactivate"; then
    vcpkg deactivate
fi

echo "✅ Build complete for $proj"
