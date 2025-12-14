#!/bin/bash
#
# This script downloads and verifies apache commons release candidates.
# The script creates a directory "commons-release" in the current working directory and performs the following steps:
#
# 1. Downloads all files from the provided URL (excluding /site/ directories)
# 2. Runs the signature-validator.sh script to verify signatures and hashes
# 3. Extracts the source tarball and builds the project using 'mvn clean package site' with all available JDKs on the system
#
# Usage: ./test-commons-rc.sh url
# Example: ./test-commons-rc.sh  https://dist.apache.org/repos/dist/dev/commons/cli/1.11.0-RC1/

# Check that URL was provided
if [ -z "$1" ]; then
    echo "Error: URL argument required"
    echo "Usage: $0 url"
    exit 1
fi

URL="$1"
# Ensure URL ends with trailing slash
[[ "$URL" != */ ]] && URL="$URL/"

WORK_DIR="commons-release"
SOURCES_DIR="${WORK_DIR}/source"

rm -rf "$WORK_DIR"

# Create and enter work directory
echo "Creating local directory: $WORK_DIR"
mkdir -p "$WORK_DIR"
cd "$WORK_DIR"

# Download the directory and its subdirectories
echo "Downloading files from: $URL"
wget -r -np -nH --cut-dirs=6 --reject-regex="/site/" -e robots=off "$URL"

# Verify files were downloaded
if [ ! -f "signature-validator.sh" ]; then
    echo "Error: Download failed - signature-validator.sh not found"
    exit 1
fi

# Run signature validator
echo ""
echo "=========================================="
echo "Running signature validator..."
echo "=========================================="
if [ -f "signature-validator.sh" ]; then
    if bash signature-validator.sh | tee sig-validate.log | grep -q "SUCCESSFUL VALIDATION"; then
        echo "Signature validation successful"
    else
        echo "Signature validation failed or did not complete successfully"
        echo "Validator output:"
        cat sig-validate.log
    fi
else
    echo "Warning: signature-validator.sh not found"
fi

# Extract source tarball and build
echo ""
echo "=========================================="
echo "Extracting and building source..."
echo "=========================================="

cd "source"

# Find and extract the source tarball from commons-release
SOURCE_TARBALL=$(ls *.tar.gz | head -1)
if [ -z "$SOURCE_TARBALL" ]; then
    echo "Error: No source tarball found in $WORK_DIR/source"
    ls -la "$WORK_DIR/source"
    exit 1
fi

echo "Extracting: $SOURCE_TARBALL"
tar -xzf "$SOURCE_TARBALL"

# Get the extracted directory name
EXTRACTED_DIR=$(tar -tzf "$SOURCE_TARBALL" | head -1 | cut -d/ -f1)
echo "Entering extracted directory: $EXTRACTED_DIR"

if [ -z "$EXTRACTED_DIR" ] || [ ! -d "$EXTRACTED_DIR" ]; then
    echo "Error: Failed to extract source"
    exit 1
fi

cd "$EXTRACTED_DIR"

# Get list of available JDKs
echo ""
echo "=========================================="
echo "Finding installed JDKs..."
echo "=========================================="

JDKS=$(update-alternatives --list java 2>/dev/null || echo "")
if [ -z "$JDKS" ]; then
    echo "Warning: No JDKs found via update-alternatives"
    echo "Building with current JDK..."
    JDKS="default"
fi

# Initialize version tracking
VERSION_LOG="../test-versions.log"
> "$VERSION_LOG"

# Initialize build results tracking
SUCCESSFUL_BUILDS=()
FAILED_BUILDS=()

# Build with each available JDK
for JDK in $JDKS; do
    echo ""
    echo "=========================================="
    
    # Determine JDK identifier for log filename
    if [ "$JDK" != "default" ]; then
        echo "Setting JDK to: $JDK"
        sudo update-alternatives --set java "$JDK"
        export JAVA_HOME=$(dirname $(dirname "$JDK"))
        JDK_NAME=$(java -version 2>&1 | head -1 | sed 's/.*"\([^"]*\)".*/\1/' | tr ' ' '-')
    else
        echo "Building with default JDK"
        JDK_NAME="default"
    fi
    echo "=========================================="
    
    # Capture version info
    echo "" >> "$VERSION_LOG"
    echo "Testing with:" >> "$VERSION_LOG"
    java -version 2>&1 | tee -a "$VERSION_LOG"
    mvn --version 2>&1 | tee -a "$VERSION_LOG"
    
    BUILD_LOG="../mvn-build-${JDK_NAME}.log"
    echo "Running: mvn clean install site"
    if mvn clean install site | tee "$BUILD_LOG" | grep -q "BUILD SUCCESS"; then
        echo "Build successful with JDK: $JDK"
        echo ""
        echo "Maven info:"
        mvn --version
        SUCCESSFUL_BUILDS+=("$JDK_NAME")
    else
        echo "Build failed with JDK: $JDK"
        echo "Maven output:"
        tail -20 "$BUILD_LOG"
        FAILED_BUILDS+=("$JDK_NAME")
    fi
done

echo ""
echo "=========================================="
echo "Testing completed"
echo "=========================================="
echo ""
echo "Summary of test environments:"
echo "=========================================="
cat "$VERSION_LOG"
echo "=========================================="
echo ""

# Report build results
if [ ${#FAILED_BUILDS[@]} -eq 0 ]; then
    echo "All JDK builds were successful."
else
    echo "Build failures detected:"
    for failed_jdk in "${FAILED_BUILDS[@]}"; do
        echo "  - $failed_jdk"
    done
fi
