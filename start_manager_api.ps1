param(
    [ValidateSet("dev", "test", "prod")]
    [string]$Profile = "dev",

    [switch]$Help,
    [switch]$UseJar,
    [switch]$BuildFirst,
    [switch]$ClearLiquibaseChecksum,
    [switch]$NoJavaBootstrap,
    [switch]$NoMavenBootstrap,

    [bool]$EnsureDatabase = $true,
    [string]$MavenVersion = "3.9.9",
    [int]$RequiredJavaMajor = 21,

    [string]$Database = "",
    [string]$MySqlHost = "127.0.0.1",
    [int]$MySqlPort = 3306,
    [string]$MySqlUser = "root",
    [string]$MySqlPassword = "123456"
)

$ErrorActionPreference = "Stop"
$projectRoot = $PSScriptRoot
Set-Location $projectRoot

function Show-Help {
    Write-Host "Usage:"
    Write-Host "  .\start_manager_api.ps1 [-Profile dev|test|prod]"
    Write-Host "  .\start_manager_api.ps1 -UseJar [-BuildFirst] [-Profile dev|test|prod]"
    Write-Host "  .\start_manager_api.ps1 -ClearLiquibaseChecksum [-Database richard_esp32_server]"
    Write-Host ""
    Write-Host "Auto behaviors (default):"
    Write-Host "  - Auto bootstrap JDK $RequiredJavaMajor if local Java is missing or lower."
    Write-Host "  - Auto bootstrap Maven if mvn/mvnw is missing."
    Write-Host "  - Auto ensure MySQL database exists (tables are created by Liquibase on startup)."
    Write-Host ""
    Write-Host "Disable auto behaviors:"
    Write-Host "  -NoJavaBootstrap"
    Write-Host "  -NoMavenBootstrap"
    Write-Host "  -EnsureDatabase:`$false"
    Write-Host ""
    Write-Host "Examples:"
    Write-Host "  .\start_manager_api.ps1"
    Write-Host "  .\start_manager_api.ps1 -UseJar -BuildFirst"
    Write-Host "  .\start_manager_api.ps1 -ClearLiquibaseChecksum"
    Write-Host "  .\start_manager_api.ps1 -Database richard_esp32_server -MySqlUser root -MySqlPassword 123456"
}

if ($Help) {
    Show-Help
    exit 0
}

function Get-ToolPath {
    param([Parameter(Mandatory = $true)][string]$Name)
    $cmd = Get-Command $Name -ErrorAction SilentlyContinue
    if ($null -eq $cmd) { return $null }
    return $cmd.Source
}

function Resolve-DatabaseName {
    if ($Database -and $Database.Trim().Length -gt 0) {
        return $Database.Trim()
    }

    $candidates = @(
        (Join-Path $projectRoot "src/main/resources/application-$Profile.yml"),
        (Join-Path $projectRoot "src/main/resources/application.yml")
    )
    $regex = [regex]'jdbc:mysql://[^/]+/(?<db>[^?\s]+)'

    foreach ($file in $candidates) {
        if (-not (Test-Path $file)) { continue }
        $content = Get-Content -Path $file -Raw
        $m = $regex.Match($content)
        if ($m.Success) {
            return $m.Groups["db"].Value
        }
    }

    return "richard_esp32_server"
}

function Get-MySqlCommand {
    $mysql = Get-ToolPath -Name "mysql"
    if ($mysql) { return $mysql }

    $fallbacks = @(
        "D:\MySQL\MySQL Server 8.0\bin\mysql.exe",
        "D:\MySQL\MySQL Server 8.4\bin\mysql.exe",
        "$env:ProgramFiles\MySQL\MySQL Server 8.0\bin\mysql.exe",
        "$env:ProgramFiles\MySQL\MySQL Server 8.4\bin\mysql.exe",
        "$env:ProgramFiles\MySQL\MySQL Server 9.0\bin\mysql.exe"
    )

    foreach ($path in $fallbacks) {
        if (Test-Path $path) { return $path }
    }

    return $null
}

