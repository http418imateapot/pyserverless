# Parse command line arguments
param(
    [Parameter(Mandatory=$false)]
    [Alias("h")]
    [switch]$Help,
    
    [Parameter(Mandatory=$false)]
    [Alias("p")]
    [string]$PackageDir
)

# Help text function
function Show-Help {
    Write-Host "Usage: $(Split-Path -Leaf $MyInvocation.MyCommand.Path) [OPTIONS]"
    Write-Host ""
    Write-Host "Package AWS Lambda functions into deployment-ready zip files"
    Write-Host ""
    Write-Host "Options:"
    Write-Host "  -h, --help             Show this help message and exit"
    Write-Host "  -p, --package DIR      Specify the package directory to build"
    Write-Host ""
    Write-Host "If no package directory is specified, the script will search for"
    Write-Host "directories ending with '_package' that contain a lambda_function.py file"
    Write-Host "and prompt you to select one."
    Write-Host ""
}

if ($Help) {
    Show-Help
    exit 0
}

# Store original directory
$OriginalDir = Get-Location

# Check Python and pip installation in a user-friendly way - continue regardless
$pythonInstalled = $false
$pipInstalled = $false

try {
    $pythonVersionOutput = (python --version 2>&1).ToString()
    if ($pythonVersionOutput -match 'Python (\d+\.\d+\.\d+)') {
        $pythonVersion = $matches[1]
        Write-Host "[Environment] Found Python $pythonVersion on your system" -ForegroundColor Cyan
        $pythonInstalled = $true
    } else {
        Write-Host "[Environment] Python is installed, but we couldn't read its version" -ForegroundColor Cyan
        $pythonInstalled = $true
    }
} catch {
    Write-Host "[Environment] We couldn't find Python on your system" -ForegroundColor Yellow
    Write-Host "You can install Python from python.org if you need dependency management" -ForegroundColor Yellow
}

try {
    $pipVersionOutput = (pip --version 2>&1).ToString()
    if ($pipVersionOutput -match 'pip (\d+\.\d+(\.\d+)?)') {
        $pipVersion = $matches[1]
        Write-Host "[Environment] Found pip $pipVersion on your system" -ForegroundColor Cyan
        $pipInstalled = $true
    } else {
        Write-Host "[Environment] pip is installed, but we couldn't read its version" -ForegroundColor Cyan
        $pipInstalled = $true
    }
} catch {
    Write-Host "[Environment] We couldn't find pip on your system" -ForegroundColor Yellow
    Write-Host "pip usually comes with Python and is needed for installing dependencies" -ForegroundColor Yellow
}

# Let user know what will happen without Python/pip
if (-not $pythonInstalled -or -not $pipInstalled) {
    Write-Host "[Note] We'll continue with packaging, but without Python/pip," -ForegroundColor Yellow
    Write-Host "      any dependencies in requirements.txt won't be included." -ForegroundColor Yellow
    Write-Host "      This might be OK if your function doesn't have external dependencies." -ForegroundColor Yellow
    Write-Host ""
}

# Get script directory
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

# If no package directory specified, find eligible directories
if ([string]::IsNullOrEmpty($PackageDir)) {
    Write-Host "[Info] No package directory specified, looking for Lambda functions..." -ForegroundColor Cyan
    
    # Find all *_package directories with lambda_function.py (only in first level, excluding build and dist)
    $PackageDirs = @()
    Get-ChildItem -Path $ScriptDir -Directory | Where-Object { 
        $_.Name -like "*_package" -and 
        $_.Name -ne "build" -and 
        $_.Name -ne "dist" -and 
        (Test-Path (Join-Path $_.FullName "lambda_function.py"))
    } | ForEach-Object {
        $PackageDirs += $_.FullName
    }
    
    # Check if any eligible directories were found
    if ($PackageDirs.Count -eq 0) {
        Write-Host "[Error] No eligible package directories found" -ForegroundColor Red
        Write-Host "Note: We looked for directories ending with '_package' that contain a lambda_function.py file" -ForegroundColor Yellow
        Write-Host "      in the same directory as this script" -ForegroundColor Yellow
        Set-Location $OriginalDir
        exit 1
    }
    
    # Always show directory selection menu, even for a single directory
    Write-Host "[Info] Package directories found:" -ForegroundColor Cyan
    for ($i = 0; $i -lt $PackageDirs.Count; $i++) {
        Write-Host "  [$(($i+1))]" -ForegroundColor Blue -NoNewline
        Write-Host " $($PackageDirs[$i])"
    }
    
    # Prompt user for selection
    do {
        $selection = Read-Host "Enter the number of the package directory to build [1-$($PackageDirs.Count)]"
        $valid = [int]::TryParse($selection, [ref]$null) -and [int]$selection -ge 1 -and [int]$selection -le $PackageDirs.Count
        if (-not $valid) {
            Write-Host "[Error] Invalid selection. Please enter a number between 1 and $($PackageDirs.Count)" -ForegroundColor Yellow
        }
    } while (-not $valid)
    
    $PackageDir = $PackageDirs[[int]$selection - 1]
}

