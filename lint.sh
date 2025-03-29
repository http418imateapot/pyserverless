#!/bin/sh

if [ -n "$1" ]; then
    ROOT_PATH="$1"
else
    ROOT_PATH="PyServerless"
fi

# Lint Python files
if [ -d "$ROOT_PATH" ]; then
    echo "Linting Python files in $ROOT_PATH..."
    autopep8 ./$ROOT_PATH --in-place --recursive
    
    PEP8_ERROR_COUNT_CMD="pycodestyle --ignore=E501,W504 ./$ROOT_PATH"
    PEP8_ERROR_COUNT=$($PEP8_ERROR_COUNT_CMD | wc -l)
    
    if [ "$PEP8_ERROR_COUNT" -eq 0 ]; then
        echo "PEP8 passed, no linting errors found."
    else
        $PEP8_ERROR_COUNT_CMD
        echo "==============================="
        echo "PEP8 failed with $PEP8_ERROR_COUNT errors."
    fi
else
    echo "Directory $ROOT_PATH does not exist. Skipping Python linting."
fi

# Lint Bash scripts
echo "Linting Bash scripts..."
BASH_SCRIPTS=$(find . -name "*.sh" -type f -not -path "*/\.*" -not -path "*/node_modules/*" -not -path "*/venv/*")
if [ -n "$BASH_SCRIPTS" ]; then
    if command -v shellcheck > /dev/null; then
        SHELLCHECK_ERRORS=0
        for script in $BASH_SCRIPTS; do
            echo "Checking $script"
            if ! shellcheck -x "$script"; then
                SHELLCHECK_ERRORS=$((SHELLCHECK_ERRORS + 1))
            fi
        done
        
        if [ "$SHELLCHECK_ERRORS" -eq 0 ]; then
            echo "ShellCheck passed, no errors found in Bash scripts."
        else
            echo "==============================="
            echo "ShellCheck failed with errors in $SHELLCHECK_ERRORS scripts."
        fi
    else
        echo "ShellCheck not installed. Skipping Bash linting."
        echo "Install it with: apt-get install shellcheck or brew install shellcheck"
    fi
else
    echo "No Bash scripts found."
fi

# Lint PowerShell scripts
echo "Linting PowerShell scripts..."
PS1_SCRIPTS=$(find . -name "*.ps1" -type f -not -path "*/\.*" -not -path "*/node_modules/*" -not -path "*/venv/*")
if [ -n "$PS1_SCRIPTS" ]; then
    if command -v pwsh > /dev/null; then
        PS_ERRORS=0
        for script in $PS1_SCRIPTS; do
            echo "Checking $script"
            if ! pwsh -Command "Invoke-ScriptAnalyzer -Path \"$script\" -Settings PSScriptAnalyzerSettings.psd1 2>/dev/null || Invoke-ScriptAnalyzer -Path \"$script\""; then
                PS_ERRORS=$((PS_ERRORS + 1))
            fi
        done
        
        if [ "$PS_ERRORS" -eq 0 ]; then
            echo "PowerShell Script Analyzer passed, no errors found in PowerShell scripts."
        else
            echo "==============================="
            echo "PowerShell Script Analyzer failed with errors in $PS_ERRORS scripts."
        fi
    else
        echo "PowerShell Core (pwsh) not installed. Skipping PowerShell linting."
        echo "Install it from: https://github.com/PowerShell/PowerShell"
    fi
else
    echo "No PowerShell scripts found."
fi
