# MS Code Copilot and Codex Development Environment

## AWS RHEL 9 Dev Stack Add-On Playbook

This Ansible playbook is an add-on module designed to safely layer a strict, RPM-based Infrastructure as Code (IaC) development stack on top of a local pre-provisioned RHEL 9 workstation.

Remote inventory execution is intentionally unsupported. The playbook fails early unless it is running against the local workstation.

### Features

- **Core stack**: VS Code, Terraform, PowerShell, Git, and jq.
- **Ansible environment**: `ansible-core` and `ansible-lint` installed natively via the RHEL AppStream and EPEL repositories.
- **Pre-configured IDE**: Installs VS Code, GitHub Copilot, Ansible, Terraform, and AWS Toolkit extensions natively into the executing user's profile. VS Code Chat is provided by the GitHub Copilot extension in current VS Code releases.
- **Credal custom endpoint**: Optionally configures VS Code Chat / GitHub Copilot BYOK Custom Endpoint for the ACF Credal OpenAI-compatible Chat Completions endpoint.
- **Optional Codex support**: Installs the OpenAI Codex VS Code extension (`OpenAI.chatgpt`) when enabled.
- **Optional AWS Agent Toolkit support**: Installs and configures the AWS Agent Toolkit and writes AWS guidance to `AGENTS.md` for Codex.

### Execution requirements

**This playbook must be executed by the developer account that will be using the workstation.** To keep the code clean and prevent profile mapping issues, the playbook installs system packages via standard privilege escalation, but seamlessly drops back to your user account to install the IDE extensions.

- **Requirement 1**: You must run this playbook as your standard user (for example, `ec2-user` or `jdoe`). Do not run it as the `root` user.
- **Requirement 2**: Your user account must have `sudo` privileges to install the RPM packages.
- **Requirement 3**: The target must be the local workstation. Remote SSH inventory execution is not supported.
- **Requirement 4**: To enable AWS Agent Toolkit setup, provide your default AWS Region with `aws_default_region`. Do not provide AWS access keys or secret keys; the setup uses `aws login` browser authentication.

### Prerequisites

- **Ansible** installed on the local machine (`sudo dnf install ansible-core`).
- Administrator (`sudo`) privileges on the local workstation.
- RHEL-family version 9. Other platforms fail early as unsupported.
- Internet access to install package repositories, VS Code extensions, and optional AWS CLI v2 / Agent Toolkit assets.
- Optional: Credal API token if you want the playbook to create the VS Code custom endpoint configuration.

### Usage

#### Clone the repository

```bash
git clone https://github.com/acfehisey/guac-cicd-dev-setup.git
cd cicd-dev-setup
```

#### Local execution

Use this method if you are already logged into the pre-provisioned RHEL 9 GUI instance and want to apply the configuration directly to your current session.

The playbook assumes local execution. The `-K` or `--ask-become-pass` flag is required to prompt for your user's `sudo` password to install system packages.

```bash
ansible-playbook install_dev_stack.yml -K
```

To also configure the VS Code Credal custom endpoint, provide the token through the environment. This keeps the token out of the command line for most interactive workflows:

```bash
read -rs CREDAL_API_TOKEN
export CREDAL_API_TOKEN
ansible-playbook install_dev_stack.yml -K
unset CREDAL_API_TOKEN
```

The playbook creates:

```text
~/.config/Code/User/chatLanguageModels.json
```

with permissions set to `0600`.

#### Local execution with OpenAI Codex VS Code extension

Use this option to add the OpenAI Codex IDE extension to VS Code as part of the setup.

```bash
ansible-playbook install_dev_stack.yml -K -e install_codex=true
```

After installation, open VS Code and sign in to Codex with your ChatGPT account.

#### Local execution with Credal, Codex, and AWS Agent Toolkit

Use this option to install the OpenAI Codex VS Code extension, install AWS CLI v2 through the AWS installer, authenticate with `aws login`, configure the AWS Agent Toolkit, write AWS Codex guidance to `AGENTS.md`, and configure the Credal custom endpoint.

```bash
read -rs CREDAL_API_TOKEN
export CREDAL_API_TOKEN
ansible-playbook install_dev_stack.yml -K -e "install_codex=true install_aws_agent_toolkit=true aws_default_region=us-east-2"
unset CREDAL_API_TOKEN
```

Notes:

- Replace `us-east-2` with your default AWS Region.
- The AWS Agent Toolkit service setup uses `us-east-1` as required by the AWS setup instructions.
- The `aws login` flow opens a browser for authentication. Do not put AWS access keys or secret keys in the command line.
- Credentials are valid for 12 hours and can be renewed for 90 days without re-authenticating in the browser.

### Unsupported platforms

The Linux playbook uses an explicit unsupported-platform method. If the local machine is not a RHEL-family version 9 workstation, the playbook fails before package or user configuration tasks run.

Remote inventory execution is also unsupported. Run this repository directly on the local instance that will use the development stack.

## VS Code GitHub Copilot Credal Custom Endpoint

This repository can configure Microsoft VS Code / GitHub Copilot Chat BYOK Custom Endpoint to use the ACF Credal OpenAI-compatible endpoint.

Use the Credal OpenAI-compatible Chat Completions endpoint:

```text
https://app.credal.acf.gov/api/openai/chat/completions
```

Do not use:

```text
https://app.credal.acf.gov/api/openai/v1
```

Do not use the Responses endpoint for this VS Code Copilot setup:

