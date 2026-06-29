<#
.SYNOPSIS
    Imports the script analyzer module and exits with a non-zero exit code if
    any issues are found.
.DESCRIPTION
    This script runs the PowerShell script analyzer for the build or as a
    pre-commit hook. If the PSScriptAnalyzer module is not found, it will be
    installed for the user.
#>
begin {
    # When you run `pre-commit run --all` or when pre-commit runs with multiple
    # files, it does so with `xargs` (basically), so instead of getting a
    # comma-delimited list (like PowerShell wants), you get a space-delimited
    # list. That's why you see $args getting used here as the list of files
    # instead of an array parameter.
    $enableVerbose = $false
    if ($Env:RUNNER_DEBUG) {
        $enableVerbose = $true
    }

    function Write-Result {
        param(
            [Parameter(Mandatory = $true)]
            $result
        )

        $severity = $result.Severity.ToString().ToLower()
        if ($severity -ne 'warning' -and $severity -ne 'error') {
            $severity = 'warning'
        }
        $message = "$($result.ScriptPath)($($result.Line),$($result.Column)) $severity $($result.RuleName): $($result.Message)"
        if ($Env:GITHUB_ACTIONS) {
            Write-Output "::${severity} file=$($result.ScriptPath),line=$($result.Line),col=$($result.Column)::$($result.RuleName): $($result.Message)"
        }
        else {
            if ($severity -eq 'warning') {
                Write-Warning $message
            }
            else {
                Write-Error $message
            }
        }
    }

    $analyzerModule = Import-Module PSScriptAnalyzer -PassThru -ErrorAction SilentlyContinue -Verbose:$enableVerbose
    if (-not $analyzerModule) {
        throw 'Install the PSScriptAnalyzer module: Install-Module PSScriptAnalyzer -Scope CurrentUser -Force'
    }

    Write-Verbose "PSScriptAnalyzer version: $($analyzerModule.Version)" -Verbose:$enableVerbose
    $analysisResults = @()
}
process {
    try {
        if ($args) {
            $args | ForEach-Object {
                $analysisResults += Invoke-ScriptAnalyzer -Path $_ -Settings $PSScriptRoot/../../PSScriptAnalyzerSettings.psd1 -Verbose:$enableVerbose -ErrorAction SilentlyContinue
            }
        }
        else {
            $analysisResults = Invoke-ScriptAnalyzer -Path $PSScriptRoot/../.. -Recurse -Settings $PSScriptRoot/../../PSScriptAnalyzerSettings.psd1 -Verbose:$enableVerbose -ErrorAction SilentlyContinue
        }
    }
    catch {
        Write-Error "Error executing script analyzer: $_`: $($_.ScriptStackTrace)"
        exit 1
    }
}
end {
    if ($analysisResults) {
        Write-Error 'Script analyzer found issues.'
        $analysisResults | ForEach-Object {
            Write-Result $_
        }
        exit 1
    }

    Write-Verbose 'No script analyzer issues found.' -Verbose:$enableVerbose
    exit 0
}