function Get-JavaCommand {
    $java = Get-ToolPath -Name "java"
    if ($java) { return $java }

    if ($env:JAVA_HOME) {
        $javaFromHome = Join-Path $env:JAVA_HOME "bin/java.exe"
        if (Test-Path $javaFromHome) { return $javaFromHome }
    }

    $portableJava = Join-Path $projectRoot ".tools/jdk-21/bin/java.exe"
    if (Test-Path $portableJava) { return $portableJava }

    return $null
}

function Get-JavaMajor {
    param([Parameter(Mandatory = $true)][string]$JavaCmd)

    $line = $null
    $hadNativePref = $false
    $nativePrefOld = $null
    $nativePrefVar = Get-Variable -Name PSNativeCommandUseErrorActionPreference -Scope Global -ErrorAction SilentlyContinue
    if ($nativePrefVar) {
        $hadNativePref = $true
        $nativePrefOld = [bool]$nativePrefVar.Value
    }

    try {
        if ($hadNativePref) {
            $global:PSNativeCommandUseErrorActionPreference = $false
        }
        $line = (& $JavaCmd --version 2>&1 | Select-Object -First 1)
        if (-not $line) {
            $line = (& $JavaCmd -version 2>&1 | Select-Object -First 1)
        }
    } finally {
        if ($hadNativePref) {
            $global:PSNativeCommandUseErrorActionPreference = $nativePrefOld
        }
    }

    if (-not $line) { return -1 }

    $text = [string]$line
    $m = [regex]::Match($text, '"(?<v>\d+)(?:\.[^"]*)?"')
    if (-not $m.Success) {
        $m = [regex]::Match($text, '(?:openjdk|java)\s+(?<v>\d+)(?:\.\d+)*')
    }
    if (-not $m.Success) { return -1 }

    return [int]$m.Groups["v"].Value
}

function Use-JavaHome {
    param([Parameter(Mandatory = $true)][string]$JavaHome)

    $javaBin = Join-Path $JavaHome "bin"
    if (-not (Test-Path (Join-Path $javaBin "java.exe"))) {
        throw "Invalid JAVA_HOME: $JavaHome"
    }

    $env:JAVA_HOME = $JavaHome
    if (-not (($env:Path -split ";") -contains $javaBin)) {
        $env:Path = "$javaBin;$env:Path"
    }
}

function Install-PortableJdk21 {
    $toolsDir = Join-Path $projectRoot ".tools"
    $jdkAliasDir = Join-Path $toolsDir "jdk-21"
    $javaExe = Join-Path $jdkAliasDir "bin/java.exe"
    if (Test-Path $javaExe) { return $jdkAliasDir }

    New-Item -ItemType Directory -Path $toolsDir -Force | Out-Null
    $zipPath = Join-Path $toolsDir "jdk-21-windows-x64.zip"
    $tmpExtract = Join-Path $toolsDir "_jdk_extract"

    if (-not (Test-Path $zipPath)) {
        $url = "https://api.adoptium.net/v3/binary/latest/21/ga/windows/x64/jdk/hotspot/normal/eclipse"
        Write-Host "[INFO] Downloading portable JDK 21 from Adoptium..."
        Invoke-WebRequest -Uri $url -OutFile $zipPath -UseBasicParsing
    }

    if (Test-Path $tmpExtract) {
        Remove-Item -Path $tmpExtract -Recurse -Force
    }

    Write-Host "[INFO] Extracting JDK to $toolsDir"
    Expand-Archive -LiteralPath $zipPath -DestinationPath $tmpExtract -Force

    $foundJava = Get-ChildItem -Path $tmpExtract -Recurse -File -Filter "java.exe" |
        Where-Object { $_.FullName -match "\\bin\\java\.exe$" } |
        Select-Object -First 1

    if (-not $foundJava) {
        throw "Could not locate java.exe in downloaded JDK package."
    }

    $jdkHome = Split-Path (Split-Path $foundJava.FullName -Parent) -Parent

    if (Test-Path $jdkAliasDir) {
        Remove-Item -Path $jdkAliasDir -Recurse -Force
    }
    Move-Item -Path $jdkHome -Destination $jdkAliasDir

    Remove-Item -Path $tmpExtract -Recurse -Force
    return $jdkAliasDir
}

