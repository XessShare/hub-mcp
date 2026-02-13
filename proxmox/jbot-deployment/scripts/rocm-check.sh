#!/usr/bin/env bash
# ROCm GPU Check — Run inside LXC or Ollama Container
# Usage: docker exec jbot_ollama bash /tmp/rocm-check.sh

set -euo pipefail

echo "=== ROCm GPU Verification ==="
echo ""

# Check 1: Device Files
echo "[1/5] Device Files Check"
if [ -e /dev/kfd ]; then
    echo "  /dev/kfd exists [OK]"
    ls -l /dev/kfd
else
    echo "  /dev/kfd missing [FAIL]"
fi

if [ -e /dev/dri/card0 ]; then
    echo "  /dev/dri/card0 exists [OK]"
    ls -l /dev/dri/card0
else
    echo "  /dev/dri/card0 missing [FAIL]"
fi

if [ -e /dev/dri/renderD128 ]; then
    echo "  /dev/dri/renderD128 exists [OK]"
    ls -l /dev/dri/renderD128
else
    echo "  /dev/dri/renderD128 missing (optional) [WARN]"
fi

echo ""

# Check 2: ROCm SMI
echo "[2/5] ROCm System Management"
if command -v rocm-smi &>/dev/null; then
    rocm-smi || echo "  rocm-smi failed [WARN]"
else
    echo "  rocm-smi not installed (normal in some containers) [INFO]"
fi

echo ""

# Check 3: OpenCL / HIP
echo "[3/5] OpenCL/HIP Devices"
if command -v clinfo &>/dev/null; then
    clinfo | grep -E 'Platform Name|Device Name|Device Type' || echo "  clinfo failed [WARN]"
else
    echo "  clinfo not installed [INFO]"
fi

echo ""

# Check 4: HSA Environment
echo "[4/5] HSA Environment Variables"
env | grep -E 'HSA|ROC|HIP' || echo "  No HSA/ROC/HIP vars set [INFO]"

echo ""

# Check 5: Ollama GPU Detection (if Ollama running)
echo "[5/5] Ollama GPU Detection"
if command -v ollama &>/dev/null; then
    echo "Checking Ollama logs for GPU detection..."
    journalctl -u ollama --no-pager --lines=50 2>/dev/null | grep -iE 'hip|rocm|gpu' || \
    echo "  Check docker logs ollama manually [INFO]"
else
    echo "  Ollama not in PATH (run from host: docker logs jbot_ollama) [INFO]"
fi

echo ""
echo "=== ROCm Check Complete ==="
