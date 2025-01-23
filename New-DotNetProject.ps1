# Function to verify prerequisites
function Test-Prerequisites {
    param(
        [string]$TemplateType
    )
    # Check PowerShell version
    $psVersion = $PSVersionTable.PSVersion
    if ($psVersion.Major -lt 5 -or ($psVersion.Major -eq 5 -and $psVersion.Minor -lt 1)) {
        Write-CustomError "PowerShell 5.1 or later is required. Current version: $($psVersion.ToString())" -Fatal
    }
    Write-Log -Message "PowerShell version check passed: $($psVersion.ToString())"

    # Check .NET SDK version
    try {
        $dotnetVersion = dotnet --version
        $versionParts = $dotnetVersion.Split('.')
        if ([int]$versionParts[0] -lt 9) {
            Write-CustomError ".NET 9.0 SDK or later is required. Current version: $dotnetVersion" -Fatal
        }
        Write-Log ".NET SDK version check passed: $dotnetVersion"
    } catch {
        Write-CustomError ".NET SDK is not installed or not in PATH" -Fatal
    }

    # Check Visual Studio version if installed
    if (Get-Command "devenv.exe" -ErrorAction SilentlyContinue) {
        $vsWhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
        if (Test-Path $vsWhere) {
            $vsVersion = & $vsWhere -property catalog_productLineVersion
            if ([double]$vsVersion -lt 17.8) {
                Write-Log -Message "Warning: Visual Studio 2022 (17.8 or later) is recommended" -IsError
            } else {
                Write-Log -Message "Visual Studio version check passed: $vsVersion"
            }
        }
    }

    # Check template-specific requirements
    switch ($TemplateType) {
        "maui-blazor" {
            Write-Log -Message "Checking .NET MAUI workload..."
            $installedWorkloads = dotnet workload list
            if (-not ($installedWorkloads -match "maui")) {
                Write-Log -Message ".NET MAUI workload not found. Installing..."
                try {
                    $output = dotnet workload install maui --quiet 2>&1
                    if ($LASTEXITCODE -ne 0) {
                        Write-CustomError "Failed to install .NET MAUI workload: $output" -Fatal
                    }
                    Write-Log -Message ".NET MAUI workload installed successfully"
                } catch {
                    Write-CustomError "Failed to install .NET MAUI workload: $($_.Exception.Message)" -Fatal
                }
            } else {
                Write-Log -Message ".NET MAUI workload is already installed"
            }
        }
        "webapi" {
            Write-Log -Message "Checking ASP.NET Core workload..."
            $installedWorkloads = dotnet workload list
            if (-not ($installedWorkloads -match "aspnetcore")) {
                Write-Log -Message "Installing ASP.NET Core workload..."
                try {
                    $output = dotnet workload install aspnetcore --quiet 2>&1
                    if ($LASTEXITCODE -ne 0) {
                        Write-CustomError "Failed to install ASP.NET Core workload: $output" -Fatal
                    }
                    Write-Log -Message "ASP.NET Core workload installed successfully"
                } catch {
                    Write-CustomError "Failed to install ASP.NET Core workload: $($_.Exception.Message)" -Fatal
                }
            }
        }
    }
}

