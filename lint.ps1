# Lint.ps1

param (
    [string]$RootPath = "PyServerless"
)

# Lint Python files
if (Test-Path $RootPath) {
    Write-Host "Linting Python files in $RootPath..."
    autopep8 --in-place --recursive $RootPath

    $pep8Errors = pycodestyle --ignore=E501,W504 $RootPath | Out-String
    $pep8ErrorCount = ($pep8Errors -split "`n").Count - 1

    if ($pep8ErrorCount -eq 0) {
        Write-Host "PEP8 passed, no linting errors found."
    } else {
        Write-Host $pep8Errors
        Write-Host "==============================="
        Write-Host "PEP8 failed with $pep8ErrorCount errors."
    }
} else {
    Write-Host "Directory $RootPath does not exist. Skipping Python linting."
}

# Lint Bash scripts
Write-Host "Linting Bash scripts..."
$bashScripts = Get-ChildItem -Recurse -Include *.sh -File | Where-Object { $_.FullName -notmatch "\\\." -and $_.FullName -notmatch "node_modules" -and $_.FullName -notmatch "venv" }
if ($bashScripts) {
    if (Get-Command shellcheck -ErrorAction SilentlyContinue) {
        $shellCheckErrors = 0
        foreach ($script in $bashScripts) {
            Write-Host "Checking $($script.FullName)"
            if (-not (shellcheck -x $script.FullName)) {
                $shellCheckErrors++
            }
        }

        if ($shellCheckErrors -eq 0) {
            Write-Host "ShellCheck passed, no errors found in Bash scripts."
        } else {
            Write-Host "==============================="
            Write-Host "ShellCheck failed with errors in $shellCheckErrors scripts."
        }
    } else {
        Write-Host "ShellCheck not installed. Skipping Bash linting."
        Write-Host "Install it with: apt-get install shellcheck or brew install shellcheck"
    }
} else {
    Write-Host "No Bash scripts found."
}

# Lint PowerShell scripts
Write-Host "Linting PowerShell scripts..."
$ps1Scripts = Get-ChildItem -Recurse -Include *.ps1 -File | Where-Object { $_.FullName -notmatch "\\\." -and $_.FullName -notmatch "node_modules" -and $_.FullName -notmatch "venv" }
if ($ps1Scripts) {
    if (Get-Command pwsh -ErrorAction SilentlyContinue) {
        $psErrors = 0
        foreach ($script in $ps1Scripts) {
            Write-Host "Checking $($script.FullName)"
            if (-not (pwsh -Command "Invoke-ScriptAnalyzer -Path '$($script.FullName)' -Settings PSScriptAnalyzerSettings.psd1 -ErrorAction SilentlyContinue; Invoke-ScriptAnalyzer -Path '$($script.FullName)'")) {
                $psErrors++
            }
        }

        if ($psErrors -eq 0) {
            Write-Host "PowerShell Script Analyzer passed, no errors found in PowerShell scripts."
        } else {
            Write-Host "==============================="
            Write-Host "PowerShell Script Analyzer failed with errors in $psErrors scripts."
        }
    } else {
        Write-Host "PowerShell Core (pwsh) not installed. Skipping PowerShell linting."
        Write-Host "Install it from: https://github.com/PowerShell/PowerShell"
    }
} else {
    Write-Host "No PowerShell scripts found."
}