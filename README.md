# .NET Project Generator Script

## Explanation

This repository is intended as a premier boiler plate template for .NET projects, microservices, and applications. A more detailed explanation of the script can be found below but the idea is this;

>Intened for use with CLine, Roo Code, or any other VsCode 'LLm Assistant Coder' plugins as a way to automate project generation once the planning phase of project has completed and documentation (markdown files used against LLM coder assistant style plugins) is generated.

1) Generate markdown documentation, plans, archtiecture, and more and include different references for nuget packages using an LLM Assistant Coder Plugin like 'CLine' or 'Roo Code', or any other LLM model capable of generating markdown files.
2) Generate or copy/paste a configuration file with existing keys and secrets for api's that are referenced in your project documentation.
3) Run the 'New-DotnetProject.ps1' script
4) Delete the script [Optional].
5) Continue with your Project :smile:

> ## I <b>KNOW</b>..., its a glorified 'dotnet new' wrapper 🙄; but its a good one 🙂

## Overview

This PowerShell script automates the creation and setup of .NET projects with comprehensive environment validation, dependency management, and configuration handling. It will check your markdown documentation for any referenced nuget packages, and install them for you during project creation. It also will initialize the 'dotnet user-secrets' to store any api_keys, or configurations for secrets (see supported config types) as well as streamlines the project initialization process by ensuring all prerequisites are met and setting up necessary configurations. The script will then initalize the git repository. It will also create a .gitignore file for you.

Told you it was a good one 😁

The idea was that one spends so much time on 'Architecture' and 'Planning' that the actual project creation should be a breeze. This script is intended to make that process easier.

## Features

- **Project Template Support**
  - Console Applications
  - Class Libraries
  - Web APIs
  - MAUI Blazor Applications
  - WPF Applications
  - Windows Forms Applications
  - Blazor Applications
  - MVC Applications

- **Environment Validation**
  - PowerShell 5.1+ verification
  - .NET SDK 9.0+ verification
  - Visual Studio 2022 (17.8+) detection
  - Template-specific workload validation

- **Configuration Management**
  - Automatic user secrets initialization for web projects
  - Configuration file discovery and processing
  - Support for JSON, INI, and ENV file formats
  - Secure backup of existing secrets

- **Package Management**
  - Core infrastructure package installation
  - Intelligent package discovery from documentation
  - Compatibility validation
  - Automatic dependency resolution

- **Logging and Error Handling**
  - Comprehensive logging system
  - Detailed error reporting
  - Cleanup on failure
  - Progress tracking

## Prerequisites

- PowerShell 5.1 or later
- .NET SDK 9.0 or later
- Any preferred IDE/editor (VS Code, Visual Studio, Rider, etc.)
  - Visual Studio 2022 (17.8+) is recommended but not required
- Template-specific workloads (automatically installed if missing):
  - .NET MAUI for MAUI Blazor projects
  - ASP.NET Core for Web API projects

## Usage

```powershell
.\New-DotNetProject.ps1 -TemplateType <type> [-OutputPath <path>]
```

### Parameters

- **TemplateType** (Required)
  - Valid options: console, classlib, webapi, maui-blazor, wpf, winforms, blazor, mvc

- **OutputPath** (Optional)
  - Custom output directory for the project

### Examples

```powershell
# Create a Web API project in the current directory
.\New-DotNetProject.ps1 -TemplateType webapi

# Create a MAUI Blazor project in a specific directory
.\New-DotNetProject.ps1 -TemplateType maui-blazor -OutputPath "C:\Projects"
```

## Error Handling

The script includes robust error handling mechanisms:

- Prerequisite validation failures
- Project creation errors
- Package installation issues
- Configuration processing errors

All errors are logged to `New-DotNetProject.log` with timestamps and detailed error messages.

## Configuration Support

The script automatically processes various configuration file formats:

- JSON (appsettings.json)
- INI (.ini, .config)
- Environment files (.env)

Configuration values are securely stored using .NET User Secrets for supported project types.