# Function to write log messages
function Write-Log {
    param(
        [string]$Message,
        [string]$LogFile = "New-DotNetProject.log",
        [switch]$IsError
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH'.'mm'.'ss"
    $logMessage = "$timestamp`: $Message"
    
    # Write to console
    if ($IsError) {
        Write-Host $logMessage -ForegroundColor Red
    } else {
        Write-Host $logMessage
    }
    
    # Write to log file
    $logMessage | Out-File -FilePath $LogFile -Append
}

# Function to handle errors
function Write-CustomError {
    param(
        [string]$ErrorMessage,
        [string]$Context = "",
        [switch]$Fatal
    )
    $fullMessage = if ($Context) { "$Context - $ErrorMessage" } else { $ErrorMessage }
    Write-Log -Message $fullMessage -IsError
    
    if ($Fatal) {
        Write-Log -Message "Attempting cleanup..." -IsError
        if (Test-Path $projectPath) {
            Remove-Item -Path $projectPath -Recurse -Force
            Write-Log -Message "Cleaned up project directory" -IsError
        }
        exit 1
    }
}

# Function to validate path
function Test-ValidPath {
    param([string]$Path)
    
    if ([string]::IsNullOrWhiteSpace($Path)) {
        return $false
    }
    
    try {
        $item = Get-Item $Path -ErrorAction SilentlyContinue
        return ($null -ne $item)
    } catch {
        return $false
    }
}

# Function to backup existing secrets
function Backup-UserSecrets {
    param([string]$ProjectPath)
    
    try {
        $timestamp = Get-Date -Format "yyyyMMddHHmmss"
        $backupFile = "user-secrets-backup-$timestamp.json"
        
        # Export existing secrets
        $secrets = dotnet user-secrets list
        if ($secrets) {
            $secrets | Out-File -FilePath $backupFile
            Write-Log -Message "User secrets backed up to: $backupFile"
        }
    } catch {
        Write-Log -Message "Warning: Failed to backup user secrets - $($_.Exception.Message)" -IsError
    }
}

# Function to process JSON configuration and set user secrets
function Set-SecretsFromJson {
    param(
        [string]$JsonContent,
        [string]$ParentKey = ""
    )
    
    try {
        $config = $JsonContent | ConvertFrom-Json
        
        function Convert-JsonObject {
            param($Object, [string]$Prefix = "")
            
            $Object.PSObject.Properties | ForEach-Object {
                $key = if ($Prefix) { "$Prefix`:$($_.Name)" } else { $_.Name }
                
                if ($_.Value -is [System.Management.Automation.PSCustomObject]) {
                    Convert-JsonObject -Object $_.Value -Prefix $key
                }
                else {
                    # Validate and sanitize value, skip template values
                    $value = $_.Value.ToString().Trim()
                    if (-not [string]::IsNullOrWhiteSpace($value) -and
                        -not $value.StartsWith("YOUR_") -and
                        -not $value -eq "true" -and
                        -not $value -eq "false" -and
                        -not $value -match "^https?://") {
                        Write-Log -Message "Setting secret: $key"
                        dotnet user-secrets set "$key" "$value"
                    }
                }
            }
        }
        
        Convert-JsonObject -Object $config -Prefix $ParentKey
    } catch {
        Write-CustomError "Failed to process JSON configuration: $($_.Exception.Message)"
    }
}

# Function to process INI configuration and set user secrets
function Set-SecretsFromIni {
    param([string]$IniContent)
    
    try {
        $currentSection = ""
        $IniContent -split "`n" | ForEach-Object {
            $line = $_.Trim()
            if ($line -and -not $line.StartsWith('#')) {
                if ($line -match '^\[(.+)\]$') {
                    $currentSection = $matches[1]
                }
                elseif ($line -match '^([^=]+)=(.*)$') {
                    $key = $matches[1].Trim()
                    $value = $matches[2].Trim()
                    
                    if (-not [string]::IsNullOrWhiteSpace($key) -and -not [string]::IsNullOrWhiteSpace($value)) {
                        $fullKey = if ($currentSection) {
                            "$currentSection`:$key"
                        } else {
                            $key
                        }
                        
                        Write-Log -Message "Setting secret: $fullKey"
                        dotnet user-secrets set "$fullKey" "$value"
                    }
                }
            }
        }
    } catch {
        Write-CustomError "Failed to process INI configuration: $($_.Exception.Message)"
    }
}

# Function to process ENV configuration and set user secrets
function Set-SecretsFromEnv {
    param([string]$EnvContent)
    
    try {
        $EnvContent -split "`n" | ForEach-Object {
            $line = $_.Trim()
            if ($line -and -not $line.StartsWith('#')) {
                if ($line -match '^([^=]+)=(.*)$') {
                    $key = $matches[1].Trim()
                    $value = $matches[2].Trim() -replace '^[''"]|[''"]$'
                    
                    if (-not [string]::IsNullOrWhiteSpace($key) -and -not [string]::IsNullOrWhiteSpace($value)) {
                        Write-Log -Message "Setting secret: $key"
                        dotnet user-secrets set "$key" "$value"
                    }
                }
            }
        }
    } catch {
        Write-CustomError "Failed to process ENV configuration: $($_.Exception.Message)"
    }
}

# Function to discover and process configuration files
function Initialize-UserSecrets {
    param([string]$RootPath)
    
    Write-Log -Message "Searching for configuration files..."
    
    # Backup existing secrets
    Backup-UserSecrets -ProjectPath $RootPath
    
    # Find configuration files
    $configFiles = Get-ChildItem -Path $RootPath -Recurse -File |
        Where-Object {
            $_.Name -match '^(appsettings.*\.json|config.*\.ini|\.env.*|.*\.config)$' -and
            -not $_.FullName.Contains('\bin\') -and
            -not $_.FullName.Contains('\obj\')
        }
    
    if ($configFiles.Count -eq 0) {
        Write-Log -Message "No configuration files found. Creating default development configuration..."
        
        # Create default template
        $defaultTemplate = @{
            "General_Settings" = @{
                "debug_enabled" = $true
            }
            "Logging" = @{
                "LogLevel" = @{
                    "Default" = "Information"
                    "Microsoft.Hosting.Lifetime" = "Warning"
                }
            }
        }
        
        $templatePath = Join-Path -Path $RootPath -ChildPath "appsettings.json"
        $defaultTemplate | ConvertTo-Json -Depth 10 | Out-File -FilePath $templatePath -Encoding UTF8
        Write-Log -Message "Created default template configuration"
        
        # Copy to development
        $devPath = Join-Path -Path $RootPath -ChildPath "appsettings.development.json"
        Copy-Item -Path $templatePath -Destination $devPath -Force
        Write-Log -Message "Created development configuration from default template"
        
        # Set default secrets
        dotnet user-secrets set "AppConfig:Environment" "Development"
        return
    }
    
    foreach ($file in $configFiles) {
        Write-Log -Message "Processing configuration file: $($file.FullName)"
        try {
            $content = Get-Content $file.FullName -Raw -ErrorAction Stop
            
            switch -Regex ($file.Name) {
                '\.json$' {
                    Write-Log -Message "Processing JSON configuration"
                    Set-SecretsFromJson -JsonContent $content
                }
                '\.ini$|\.config$' {
                    Write-Log -Message "Processing INI configuration"
                    Set-SecretsFromIni -IniContent $content
                }
                '\.env' {
                    Write-Log -Message "Processing ENV configuration"
                    Set-SecretsFromEnv -IniContent $content
                }
            }
        } catch {
            Write-CustomError "Failed to process file $($file.Name): $($_.Exception.Message)"
        }
    }
}

# Function to validate package compatibility
function Test-PackageCompatibility {
    param(
        [string]$Package,
        [string]$ProjectPath
    )
    
    try {
        # Check if package restore succeeds
        dotnet restore --package $Package 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Log -Message "Warning: Package $Package may have compatibility issues" -IsError
            return $false
        }
        return $true
    } catch {
        Write-Log -Message "Warning: Failed to validate package $Package - $($_.Exception.Message)" -IsError
        return $false
    }
}

# Function to get all required packages (core + discovered)
function Get-RequiredPackages {
    param([string]$RootPath)
    
    # Initialize with core infrastructure packages
    $packages = @{
        "Microsoft.Extensions.Configuration" = $true
        "Microsoft.Extensions.Hosting" = $true
        "Microsoft.Extensions.Logging" = $true
        "Microsoft.Extensions.Configuration.Json" = $true
        "Microsoft.Extensions.DependencyInjection" = $true
    }
    
    Write-Log -Message "Core infrastructure packages included:"
    foreach ($package in $packages.Keys) {
        Write-Log -Message "- $package"
    }
    
    # Get all .md files recursively
    $mdFiles = Get-ChildItem -Path $RootPath -Filter "*.md" -Recurse |
        Where-Object { 
            -not $_.FullName.Contains('\bin\') -and 
            -not $_.FullName.Contains('\obj\')
        }
    
    if ($mdFiles.Count -eq 0) {
        Write-Log -Message "No markdown files found. Using only core packages."
        return $packages.Keys
    }

    foreach ($file in $mdFiles) {
        Write-Log -Message "Scanning file: $($file.FullName)"
        try {
            $content = Get-Content $file.FullName -Raw -ErrorAction Stop

            # Match XML style package references
            $xmlMatches = [regex]::Matches($content, '<PackageReference\s+Include="([^"]+)"[^>]*>')
            foreach ($match in $xmlMatches) {
                $packageName = $match.Groups[1].Value
                if (-not $packages.ContainsKey($packageName)) {
                    $packages[$packageName] = $true
                    Write-Log -Message "Found additional package (XML): $packageName"
                }
            }

            # Match requirements.txt style references
            $reqMatches = [regex]::Matches($content, '([A-Za-z0-9\.]+)[=>]=\d+\.\d+\.\d+(?:-[A-Za-z0-9-]+)?')
            foreach ($match in $reqMatches) {
                $packageName = $match.Groups[1].Value
                if (-not $packages.ContainsKey($packageName)) {
                    $packages[$packageName] = $true
                    Write-Log -Message "Found additional package (Requirements): $packageName"
                }
            }

            # Match package names in code blocks
            $codeBlockMatches = [regex]::Matches($content, '```[^\n]*\n(.*?)```', [System.Text.RegularExpressions.RegexOptions]::Singleline)
            foreach ($block in $codeBlockMatches) {
                $blockContent = $block.Groups[1].Value
                $packageMatches = [regex]::Matches($blockContent, '(?:using|import|require)[^\n]*[\s"'']([A-Za-z0-9\.]+)')
                foreach ($match in $packageMatches) {
                    $packageName = $match.Groups[1].Value
                    if (-not $packages.ContainsKey($packageName)) {
                        $packages[$packageName] = $true
                        Write-Log -Message "Found additional package (Code Block): $packageName"
                    }
                }
            }
        } catch {
            Write-CustomError "Failed to process markdown file $($file.Name): $($_.Exception.Message)"
        }
    }

    return $packages.Keys
}

# Script parameters
param(
    [Parameter(Mandatory=$true)]
    [ValidateSet("console", "classlib", "webapi", "maui-blazor", "wpf", "winforms", "blazor", "mvc")]
    [string]$TemplateType,
    
    [Parameter(Mandatory=$false)]
    [string]$OutputPath
)

try {
    # Start logging
    $logFile = "New-DotNetProject.log"
    Write-Log -Message "Starting script execution" -LogFile $logFile
    
    # Verify prerequisites first
    Test-Prerequisites -TemplateType $TemplateType
    
    # Get the current directory name as the project name if output path not specified
    if (-not $OutputPath) {
        $projectName = Split-Path -Path (Get-Location) -Leaf
    } else {
        $projectName = Split-Path -Path $OutputPath -Leaf
    }
    
    if ($projectName -match '[^\w\-\.]') {
        Write-CustomError "Project name contains invalid characters: $projectName" -Fatal
    }
    Write-Log -Message "Starting $TemplateType project creation for $projectName"

    # Verify dotnet CLI is installed
    if (-not (Get-Command dotnet -ErrorAction SilentlyContinue)) {
        Write-CustomError ".NET SDK is not installed or not in PATH" -Fatal
    }

    # Check if project directory already exists
    $projectPath = if ($OutputPath) {
        Join-Path $OutputPath $projectName
    } else {
        "$projectName/$projectName"
    }
    
    if (Test-Path $projectPath) {
        Write-CustomError "Project directory already exists: $projectPath" -Fatal
    }

    # Create project directory structure
    Write-Log -Message "Creating project directory: $projectPath"
    New-Item -ItemType Directory -Path $projectPath -Force | Out-Null

    # Create project using specified template
    Write-Log -Message "Creating $TemplateType project"
    $output = dotnet new $TemplateType -n $projectName -o $projectPath 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-CustomError "Failed to create $TemplateType project: $output" -Fatal
    }

    # Navigate to project directory
    Set-Location $projectPath

    # Initialize user secrets for web projects
    if (@("webapi", "mvc", "blazor", "maui-blazor") -contains $TemplateType) {
        Write-Log -Message "Initializing user secrets"
        dotnet user-secrets init
        if ($LASTEXITCODE -ne 0) {
            Write-CustomError "Failed to initialize user secrets" -Fatal
        }
        
        # Initialize secrets from configuration files
        Initialize-UserSecrets -RootPath "../../"
    }

    # Get all required packages (core + discovered)
    Write-Log -Message "Getting required packages"
    $packages = Get-RequiredPackages -RootPath "../../"

    # Add NuGet packages
    Write-Log -Message "Installing all required packages (latest stable versions)"
    foreach ($package in $packages) {
        Write-Log -Message "Adding package: $package"
        if (Test-PackageCompatibility -Package $package -ProjectPath $projectPath) {
            $output = dotnet add package $package 2>&1
            if ($LASTEXITCODE -ne 0) {
                Write-CustomError "Failed to add package $package`: $output"
            }
        }
    }

    Write-Log -Message "Project setup completed successfully!"
    Write-Log -Message "Total packages installed: $($packages.Count)"

    # [Rest of the file content remains unchanged until the final catch block]

} catch {
    Write-CustomError $_.Exception.Message -Fatal
} finally {
    # Return to original directory
    Set-Location -Path "..\..\"
    Write-Log -Message "Script execution completed"
}