# Verify the selected package directory
if (-not (Test-Path $PackageDir -PathType Container)) {
    Write-Host "[Error] Package directory does not exist: $PackageDir" -ForegroundColor Red
    Set-Location $OriginalDir
    exit 1
}

if (-not (Test-Path (Join-Path $PackageDir "lambda_function.py"))) {
    Write-Host "[Error] lambda_function.py not found in $PackageDir" -ForegroundColor Red
    Set-Location $OriginalDir
    exit 1
}

Write-Host "[Info] Using package directory: $PackageDir" -ForegroundColor Cyan

# Get the package name from the directory name
$PackageName = Split-Path -Leaf $PackageDir
Write-Host "[Info] Package name: $PackageName" -ForegroundColor Cyan

# Check and install development dependencies if present and Python/pip are available
$devRequirementsPath = Join-Path $PackageDir "requirements-dev.txt"
if ($pythonInstalled -and $pipInstalled -and (Test-Path $devRequirementsPath)) {
    Write-Host "[Info] Installing development dependencies..." -ForegroundColor Cyan
    try {
        pip install -r $devRequirementsPath
        if ($LASTEXITCODE -ne 0) { 
            Write-Host "[Warning] Some development dependencies could not be installed" -ForegroundColor Yellow
            Write-Host "This may not affect packaging, proceeding anyway..." -ForegroundColor Yellow
        }
    } catch {
        Write-Host "[Warning] Error installing development dependencies: $($_.Exception.Message)" -ForegroundColor Yellow
        Write-Host "Proceeding with packaging anyway..." -ForegroundColor Yellow
    }
} elseif (Test-Path $devRequirementsPath) {
    Write-Host "[Warning] Found requirements-dev.txt but Python/pip is not available" -ForegroundColor Yellow
    Write-Host "Development dependencies will not be installed" -ForegroundColor Yellow
}

# Check compression tools with clearer messaging
$CompressTool = $null

if (Get-Command "7z" -ErrorAction SilentlyContinue) {
    $CompressTool = "7z"
} elseif (Get-Command "zip" -ErrorAction SilentlyContinue) {
    $CompressTool = "zip"
} else {
    Write-Host "[Error] We couldn't find any compression tools on your system" -ForegroundColor Red
    Write-Host "To create Lambda packages, you need one of the following:" -ForegroundColor Yellow
    Write-Host "  • 7-Zip (recommended): https://7-zip.org" -ForegroundColor Yellow
    Write-Host "  • Git Bash (includes zip command)" -ForegroundColor Yellow
    Set-Location $OriginalDir
    exit 1
}

Write-Host "[Info] Using $CompressTool to create the package" -ForegroundColor Cyan

# Create dist directory
Write-Host "[Info] Creating dist directory..." -ForegroundColor Cyan
$DistPath = Join-Path $ScriptDir "dist\$PackageName"
New-Item -ItemType Directory -Force -Path $DistPath | Out-Null

# Define build directory with package name
$BuildPath = Join-Path $ScriptDir "build\$PackageName"
Write-Host "[Info] Using build path: $BuildPath" -ForegroundColor Cyan

# Define pip target directory as a subdirectory
$PipTargetPath = Join-Path $BuildPath "package"
Write-Host "[Info] Python packages will be installed to: $PipTargetPath" -ForegroundColor Cyan

# Clean up any existing files
Write-Host "[Info] Cleaning up old files..." -ForegroundColor Cyan
if (Test-Path $BuildPath) { Remove-Item -Recurse -Force $BuildPath }
$zipPath = Join-Path $DistPath "lambda_function.zip"
if (Test-Path $zipPath) { Remove-Item -Force $zipPath }

# Create package directory
New-Item -ItemType Directory -Force -Path $BuildPath | Out-Null
New-Item -ItemType Directory -Force -Path $PipTargetPath | Out-Null

