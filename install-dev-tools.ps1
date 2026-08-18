[CmdletBinding()]
param(
    [switch]$InstallCodex,
    [switch]$InstallAwsAgentToolkit,
    [string]$AwsDefaultRegion,
    [string]$AwsAgentToolkitRegion = 'us-east-1',
    [SecureString]$CredalApiToken
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

function ConvertTo-Hashtable {
    param([Parameter(ValueFromPipeline = $true)]$InputObject)

    if ($null -eq $InputObject) {
        return $null
    }

    if ($InputObject -is [System.Collections.IDictionary]) {
        $hash = @{}
        foreach ($key in $InputObject.Keys) {
            $hash[$key] = ConvertTo-Hashtable $InputObject[$key]
        }
        return $hash
    }

    if ($InputObject -is [System.Collections.IEnumerable] -and $InputObject -isnot [string]) {
        $list = @()
        foreach ($item in $InputObject) {
            $list += ConvertTo-Hashtable $item
        }
        return $list
    }

    if ($InputObject -is [pscustomobject]) {
        $hash = @{}
        foreach ($property in $InputObject.PSObject.Properties) {
            $hash[$property.Name] = ConvertTo-Hashtable $property.Value
        }
        return $hash
    }

    return $InputObject
}

function Get-JsonSettingsHashtable {
    param([string]$Path)

    if (-not (Test-Path $Path)) {
        return @{}
    }

    $rawJson = Get-Content -Path $Path -Raw
    if ([string]::IsNullOrWhiteSpace($rawJson)) {
        return @{}
    }

    return $rawJson | ConvertFrom-Json | ConvertTo-Hashtable
}

function Set-VisualStudioCodeSetting {
    param(
        [hashtable]$Settings,
        [string]$Name,
        [object]$Value
    )

    $Settings[$Name] = $Value
}

function Install-WingetPackage {
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

function Install-VisualStudioCodeExtensions {
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

function Set-CredalLanguageModelConfiguration {
    param([SecureString]$Token)

    if ($null -eq $Token) {
        Write-Host "Credal API token was not provided. Skipping Credal custom endpoint configuration."
        return
    }

    $tokenPointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($Token)
    try {
        $tokenText = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($tokenPointer)
    }
    finally {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($tokenPointer)
    }

    $codeUserDir = Join-Path $env:APPDATA 'Code\User'
    if (-not (Test-Path $codeUserDir)) {
        New-Item -ItemType Directory -Path $codeUserDir -Force | Out-Null
    }

    $chatLanguageModelsPath = Join-Path $codeUserDir 'chatLanguageModels.json'
    $languageModels = @(
        @{
            name = 'Credal'
            vendor = 'customendpoint'
            apiKey = $tokenText
            apiType = 'chat-completions'
            models = @(
                @{
                    id = 'gpt-5.5'
                    name = 'Credal GPT-5.5 Chat'
                    url = 'https://app.credal.acf.gov/api/openai/chat/completions'
                    apiType = 'chat-completions'
                    requestHeaders = @{
                        Authorization = "Bearer $tokenText"
                    }
                    toolCalling = $true
                    vision = $false
                    thinking = $false
                    streaming = $false
                    maxInputTokens = 200000
                    maxOutputTokens = 64000
                }
            )
        }
    )

    $languageModels | ConvertTo-Json -Depth 20 | Set-Content -Path $chatLanguageModelsPath -Encoding utf8
    Write-Host "Configured VS Code Credal custom endpoint at $chatLanguageModelsPath."
}

function Install-AwsCliForAgentToolkit {
    if (Test-CommandAvailable -Name 'aws') {
        Write-Host "AWS CLI is available:"
        & aws --version
        return
    }

    Write-Host "AWS CLI was not found in PATH. Installing AWS CLI v2 with the AWS PowerShell installer..."
    $installerPath = Join-Path ([System.IO.Path]::GetTempPath()) 'awscliv2-install.ps1'
    Invoke-WebRequest -Uri 'https://awscli.amazonaws.com/v2/install.ps1' -OutFile $installerPath -UseBasicParsing
    & $installerPath

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

    Install-AwsCliForAgentToolkit

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

if ($null -eq $CredalApiToken -and -not [string]::IsNullOrWhiteSpace($env:CREDAL_API_TOKEN)) {
    $CredalApiToken = ConvertTo-SecureString -String $env:CREDAL_API_TOKEN -AsPlainText -Force
}

if (-not (Test-CommandAvailable -Name 'winget')) {
    throw 'winget is required for this installer. Install App Installer from Microsoft or use a supported current Windows 10/11 release, then rerun this script.'
}

if (-not (Test-CommandAvailable -Name 'git')) {
    Write-Host "Installing Git..."
    Install-WingetPackage -PackageId 'Git.Git' -DisplayName 'Git'
}
else {
    Write-Host "Git is installed. Updating Git..."
    winget upgrade --id Git.Git --source winget --accept-source-agreements --accept-package-agreements --silent
}

if (-not (Test-CommandAvailable -Name 'terraform')) {
    Write-Host "Installing Terraform..."
    Install-WingetPackage -PackageId 'Hashicorp.Terraform' -DisplayName 'Terraform'
}
else {
    Write-Host "Terraform is installed. Updating Terraform..."
    winget upgrade --id Hashicorp.Terraform --source winget --accept-source-agreements --accept-package-agreements --silent
}

if (-not (Test-CommandAvailable -Name 'aws')) {
    Write-Host "Installing AWS CLI..."
    Install-WingetPackage -PackageId 'Amazon.AWSCLI' -DisplayName 'AWS CLI'
}
else {
    Write-Host "AWS CLI is installed. Updating AWS CLI..."
    winget upgrade --id Amazon.AWSCLI --source winget --accept-source-agreements --accept-package-agreements --silent
}

Install-WingetPackage -PackageId 'Microsoft.VisualStudioCode' -DisplayName 'Visual Studio Code'

if (Test-CommandAvailable -Name 'code') {
    $settingsPath = Join-Path $HOME '.vscode\settings.json'
    $settingsDir = Split-Path $settingsPath -Parent
    if (-not (Test-Path $settingsDir)) {
        New-Item -ItemType Directory -Path $settingsDir -Force | Out-Null
    }

    $settings = Get-JsonSettingsHashtable -Path $settingsPath
    Set-VisualStudioCodeSetting -Settings $settings -Name 'files.trimTrailingWhitespace' -Value $true
    Set-VisualStudioCodeSetting -Settings $settings -Name 'editor.insertSpaces' -Value $true
    Set-VisualStudioCodeSetting -Settings $settings -Name 'editor.tabSize' -Value 2
    Set-VisualStudioCodeSetting -Settings $settings -Name 'editor.wordWrap' -Value 'on'
    Set-VisualStudioCodeSetting -Settings $settings -Name 'terminal.integrated.defaultProfile.windows' -Value 'Git Bash'
    Set-VisualStudioCodeSetting -Settings $settings -Name 'git.openDiffOnClick' -Value $false
    Set-VisualStudioCodeSetting -Settings $settings -Name 'git.enableSmartCommit' -Value $true
    Set-VisualStudioCodeSetting -Settings $settings -Name 'comments.insertSpace' -Value $true
    Set-VisualStudioCodeSetting -Settings $settings -Name 'comments.ignoreEmptyLines' -Value $false

    $settings | ConvertTo-Json -Depth 20 | Set-Content -Path $settingsPath -Encoding utf8

    $extensions = @(
        'GitHub.copilot',
        'ms-vscode.powershell',
        'redhat.ansible',
        'hashicorp.terraform',
        'amazonwebservices.aws-toolkit-vscode'
    )

    if ($InstallCodex) {
        $extensions += 'OpenAI.chatgpt'
    }

    Install-VisualStudioCodeExtensions -Extensions $extensions
    Set-CredalLanguageModelConfiguration -Token $CredalApiToken
}

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
Write-Host "To use Credal with VS Code Chat, provide a Credal API token with -CredalApiToken or CREDAL_API_TOKEN, restart VS Code, and select Credal GPT-5.5 Chat from the model picker."

if ($InstallCodex) {
    Write-Host "OpenAI Codex has been added to VS Code. Open VS Code and sign in to Codex with your ChatGPT account."
}

if ($InstallAwsAgentToolkit) {
    Write-Host "AWS Agent Toolkit setup completed. AWS guidance for Codex has been written to AGENTS.md. Start a new session to create new AWS resources."
}
