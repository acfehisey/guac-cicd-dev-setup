[CmdletBinding()]
param(
    [switch]$InstallCodex,
    [switch]$InstallAwsAgentToolkit,
    [string]$AwsDefaultRegion,
    [string]$AwsAgentToolkitRegion = 'us-east-1'
)

$ErrorActionPreference = 'Stop'

function Test-CommandAvailable {
    param([string]$Name)
    return $null -ne (Get-Command $Name -ErrorAction SilentlyContinue)
}

function Invoke-NativeCommand {
    param(
        [Parameter(Mandatory = $true)]
        [string]$FilePath,
        [string[]]$ArgumentList = @(),
        [string]$ErrorMessage = 'Native command failed.'
    )

    & $FilePath @ArgumentList
    if ($LASTEXITCODE -ne 0) {
        throw "$ErrorMessage Exit code: $LASTEXITCODE"
    }
}

function Ensure-WingetPackage {
    param(
        [string]$PackageId,
        [string]$DisplayName
    )

    $installed = winget list --id $PackageId --exact 2>$null | Select-String $PackageId
    if (-not $installed) {
        Write-Host "Installing $DisplayName..."
        Invoke-NativeCommand -FilePath 'winget' -ArgumentList @('install', '--id', $PackageId, '--source', 'winget', '--accept-source-agreements', '--accept-package-agreements', '--silent') -ErrorMessage "Failed to install $DisplayName."
    }
    else {
        Write-Host "$DisplayName is installed. Updating..."
        winget upgrade --id $PackageId --source winget --accept-source-agreements --accept-package-agreements --silent
        if ($LASTEXITCODE -ne 0) {
            Write-Warning "winget upgrade returned exit code $LASTEXITCODE for $DisplayName. Continuing because the package may already be current."
        }
    }
}

function Ensure-VisualStudioCodeExtensions {
    param([string[]]$Extensions)

    if (-not (Test-CommandAvailable -Name 'code')) {
        Write-Host "Visual Studio Code CLI not found. Please install VS Code first, restart PowerShell, and rerun this script."
        return
    }

    foreach ($extension in $Extensions) {
        Write-Host "Installing VS Code extension: $extension"
        Invoke-NativeCommand -FilePath 'code' -ArgumentList @('--install-extension', $extension, '--force') -ErrorMessage "Failed to install VS Code extension $extension."
    }
}

function Get-JsonSettingsHashtable {
    param([string]$Path)

    $settings = [ordered]@{}
    if (Test-Path $Path) {
        $rawJson = Get-Content -Path $Path -Raw
        if (-not [string]::IsNullOrWhiteSpace($rawJson)) {
            $settingsObject = $rawJson | ConvertFrom-Json
            foreach ($property in $settingsObject.PSObject.Properties) {
                $settings[$property.Name] = $property.Value
            }
        }
    }

    return $settings
}

function Ensure-AwsCliForAgentToolkit {
    if (Test-CommandAvailable -Name 'aws') {
        Write-Host "AWS CLI is available:"
        & aws --version
        return
    }

    Write-Host "AWS CLI was not found in PATH. Installing AWS CLI v2 with the AWS PowerShell installer..."
    irm 'https://awscli.amazonaws.com/v2/install.ps1' | iex

    if (-not (Test-CommandAvailable -Name 'aws')) {
        throw "AWS CLI installation completed, but 'aws' is not available in this PowerShell session. Restart PowerShell and rerun this script."
    }
}

function Install-AwsAgentToolkitForCodex {
    param(
        [string]$DefaultRegion,
        [string]$ToolkitRegion
    )

    if ([string]::IsNullOrWhiteSpace($DefaultRegion)) {
        throw "Use -AwsDefaultRegion with -InstallAwsAgentToolkit, for example: -AwsDefaultRegion us-east-2."
    }

    Write-Host "Checking network access to https://awscli.amazonaws.com/v2/install.ps1..."
    try {
        Invoke-WebRequest -Uri 'https://awscli.amazonaws.com/v2/install.ps1' -Method Head -UseBasicParsing -TimeoutSec 15 | Out-Null
    }
    catch {
        throw "Cannot reach https://awscli.amazonaws.com/v2/install.ps1. Verify internet connectivity or firewall rules, then rerun this script. $($_.Exception.Message)"
    }

    Ensure-AwsCliForAgentToolkit

    Write-Host "AWS Agent Toolkit setup uses browser-based 'aws login'."
    Write-Host "Do not enter AWS access keys or secret keys into this script."
    Write-Host "Credentials are valid for 12 hours and can be renewed for 90 days without re-authenticating in the browser."

    Invoke-NativeCommand -FilePath 'aws' -ArgumentList @('configure', 'set', 'region', $DefaultRegion) -ErrorMessage "Failed to configure default AWS Region."
    Invoke-NativeCommand -FilePath 'aws' -ArgumentList @('login', '--region', $DefaultRegion) -ErrorMessage "AWS login failed. Complete browser authentication and rerun if needed."
    Invoke-NativeCommand -FilePath 'aws' -ArgumentList @('sts', 'get-caller-identity') -ErrorMessage "AWS credential verification failed."

    Write-Host "Configuring AWS Agent Toolkit in $ToolkitRegion..."
    & aws configure agent-toolkit --yes --region $ToolkitRegion
    if ($LASTEXITCODE -ne 0) {
        Write-Warning "AWS CLI did not accept 'aws configure agent-toolkit --yes'. Retrying without --yes."
        Invoke-NativeCommand -FilePath 'aws' -ArgumentList @('configure', 'agent-toolkit', '--region', $ToolkitRegion) -ErrorMessage "AWS Agent Toolkit configuration failed."
    }

    Invoke-NativeCommand -FilePath 'aws' -ArgumentList @('agent-toolkit', 'list-available-skills', '--region', $ToolkitRegion) -ErrorMessage "AWS Agent Toolkit verification failed."

    $rulesUrl = 'https://raw.githubusercontent.com/aws/agent-toolkit-for-aws/refs/heads/main/rules/aws-agent-rules.md'
    $rulesPath = Join-Path (Get-Location) 'AGENTS.md'
    $rulesDir = Split-Path $rulesPath -Parent
    if (-not (Test-Path $rulesDir)) {
        New-Item -ItemType Directory -Path $rulesDir -Force | Out-Null
    }

    Write-Host "Writing AWS guidance for Codex to $rulesPath..."
    Invoke-WebRequest -Uri $rulesUrl -OutFile $rulesPath -UseBasicParsing
}

