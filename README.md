# MS Code Copilot and Codex Development Environment

## AWS RHEL 9 Dev Stack Add-On Playbook

This Ansible playbook is an add-on module designed to safely layer a strict, RPM-based Infrastructure as Code (IaC) development stack on top of a pre-provisioned RHEL 9 workstation.

### Features

- **Core stack**: VS Code, Terraform, PowerShell, Git, and jq.
- **Ansible environment**: `ansible-core` and `ansible-lint` installed natively via the RHEL AppStream and EPEL repositories.
- **Pre-configured IDE**: Installs VS Code extensions natively into the executing user's profile.
- **Optional Codex support**: Installs the OpenAI Codex VS Code extension (`OpenAI.chatgpt`) when enabled.
- **Optional AWS Agent Toolkit support**: Installs and configures the AWS Agent Toolkit and writes AWS guidance to `AGENTS.md` for Codex.

### Execution requirements

**This playbook must be executed by the developer account that will be using the workstation.** To keep the code clean and prevent profile mapping issues, the playbook installs system packages via standard privilege escalation, but seamlessly drops back to your user account to install the IDE extensions.

- **Requirement 1**: You must run this playbook as your standard user (for example, `ec2-user` or `jdoe`). Do not run it as the `root` user.
- **Requirement 2**: Your user account must have `sudo` privileges to install the RPM packages.
- **Requirement 3**: To enable AWS Agent Toolkit setup, provide your default AWS Region with `aws_default_region`. Do not provide AWS access keys or secret keys; the setup uses `aws login` browser authentication.

### Prerequisites

- **Ansible** installed on the control node or local machine (`sudo dnf install ansible-core`).
- Administrator (`sudo`) privileges on the target node.
- Internet access to install VS Code extensions and, when enabled, AWS CLI v2 / Agent Toolkit.

### Usage

#### Clone the repository

```bash
git clone https://github.com/evanhisey/cicd-dev-setup.git
cd cicd-dev-setup
```

#### Playbook execution guide

This guide details how to execute the Dev Stack Add-On playbook. **You must run this playbook as the standard developer account** that will be using the workstation (for example, `ec2-user` or `jdoe`). Do not run it as the `root` user. Your user account must have `sudo` privileges to install the required system packages.

---

#### Option A: Local execution (default)

Use this method if you are already logged into the pre-provisioned RHEL 9 GUI instance (for example, via RDP or console) and want to apply the configuration directly to your current session.

The playbook assumes local execution by default. The `-K` (or `--ask-become-pass`) flag is required to prompt for your user's `sudo` password to install system packages.

```bash
ansible-playbook install_dev_stack.yml -K
```

#### Option B: Local execution with OpenAI Codex VS Code extension

Use this option to add the OpenAI Codex IDE extension to VS Code as part of the setup.

```bash
ansible-playbook install_dev_stack.yml -K -e install_codex=true
```

After installation, open VS Code and sign in to Codex with your ChatGPT account.

#### Option C: Local execution with Codex and AWS Agent Toolkit

Use this option to install the OpenAI Codex VS Code extension, install AWS CLI v2 through the AWS installer, authenticate with `aws login`, configure the AWS Agent Toolkit, and write the AWS Codex guidance file to `AGENTS.md`.

```bash
ansible-playbook install_dev_stack.yml -K -e "install_codex=true install_aws_agent_toolkit=true aws_default_region=us-east-2"
```

Notes:

- Replace `us-east-2` with your default AWS Region.
- The AWS Agent Toolkit service setup uses `us-east-1` as required by the AWS setup instructions.
- The `aws login` flow opens a browser for authentication. Do not put AWS access keys or secret keys in the command line.
- Credentials are valid for 12 hours and can be renewed for 90 days without re-authenticating in the browser.

#### Option D: Remote execution via SSH

Use this method if you are pushing this configuration from a central control node (such as your laptop or a bastion host) to one or more remote workstations.

You must define your target hosts in an inventory file and pass the target group by using the `-e target_hosts` extra variable.

Create an inventory file (for example, `inventory.ini`):

```ini
[dev_workstations]
198.51.100.10
198.51.100.11
```

Execute the playbook:

```bash
ansible-playbook -i inventory.ini install_dev_stack.yml -e "target_hosts=dev_workstations" -u <developer-username> --private-key=/path/to/your/key.pem -K
```

Note: If your SSH key is already added to your SSH agent, you can omit the `--private-key` flag.

## Windows PowerShell Installer

Use the PowerShell script to install or update the following on Windows:

- Git for Git Bash
- Terraform
- AWS CLI
- Visual Studio Code
- VS Code extensions for PowerShell, Ansible, Terraform, and AWS Toolkit
- Optional OpenAI Codex VS Code extension
- Optional AWS Agent Toolkit setup for Codex
- Git configuration to use Notepad for comments and commit messages

### Prerequisites

- Windows 10 or later
- PowerShell 5.1 or later
- Internet access
- Administrator PowerShell for base tool installation through `winget`

### Install from PowerShell

Open PowerShell as Administrator and run:

```powershell
Set-ExecutionPolicy Bypass -Scope Process -Force
./install-dev-tools.ps1
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
- Installs the VS Code extensions for PowerShell, Ansible, Terraform, and AWS Toolkit
- Optionally installs the OpenAI Codex VS Code extension
- Optionally runs AWS Agent Toolkit setup and writes `AGENTS.md`
- Configures Git to use Notepad for comments and commit messages
- Displays messages explaining how to connect GitHub Copilot Enterprise and OpenAI Codex

### GitHub Copilot Enterprise connection

After installation, open VS Code and:

1. Click the Accounts icon in the lower-left corner.
2. Choose Sign in with GitHub Enterprise.
3. If required, add this setting to your VS Code settings:

```json
"github.copilot.advanced": { "authProvider": "github-enterprise" }
```