function Ensure-JavaRequirement {
    $javaCmd = Get-JavaCommand
    if ($javaCmd) {
        $major = Get-JavaMajor -JavaCmd $javaCmd
        if ($major -ge $RequiredJavaMajor) {
            $javaHome = Split-Path (Split-Path $javaCmd -Parent) -Parent
            Use-JavaHome -JavaHome $javaHome
            Write-Host "[INFO] Java $major detected at $javaCmd"
            return
        }
        Write-Host "[WARN] Java $major detected, but $RequiredJavaMajor+ is required."
    } else {
        Write-Host "[WARN] Java not found in PATH/JAVA_HOME."
    }

    if ($NoJavaBootstrap) {
        throw "Required Java $RequiredJavaMajor not available and -NoJavaBootstrap is enabled."
    }

    $jdkHome = Install-PortableJdk21
    Use-JavaHome -JavaHome $jdkHome
    $javaCmd2 = Join-Path $jdkHome "bin/java.exe"
    $major2 = Get-JavaMajor -JavaCmd $javaCmd2
    if ($major2 -lt $RequiredJavaMajor) {
        throw "Portable JDK bootstrap failed. Found Java major=$major2"
    }
    Write-Host "[INFO] Using portable JDK at $jdkHome"
}

function Get-PortableMavenPath {
    $mvnCmd = Join-Path $projectRoot ".tools/apache-maven-$MavenVersion/bin/mvn.cmd"
    if (Test-Path $mvnCmd) { return $mvnCmd }
    return $null
}

function Install-PortableMaven {
    $toolsDir = Join-Path $projectRoot ".tools"
    $mavenDir = Join-Path $toolsDir "apache-maven-$MavenVersion"
    $mvnCmd = Join-Path $mavenDir "bin/mvn.cmd"
    if (Test-Path $mvnCmd) { return $mvnCmd }

    New-Item -ItemType Directory -Path $toolsDir -Force | Out-Null
    $zipPath = Join-Path $toolsDir "apache-maven-$MavenVersion-bin.zip"

    if (-not (Test-Path $zipPath)) {
        $urls = @(
            "https://archive.apache.org/dist/maven/maven-3/$MavenVersion/binaries/apache-maven-$MavenVersion-bin.zip",
            "https://dlcdn.apache.org/maven/maven-3/$MavenVersion/binaries/apache-maven-$MavenVersion-bin.zip"
        )

        $downloaded = $false
        foreach ($url in $urls) {
            try {
                Write-Host "[INFO] Downloading Maven $MavenVersion from $url"
                Invoke-WebRequest -Uri $url -OutFile $zipPath -UseBasicParsing
                $downloaded = $true
                break
            } catch {
                Write-Host "[WARN] Download failed from $url"
            }
        }

        if (-not $downloaded) {
            throw "Unable to download Maven $MavenVersion."
        }
    }

    Write-Host "[INFO] Extracting Maven to $toolsDir"
    Expand-Archive -LiteralPath $zipPath -DestinationPath $toolsDir -Force

    if (-not (Test-Path $mvnCmd)) {
        throw "Portable Maven install failed. Expected: $mvnCmd"
    }

    return $mvnCmd
}

function Get-MavenCommand {
    $mvn = Get-ToolPath -Name "mvn"
    if ($mvn) { return $mvn }

    $mvnwCmd = Join-Path $projectRoot "mvnw.cmd"
    if (Test-Path $mvnwCmd) { return $mvnwCmd }

    $portable = Get-PortableMavenPath
    if ($portable) { return $portable }

    if (-not $NoMavenBootstrap) {
        $installed = Install-PortableMaven
        return $installed
    }

    return $null
}