Write-Host "Checking for required Windows tooling..."

# Git for Git Bash and Git tools
if (-not (Test-CommandAvailable -Name 'git')) {
    Write-Host "Installing Git..."
    Ensure-WingetPackage -PackageId 'Git.Git' -DisplayName 'Git'
}
else {
    Write-Host "Git is installed. Updating Git..."
    winget upgrade --id Git.Git --source winget --accept-source-agreements --accept-package-agreements --silent
}

# Terraform
if (-not (Test-CommandAvailable -Name 'terraform')) {
    Write-Host "Installing Terraform..."
    Ensure-WingetPackage -PackageId 'Hashicorp.Terraform' -DisplayName 'Terraform'
}
else {
    Write-Host "Terraform is installed. Updating Terraform..."
    winget upgrade --id Hashicorp.Terraform --source winget --accept-source-agreements --accept-package-agreements --silent
}

# AWS CLI
if (-not (Test-CommandAvailable -Name 'aws')) {
    Write-Host "Installing AWS CLI..."
    Ensure-WingetPackage -PackageId 'Amazon.AWSCLI' -DisplayName 'AWS CLI'
}
else {
    Write-Host "AWS CLI is installed. Updating AWS CLI..."
    winget upgrade --id Amazon.AWSCLI --source winget --accept-source-agreements --accept-package-agreements --silent
}

# Visual Studio Code via winget
Ensure-WingetPackage -PackageId 'Microsoft.VisualStudioCode' -DisplayName 'Visual Studio Code'

# Configure VS Code for PowerShell, Ansible, Terraform, AWS, Codex, and Notepad comments
if (Test-CommandAvailable -Name 'code') {
    $settingsPath = Join-Path $HOME '.vscode\settings.json'
    $settingsDir = Split-Path $settingsPath -Parent
    if (-not (Test-Path $settingsDir)) {
        New-Item -ItemType Directory -Path $settingsDir -Force | Out-Null
    }

    $settings = Get-JsonSettingsHashtable -Path $settingsPath
    $settings['files.trimTrailingWhitespace'] = $true
    $settings['editor.insertSpaces'] = $true
    $settings['editor.tabSize'] = 2
    $settings['editor.wordWrap'] = 'on'
    $settings['terminal.integrated.defaultProfile.windows'] = 'Git Bash'
    $settings['git.openDiffOnClick'] = $false
    $settings['git.enableSmartCommit'] = $true
    $settings['comments.insertSpace'] = $true
    $settings['comments.ignoreEmptyLines'] = $false

    $settings | ConvertTo-Json -Depth 20 | Set-Content -Path $settingsPath -Encoding utf8

    $extensions = @(
        'ms-vscode.powershell',
        'redhat.ansible',
        'hashicorp.terraform',
        'amazonwebservices.aws-toolkit-vscode'
    )

    if ($InstallCodex) {
        $extensions += 'OpenAI.chatgpt'
    }

    Ensure-VisualStudioCodeExtensions -Extensions $extensions
}

# Configure Git to use Notepad for comments and commit messages
if (Test-CommandAvailable -Name 'git') {
    git config --global core.editor "notepad"
    git config --global core.pager "cat"
    git config --global core.autocrlf false
    git config --global init.defaultBranch main
    git config --global gui.editor "notepad"
}

if ($InstallAwsAgentToolkit) {
    Install-AwsAgentToolkitForCodex -DefaultRegion $AwsDefaultRegion -ToolkitRegion $AwsAgentToolkitRegion
}

Write-Host ""
Write-Host "Installation completed."
Write-Host "To connect GitHub Copilot Enterprise, open VS Code, click the Accounts icon in the lower-left corner, choose Sign in with GitHub Enterprise, and if needed add the following to your settings.json:"
Write-Host '"github.copilot.advanced": { "authProvider": "github-enterprise" }'

if ($InstallCodex) {
    Write-Host "OpenAI Codex has been added to VS Code. Open VS Code and sign in to Codex with your ChatGPT account."
}

if ($InstallAwsAgentToolkit) {
    Write-Host "AWS Agent Toolkit setup completed. AWS guidance for Codex has been written to AGENTS.md. Start a new session to create new AWS resources."
}
