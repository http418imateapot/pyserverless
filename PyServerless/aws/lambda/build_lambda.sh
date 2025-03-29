#!/bin/bash

# Exit on error
set -e

# Define colors for terminal output (VT100)
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Help text
show_help() {
    echo "Usage: $(basename "$0") [OPTIONS]"
    echo
    echo "Package AWS Lambda functions into deployment-ready zip files"
    echo
    echo "Options:"
    echo "  -h, --help             Show this help message and exit"
    echo "  -p, --package DIR      Specify the package directory to build"
    echo
    echo "If no package directory is specified, the script will search for"
    echo "directories ending with '_package' that contain a lambda_function.py file"
    echo "and prompt you to select one."
    echo
}

# Parse command line arguments
PACKAGE_DIR=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            show_help
            exit 0
            ;;
        -p|--package)
            if [[ -z "$2" || "$2" == -* ]]; then
                echo -e "${RED}[ERROR] Option $1 requires an argument${NC}" >&2
                exit 1
            fi
            PACKAGE_DIR="$2"
            shift 2
            ;;
        *)
            echo -e "${RED}[ERROR] Unknown option: $1${NC}" >&2
            show_help
            exit 1
            ;;
    esac
done

# Check Python and pip installation in a user-friendly way - continue regardless
PYTHON_INSTALLED=false
PIP_INSTALLED=false

# Check Python with friendly messaging
if command -v python3 &> /dev/null; then
    PYTHON_CMD="python3"
    PYTHON_INSTALLED=true
elif command -v python &> /dev/null; then
    PYTHON_CMD="python"
    PYTHON_INSTALLED=true
else
    echo -e "${YELLOW}[Environment] We couldn't find Python on your system${NC}"
    echo -e "${YELLOW}You can install Python from python.org if you need dependency management${NC}"
fi

# Display Python version if installed
if [ "$PYTHON_INSTALLED" = true ]; then
    PYTHON_VERSION=$($PYTHON_CMD --version 2>&1 | sed 's/Python //')
    echo -e "${CYAN}[Environment] Found Python $PYTHON_VERSION on your system${NC}"
fi

# Check pip with friendly messaging
if command -v pip3 &> /dev/null; then
    PIP_CMD="pip3"
    PIP_INSTALLED=true
elif command -v pip &> /dev/null; then
    PIP_CMD="pip"
    PIP_INSTALLED=true
else
    echo -e "${YELLOW}[Environment] We couldn't find pip on your system${NC}"
    echo -e "${YELLOW}pip usually comes with Python and is needed for installing dependencies${NC}"
fi

# Display pip version if installed
if [ "$PIP_INSTALLED" = true ]; then
    PIP_VERSION=$($PIP_CMD --version | sed 's/pip \([0-9.]*\).*/\1/')
    echo -e "${CYAN}[Environment] Found pip $PIP_VERSION on your system${NC}"
fi

# Let user know what will happen without Python/pip
if [ "$PYTHON_INSTALLED" = false ] || [ "$PIP_INSTALLED" = false ]; then
    echo -e "${YELLOW}[Note] We'll continue with packaging, but without Python/pip,${NC}"
    echo -e "${YELLOW}       any dependencies in requirements.txt won't be included.${NC}"
    echo -e "${YELLOW}       This might be OK if your function doesn't have external dependencies.${NC}"
    echo ""
fi

# Store original directory
ORIGINAL_DIR=$(pwd)

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"