function Ensure-DatabaseExists {
    param([Parameter(Mandatory = $true)][string]$DbName)

    $mysql = Get-MySqlCommand
    if (-not $mysql) {
        throw "mysql client not found; cannot ensure database '$DbName'."
    }

    $baseArgs = @(
        "-h$MySqlHost",
        "-P$MySqlPort",
        "-u$MySqlUser",
        "-p$MySqlPassword",
        "-N",
        "-B"
    )

    $checkSql = "SELECT SCHEMA_NAME FROM information_schema.SCHEMATA WHERE SCHEMA_NAME='$DbName';"
    $exists = (& $mysql @baseArgs -e $checkSql | Out-String).Trim()

    if (-not $exists) {
        Write-Host "[INFO] Database '$DbName' does not exist. Creating..."
        $createSql = "CREATE DATABASE IF NOT EXISTS ``$DbName`` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
        & $mysql @baseArgs -e $createSql | Out-Null
    } else {
        Write-Host "[INFO] Database '$DbName' already exists."
    }

    $countSql = "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='$DbName';"
    $tableCountRaw = (& $mysql @baseArgs -e $countSql | Out-String).Trim()
    $tableCount = 0
    if ($tableCountRaw -match "^\d+$") {
        $tableCount = [int]$tableCountRaw
    }

    if ($tableCount -eq 0) {
        Write-Host "[INFO] Database '$DbName' is empty. Liquibase will create tables on startup."
    } else {
        Write-Host "[INFO] Database '$DbName' has $tableCount table(s)."
    }
}

function Clear-LiquibaseChecksums {
    param([Parameter(Mandatory = $true)][string]$DbName)

    $mysql = Get-MySqlCommand
    if (-not $mysql) {
        throw "mysql client not found; cannot clear Liquibase checksums."
    }

    $baseArgs = @(
        "-h$MySqlHost",
        "-P$MySqlPort",
        "-u$MySqlUser",
        "-p$MySqlPassword",
        "-D$DbName",
        "-N",
        "-B"
    )

    $existsSql = "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='$DbName' AND table_name='databasechangelog';"
    $existsRaw = (& $mysql @baseArgs -e $existsSql | Out-String).Trim()
    $exists = 0
    if ($existsRaw -match "^\d+$") {
        $exists = [int]$existsRaw
    }

    if ($exists -eq 0) {
        Write-Host "[INFO] No databasechangelog table found in '$DbName'. Skip checksum cleanup."
        return
    }

    Write-Host "[INFO] Clearing Liquibase checksums in '$DbName'"
    $sql = "UPDATE databasechangelog SET MD5SUM = NULL; SELECT ROW_COUNT() AS updated_rows;"
    & $mysql @baseArgs -e $sql
}

function Start-WithJar {
    param([Parameter(Mandatory = $true)][string]$JarPath)

    $javaCmd = Get-JavaCommand
    if (-not $javaCmd) {
        throw "java command not found."
    }

    Write-Host "[INFO] Starting with jar, profile=$Profile"
    & $javaCmd "-jar" $JarPath "--spring.profiles.active=$Profile"
    exit $LASTEXITCODE
}

$resolvedDatabase = Resolve-DatabaseName
$jarPath = Join-Path $projectRoot "target/richard-esp32-api.jar"

if ($EnsureDatabase) {
    Ensure-DatabaseExists -DbName $resolvedDatabase
}

if ($ClearLiquibaseChecksum) {
    Clear-LiquibaseChecksums -DbName $resolvedDatabase
}

Ensure-JavaRequirement

if ($UseJar) {
    if ($BuildFirst -or -not (Test-Path $jarPath)) {
        $mavenCmd = Get-MavenCommand
        if (-not $mavenCmd) {
            throw "Maven not found and bootstrap disabled; cannot build jar."
        }

        Write-Host "[INFO] Building jar..."
        & $mavenCmd "-DskipTests" "clean" "package"
    }

    if (-not (Test-Path $jarPath)) {
        throw "Executable jar not found: $jarPath"
    }

    Start-WithJar -JarPath $jarPath
}

$mavenCmd = Get-MavenCommand
if ($mavenCmd) {
    Write-Host "[INFO] Starting with Maven, profile=$Profile"
    & $mavenCmd "-DskipTests" "spring-boot:run" "-Dspring-boot.run.profiles=$Profile"
    exit $LASTEXITCODE
}

if (Test-Path $jarPath) {
    Write-Host "[WARN] Maven not found. Falling back to existing jar."
    Start-WithJar -JarPath $jarPath
}

throw "Neither Maven nor target jar is available. Install Maven, enable bootstrap, or build target/richard-esp32-api.jar first."