# Install dependencies if requirements.txt exists and Python/pip are available
$requirementsPath = Join-Path $PackageDir "requirements.txt"
if ($pythonInstalled -and $pipInstalled -and (Test-Path $requirementsPath)) {
    Write-Host "[Info] Installing dependencies..." -ForegroundColor Cyan
    try {
        pip install -r $requirementsPath --target $PipTargetPath
        if ($LASTEXITCODE -ne 0) { 
            Write-Host "[ERROR] Failed to install dependencies from requirements.txt" -ForegroundColor Red
            Write-Host "This is critical for your Lambda function to work correctly." -ForegroundColor Red
            Write-Host "Please check your requirements.txt file and try again." -ForegroundColor Red
            Set-Location $OriginalDir
            exit 1
        }
    } catch {
        Write-Host "[ERROR] Error installing dependencies: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "This is critical for your Lambda function to work correctly." -ForegroundColor Red
        Write-Host "Please check your requirements.txt file and try again." -ForegroundColor Red
        Set-Location $OriginalDir
        exit 1
    }
} elseif (Test-Path $requirementsPath) {
    Write-Host "[ERROR] Found requirements.txt but Python/pip is not available" -ForegroundColor Red
    Write-Host "Dependencies are required for your Lambda function to work correctly." -ForegroundColor Red
    Write-Host "Please install Python and pip, then try again." -ForegroundColor Red
    Set-Location $OriginalDir
    exit 1
} else {
    Write-Host "[Info] No requirements.txt found, skipping dependency installation" -ForegroundColor Cyan
}

# Copy lambda function
Write-Host "[Info] Copying lambda function..." -ForegroundColor Cyan
try {
    Copy-Item (Join-Path $PackageDir "lambda_function.py") -Destination $BuildPath
} catch {
    Write-Host "[Error] Failed to copy lambda_function.py: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Check file permissions and try again" -ForegroundColor Yellow
    Set-Location $OriginalDir
    exit 1
}

# Copy any additional files from the package directory
Write-Host "[Info] Copying additional files from package directory..." -ForegroundColor Cyan
Get-ChildItem -Path $PackageDir | Where-Object {
    $_.Name -ne "lambda_function.py" -and $_.Name -ne "requirements.txt" -and $_.Name -ne "requirements-dev.txt" -and -not $_.PSIsContainer
} | ForEach-Object {
    Write-Host "[Info] Copying: $($_.Name)" -ForegroundColor Cyan
    Copy-Item $_.FullName -Destination $BuildPath
}

# Create package with better error handling
Write-Host "[Info] Creating the Lambda package..." -ForegroundColor Cyan
Push-Location $BuildPath
try {
    $errorOutput = $null
    switch ($CompressTool) {
        "7z" { 
            $errorOutput = (& 7z a -tzip $zipPath * 2>&1)
            if ($LASTEXITCODE -ne 0) { 
                throw "7-Zip failed (exit code: $LASTEXITCODE). Error: $errorOutput"
            }
        }
        "zip" { 
            $errorOutput = (& zip -r $zipPath . 2>&1)
            if ($LASTEXITCODE -ne 0) { 
                throw "zip command failed (exit code: $LASTEXITCODE). Error: $errorOutput"
            }
        }
    }
} catch {
    Write-Host "[Error] Package creation failed" -ForegroundColor Red
    Write-Host "Reason: $($_.Exception.Message)" -ForegroundColor Red
    
    # Provide more helpful diagnostics based on common issues
    if ($_.Exception.Message -like "*Access is denied*" -or $_.Exception.Message -like "*permission*") {
        Write-Host "This looks like a permissions issue. Try:" -ForegroundColor Yellow
        Write-Host "• Running PowerShell as Administrator" -ForegroundColor Yellow
        Write-Host "• Checking if another program is using the zip file" -ForegroundColor Yellow
        Write-Host "• Making sure you have write access to the output directory" -ForegroundColor Yellow
    } elseif ($_.Exception.Message -like "*not recognized*" -or $_.Exception.Message -like "*not found*") {
        Write-Host "The compression tool may not be properly installed or in your PATH" -ForegroundColor Yellow
    } elseif ($_.Exception.Message -like "*No such file*") {
        Write-Host "Some files may be missing or inaccessible" -ForegroundColor Yellow
    }
    
    Pop-Location
    Set-Location $OriginalDir
    exit 1
}
Pop-Location

# Return to original directory
Set-Location $OriginalDir
Write-Host "[Success] Your Lambda function has been packaged successfully!" -ForegroundColor Green
Write-Host "          Location: $zipPath" -ForegroundColor Green
Write-Host "[Info] Returned to your original directory: $(Get-Location)" -ForegroundColor Cyan