# If no package directory specified, find eligible directories
if [[ -z "$PACKAGE_DIR" ]]; then
    echo -e "${CYAN}[Info] No package directory specified, looking for Lambda functions...${NC}"
    
    # Find all *_package directories with lambda_function.py (only in first level, excluding build and dist)
    PACKAGE_DIRS=()
    
    # Get direct subdirectories only
    for dir in "$SCRIPT_DIR"/*; do
        # Skip if not a directory
        if [[ ! -d "$dir" ]]; then
            continue
        fi
        
        # Skip build and dist directories
        base_name=$(basename "$dir")
        if [[ "$base_name" == "build" || "$base_name" == "dist" ]]; then
            continue
        fi
        
        # Check if it's a valid package directory
        if [[ "$base_name" == *_package && -f "$dir/lambda_function.py" ]]; then
            PACKAGE_DIRS+=("$dir")
        fi
    done
    
    # Check if any eligible directories were found
    if [[ ${#PACKAGE_DIRS[@]} -eq 0 ]]; then
        echo -e "${RED}[Error] No eligible package directories found${NC}"
        echo -e "${YELLOW}Note: We looked for directories ending with '_package' that contain a lambda_function.py file${NC}"
        echo -e "${YELLOW}      in the same directory as this script${NC}"
        exit 1
    fi
    
    # Always show directory selection menu, even for a single directory
    echo -e "${CYAN}[Info] Package directories found:${NC}"
    for i in "${!PACKAGE_DIRS[@]}"; do
        echo -e "  ${BLUE}[$((i+1))]${NC} ${PACKAGE_DIRS[$i]}"
    done
    
    # Prompt user for selection
    while true; do
        read -p "Enter the number of the package directory to build [1-${#PACKAGE_DIRS[@]}]: " selection
        if [[ "$selection" =~ ^[0-9]+$ ]] && (( selection >= 1 && selection <= ${#PACKAGE_DIRS[@]} )); then
            PACKAGE_DIR="${PACKAGE_DIRS[$((selection-1))]}"
            break
        else
            echo -e "${RED}[Error] Invalid selection. Please enter a number between 1 and ${#PACKAGE_DIRS[@]}${NC}"
        fi
    done
fi

# Verify the selected package directory
if [[ ! -d "$PACKAGE_DIR" ]]; then
    echo -e "${RED}[Error] Package directory does not exist: $PACKAGE_DIR${NC}"
    exit 1
fi

if [[ ! -f "$PACKAGE_DIR/lambda_function.py" ]]; then
    echo -e "${RED}[Error] lambda_function.py not found in $PACKAGE_DIR${NC}"
    exit 1
fi

echo -e "${CYAN}[Info] Using package directory: $PACKAGE_DIR${NC}"

# Get the package name from the directory name
PACKAGE_NAME=$(basename "$PACKAGE_DIR")
echo -e "${CYAN}[Info] Package name: $PACKAGE_NAME${NC}"

# Check and install development dependencies if present and Python/pip are available
if [ "$PYTHON_INSTALLED" = true ] && [ "$PIP_INSTALLED" = true ] && [[ -f "$PACKAGE_DIR/requirements-dev.txt" ]]; then
    echo -e "${CYAN}[Info] Installing development dependencies...${NC}"
    if ! $PIP_CMD install -r "$PACKAGE_DIR/requirements-dev.txt"; then
        echo -e "${YELLOW}[Warning] Some development dependencies could not be installed${NC}"
        echo -e "${YELLOW}This may not affect packaging, proceeding anyway...${NC}"
    fi
elif [[ -f "$PACKAGE_DIR/requirements-dev.txt" ]]; then
    echo -e "${YELLOW}[Warning] Found requirements-dev.txt but Python/pip is not available${NC}"
    echo -e "${YELLOW}Development dependencies will not be installed${NC}"
fi

# Check compression tools with clearer messaging
if command -v 7z &> /dev/null; then
    COMPRESS_TOOL="7z"
    COMPRESS_CMD="7z a -tzip"
elif command -v zip &> /dev/null; then
    COMPRESS_TOOL="zip"
    COMPRESS_CMD="zip -r"
else
    echo -e "${RED}[Error] We couldn't find any compression tools on your system${NC}"
    echo -e "${YELLOW}To create Lambda packages, you need one of the following:${NC}"
    echo -e "${YELLOW}  • 7-Zip (recommended)${NC}"
    echo -e "${YELLOW}  • zip command (common on Linux and macOS)${NC}"
    exit 1
fi

echo -e "${CYAN}[Info] Using $COMPRESS_TOOL to create the package${NC}"

# Create dist directory
echo -e "${CYAN}[Info] Creating dist directory...${NC}"
DIST_PATH="$SCRIPT_DIR/dist/$PACKAGE_NAME"
mkdir -p "$DIST_PATH"

# Define output file name with correct extension
OUTPUT_FILE="lambda_function.zip"
echo -e "${CYAN}[Info] Output file will be: $OUTPUT_FILE${NC}"

# Define build directory with package name
BUILD_PATH="$SCRIPT_DIR/build/$PACKAGE_NAME"
echo -e "${CYAN}[Info] Using build path: $BUILD_PATH${NC}"

# Define pip target directory as a subdirectory
PIP_TARGET_PATH="$BUILD_PATH/package"
echo -e "${CYAN}[Info] Python packages will be installed to: $PIP_TARGET_PATH${NC}"

# Clean up any existing files
echo -e "${CYAN}[Info] Cleaning up old files...${NC}"
rm -rf "$BUILD_PATH"
rm -f "$DIST_PATH/$OUTPUT_FILE"

# Create package directory
mkdir -p "$BUILD_PATH"
mkdir -p "$PIP_TARGET_PATH"

# Install dependencies if requirements.txt exists and Python/pip are available
if [ "$PYTHON_INSTALLED" = true ] && [ "$PIP_INSTALLED" = true ] && [[ -f "$PACKAGE_DIR/requirements.txt" ]]; then
    echo -e "${CYAN}[Info] Installing dependencies...${NC}"
    if ! $PIP_CMD install -r "$PACKAGE_DIR/requirements.txt" --target "$PIP_TARGET_PATH"; then
        echo -e "${RED}[ERROR] Failed to install dependencies from requirements.txt${NC}"
        echo -e "${RED}This is critical for your Lambda function to work correctly.${NC}"
        echo -e "${RED}Please check your requirements.txt file and try again.${NC}"
        cd "$ORIGINAL_DIR"
        exit 1
    fi
elif [[ -f "$PACKAGE_DIR/requirements.txt" ]]; then
    echo -e "${RED}[ERROR] Found requirements.txt but Python/pip is not available${NC}"
    echo -e "${RED}Dependencies are required for your Lambda function to work correctly.${NC}"
    echo -e "${RED}Please install Python and pip, then try again.${NC}"
    cd "$ORIGINAL_DIR"
    exit 1
else
    echo -e "${CYAN}[Info] No requirements.txt found, skipping dependency installation${NC}"
fi

# Copy lambda function
echo -e "${CYAN}[Info] Copying lambda function...${NC}"
if ! cp "$PACKAGE_DIR/lambda_function.py" "$BUILD_PATH/"; then
    echo -e "${RED}[Error] Failed to copy lambda_function.py${NC}"
    echo -e "${YELLOW}Check file permissions and try again${NC}"
    exit 1
fi

# Copy any additional files from package directory
echo -e "${CYAN}[Info] Copying additional files from package directory...${NC}"
for file in "$PACKAGE_DIR"/*; do
    if [[ "$(basename "$file")" != "lambda_function.py" && "$(basename "$file")" != "requirements.txt" && "$(basename "$file")" != "requirements-dev.txt" ]]; then
        if [[ -f "$file" ]]; then
            echo -e "${CYAN}[Info] Copying: $(basename "$file")${NC}"
            cp "$file" "$BUILD_PATH/"
        fi
    fi
done

# Create package with better error handling
echo -e "${CYAN}[Info] Creating the Lambda package...${NC}"
cd "$BUILD_PATH"
ERROR_MSG=""
ERROR_DETAILS=""

case "$COMPRESS_TOOL" in
    "7z")
        ERROR_DETAILS=$(($COMPRESS_CMD "$DIST_PATH/$OUTPUT_FILE" * 2>&1) || echo "Failed")
        if [[ "$ERROR_DETAILS" == *"Failed"* ]]; then 
            ERROR_MSG="7-Zip couldn't create the archive"
        fi
        ;;
    "zip")
        ERROR_DETAILS=$(($COMPRESS_CMD "$DIST_PATH/$OUTPUT_FILE" . 2>&1) || echo "Failed")
        if [[ "$ERROR_DETAILS" == *"Failed"* ]]; then 
            ERROR_MSG="The zip command couldn't create the archive"
        fi
        ;;
esac

if [ -n "$ERROR_MSG" ]; then
    echo -e "${RED}[Error] Package creation failed${NC}"
    echo -e "${RED}Reason: $ERROR_MSG${NC}"
    echo -e "${RED}Details: $ERROR_DETAILS${NC}"
    
    # Provide more helpful diagnostics based on common issues
    if [[ "$ERROR_DETAILS" == *"permission denied"* || "$ERROR_DETAILS" == *"Permission denied"* ]]; then
        echo -e "${YELLOW}This looks like a permissions issue. Try:${NC}"
        echo -e "${YELLOW}• Making sure you have write access to the output directory${NC}"
        echo -e "${YELLOW}• Checking if another program is using the zip file${NC}"
    elif [[ "$ERROR_DETAILS" == *"command not found"* || "$ERROR_DETAILS" == *"No such file"* ]]; then
        echo -e "${YELLOW}The compression tool may not be properly installed or in your PATH${NC}"
    elif [[ "$ERROR_DETAILS" == *"No space left on device"* ]]; then
        echo -e "${YELLOW}You may be out of disk space. Try freeing up some space and try again.${NC}"
    fi
    
    cd "$ORIGINAL_DIR"
    exit 1
fi

cd "$ORIGINAL_DIR"
echo -e "${GREEN}[Success] Your Lambda function has been packaged successfully!${NC}"
echo -e "${GREEN}          Location: $DIST_PATH/$OUTPUT_FILE${NC}"