```text
https://app.credal.acf.gov/api/openai/responses
```

The key Credal setting is:

```json
"streaming": false
```

Users need:

- VS Code installed
- GitHub Copilot / VS Code Chat available
- A Credal API token
- BYOK / Custom Endpoint models enabled by organizational policy

The token should look like a JWT and may begin with `eyJhbGci`. Do not include angle brackets when using it in a bearer token.

Correct:

```text
Bearer eyJhbGci...
```

Incorrect:

```text
Bearer <eyJhbGci...>
```

Final working configuration summary:

```text
Vendor: customendpoint
API Type: chat-completions
Endpoint: https://app.credal.acf.gov/api/openai/chat/completions
Model: gpt-5.5
Streaming: false
Authorization: Bearer <Credal token>
```

After running the Linux playbook or Windows installer with a Credal token, fully close and restart VS Code. Open Chat, open the model picker, and select `Credal GPT-5.5 Chat`. If the model does not appear, run `Developer: Reload Window` or `Chat: Manage Language Models` from the Command Palette.

Optional endpoint test from Linux or Git Bash when `OPENAI_API_KEY` contains the Credal token:

```bash
curl -s https://app.credal.acf.gov/api/openai/chat/completions \
  -H "Authorization: Bearer $OPENAI_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "gpt-5.5",
    "messages": [
      {
        "role": "user",
        "content": "Say hello in one sentence."
      }
    ],
    "stream": false
  }' | python3 -m json.tool
```

Known limitations:

- This custom endpoint setup applies to VS Code Chat and some Agent / Chat workflows.
- It does not necessarily replace inline code completions, semantic search, embeddings-based features, or GitHub-hosted Copilot-only features.
- Credal currently does not support streaming through this OpenAI proxy, so VS Code is configured with `streaming: false`.

## Windows PowerShell Installer

Use the PowerShell script to install or update the following on Windows:

- Git for Git Bash
- Terraform
- AWS CLI
- Visual Studio Code
- VS Code extensions for GitHub Copilot, PowerShell, Ansible, Terraform, and AWS Toolkit
- Optional VS Code Credal custom endpoint configuration
- Optional OpenAI Codex VS Code extension
- Optional AWS Agent Toolkit setup for Codex
- Git configuration to use Notepad for comments and commit messages

### Prerequisites

- Windows 10 or later
- Windows PowerShell 5.1, included with current Windows releases
- `winget`, provided by App Installer on supported current Windows 10/11 releases
- Internet access
- Administrator PowerShell for base tool installation through `winget`

### Install from PowerShell

Open PowerShell as Administrator and run:

```powershell
Set-ExecutionPolicy Bypass -Scope Process -Force
./install-dev-tools.ps1
```

To configure the Credal custom endpoint during installation, pass the token as a secure string:

```powershell
$credalToken = Read-Host 'Credal API token' -AsSecureString
./install-dev-tools.ps1 -CredalApiToken $credalToken
```

For non-interactive automation, the script can also read `CREDAL_API_TOKEN` from the environment:

```powershell
$env:CREDAL_API_TOKEN = 'eyJhbGci...'
./install-dev-tools.ps1
Remove-Item Env:\CREDAL_API_TOKEN
```

### Install with the OpenAI Codex VS Code extension

```powershell
Set-ExecutionPolicy Bypass -Scope Process -Force
./install-dev-tools.ps1 -InstallCodex
```

After installation, open VS Code and sign in to Codex with your ChatGPT account.

### Install with Codex and AWS Agent Toolkit

```powershell
Set-ExecutionPolicy Bypass -Scope Process -Force
./install-dev-tools.ps1 -InstallCodex -InstallAwsAgentToolkit -AwsDefaultRegion us-east-2
```

Notes:

- Replace `us-east-2` with your default AWS Region.
- The AWS Agent Toolkit command intentionally uses `us-east-1` for toolkit setup and verification.
- The script uses `aws login`; do not provide AWS access keys or secret keys.
- Credentials are valid for 12 hours and can be renewed for 90 days without re-authenticating in the browser.

### What the script does

- Checks whether Git, Terraform, and AWS CLI are installed
- Installs them if missing
- Updates them if they are already present
- Installs Visual Studio Code if it is not present
- Installs the VS Code extensions for GitHub Copilot, PowerShell, Ansible, Terraform, and AWS Toolkit
- Creates `%APPDATA%\Code\User\chatLanguageModels.json` for Credal when a token is provided
- Optionally installs the OpenAI Codex VS Code extension
- Optionally runs AWS Agent Toolkit setup and writes `AGENTS.md`
- Configures Git to use Notepad for comments and commit messages
- Displays messages explaining how to select the Credal model in VS Code Chat and how to connect OpenAI Codex

### Troubleshooting Credal in VS Code

If VS Code reports `Authorization: Bearer <Credal token> header required`, verify that `chatLanguageModels.json` includes the bearer authorization header and that the token is pasted directly after `Bearer `.

If VS Code reports `Response contained no choices`, verify that the model uses:

```json
"apiType": "chat-completions"
```

and the URL is `https://app.credal.acf.gov/api/openai/chat/completions`.

If VS Code reports that streaming is not supported, verify that the model has:

```json
"streaming": false
```

If Chat works but Agent mode does not, try changing `toolCalling` to `false` in `chatLanguageModels.json`, then reload VS Code. This may make the model usable for basic chat but may reduce Agent mode capabilities.
