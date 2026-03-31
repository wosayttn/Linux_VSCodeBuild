#!/bin/bash

NUMICRO_BSP='M3351BSP'

# 🔧 Check and install jq
if ! command -v jq &> /dev/null; then
    echo "🔧 jq not found. Installing jq..."
    if command -v apt-get &> /dev/null; then
        sudo apt-get update && sudo apt-get install -y jq
    elif command -v dnf &> /dev/null; then
        sudo dnf install -y jq
    elif command -v pacman &> /dev/null; then
        sudo pacman -S --noconfirm jq
    else
        echo "❌ Package manager not supported. Please install jq manually."
        exit 1
    fi
fi

# 🔧 Check and install git
if ! command -v git &> /dev/null; then
    echo "🔧 git not found. Installing git..."
    if command -v apt-get &> /dev/null; then
        sudo apt-get update && sudo apt-get install -y git
    elif command -v dnf &> /dev/null; then
        sudo dnf install -y git
    elif command -v pacman &> /dev/null; then
        sudo pacman -S --noconfirm git
    else
        echo "❌ Package manager not supported. Please install git manually."
        exit 1
    fi
fi

# 🔧 Check and install armlm
export PATH="$HOME/.armlm/bin:$PATH"
if ! command -v armlm &> /dev/null; then
    echo "🔧 armlm not found. Installing armlm to ~/.armlm..."
    ARMLM_ROOT="$HOME/.armlm"
    mkdir -p "$ARMLM_ROOT"
    curl -sL https://artifacts.tools.arm.com/armlm/1.4.0/armlm-1.4.0-lin-x86_64.tar.gz | tar -xz -C "$ARMLM_ROOT"
    export PATH="$ARMLM_ROOT/bin:$PATH"

    # Get nuvoton-free essential AC6 toolchain license(for commercial-use)
    armlm activate --product=KEMDK-NUV1 --server=https://nuvoton-free.licensing.keil.arm.com/
fi

armlm reactivate --product=KEMDK-NUV1

# 🔧 Check and install vcpkg
export PATH="$HOME/.vcpkg:$PATH"
if ! command -v vcpkg &> /dev/null; then
    echo "🔧 vcpkg not found. Installing vcpkg to ~/.vcpkg..."
    VCPKG_ROOT="$HOME/.vcpkg"
    if [ ! -d "$VCPKG_ROOT" ]; then
        git clone https://github.com/microsoft/vcpkg.git "$VCPKG_ROOT"
    fi
    "$VCPKG_ROOT/bootstrap-vcpkg.sh" -disableMetrics
    export PATH="$VCPKG_ROOT:$PATH"
fi

if [ -d "$NUMICRO_BSP" ]; then
    echo "🔄 $NUMICRO_BSP already exists. Pulling latest changes..."
    # Run git pull in a subshell to avoid changing the working directory of the script
    (cd "$NUMICRO_BSP" && git pull)
else
    echo "📥 Cloning $NUMICRO_BSP..."
    git clone https://github.com/OpenNuvoton/$NUMICRO_BSP
fi

# Absolute path to the build script
BUILD_SCRIPT="$(realpath ./vcpkg_build_linux.sh)"

# Use mapfile to avoid subshell so that 'exit 1' properly halts the script
mapfile -t solutions < <(find "$NUMICRO_BSP"/SampleCode -name '*.csolution.yml')

CHECK_SCRIPT="$(realpath ./vcpkg_blacklist_check.sh)"
declare -a failed_logs=()

set +e
for sol_path in "${solutions[@]}"; do
    sol_dir=$(dirname "$sol_path")
    sol_name=$(basename "$sol_path")
    log_path="$sol_dir/$sol_name.txt"

    # Build & Produce log file
    "$BUILD_SCRIPT" "$sol_path" > "$log_path" 2>&1
    ret1=$?

    # Check log file directly with local script instead of the BSP version
    if [ -f "$CHECK_SCRIPT" ]; then
        bash "$CHECK_SCRIPT" "$log_path"
        ret2=$?
    else
        echo "⚠️ Check script not found at $CHECK_SCRIPT"
        ret2=0
    fi

    if [[ $ret1 -ne 0 || $ret2 -ne 0 ]]; then
        echo "❌ Build failed: $sol_path"
        echo "🔍 Log:"
        cat "$log_path"
        failed_logs+=("$log_path")
    else
        echo "✅ Build success: $sol_path"
    fi
done
set -e

# List all the paths of failed logs at the end (if any)
if [[ ${#failed_logs[@]} -ne 0 ]]; then
    echo "🚨 The following builds failed:"
    for log in "${failed_logs[@]}"; do
        echo "  - $log"
    done
    printf "%s," "${failed_logs[@]}" | sed 's/,$//' > failed_logs.txt
    echo "Wrote failed_logs.txt"
    exit 1
else
    echo "🎉 All builds succeeded!"
fi
