# =============================================================================
# setup-windows-smb.ps1 — Create SMB file shares on Windows VM
#
# Run inside the Windows VM (192.168.20.10) as Administrator.
# Creates standard project directories and shares them on the network.
#
# Usage (PowerShell as Admin):
#   Set-ExecutionPolicy Bypass -Scope Process -Force
#   .\setup-windows-smb.ps1
#
# After running, access from ThinkPad:
#   Windows: \\192.168.20.10\Projects
#   Linux:   mount -t cifs //192.168.20.10/Projects /mnt/projects
# =============================================================================

$ErrorActionPreference = "Stop"

# --- Configuration ---
$BasePath = "D:\Shares"
$Shares = @(
    @{ Name = "Projects";  Path = "$BasePath\Projects";  Description = "Development projects" },
    @{ Name = "Documents"; Path = "$BasePath\Documents"; Description = "Business documents" },
    @{ Name = "Backups";   Path = "$BasePath\Backups";   Description = "Backup storage" },
    @{ Name = "FitnaAI";   Path = "$BasePath\FitnaAI";   Description = "FitnaAI project data" }
)
$AllowedSubnets = @("192.168.16.0/24", "192.168.20.0/24")

Write-Host "=== Windows SMB Share Setup ===" -ForegroundColor Cyan
Write-Host "Base path: $BasePath" -ForegroundColor Gray

# --- 1. Create directories ---
Write-Host "`n[1/4] Creating share directories..." -ForegroundColor Yellow

foreach ($share in $Shares) {
    if (-not (Test-Path $share.Path)) {
        New-Item -Path $share.Path -ItemType Directory -Force | Out-Null
        Write-Host "  [PASS] Created: $($share.Path)" -ForegroundColor Green
    } else {
        Write-Host "  [INFO] Exists:  $($share.Path)" -ForegroundColor Blue
    }
}

# --- 2. Create SMB shares ---
Write-Host "`n[2/4] Creating network shares..." -ForegroundColor Yellow

foreach ($share in $Shares) {
    $existing = Get-SmbShare -Name $share.Name -ErrorAction SilentlyContinue
    if (-not $existing) {
        New-SmbShare -Name $share.Name `
            -Path $share.Path `
            -Description $share.Description `
            -FullAccess "Administrators" `
            -ChangeAccess "Authenticated Users" `
            -FolderEnumerationMode AccessBased

        Write-Host "  [PASS] Shared: \\$(hostname)\$($share.Name)" -ForegroundColor Green
    } else {
        Write-Host "  [INFO] Already shared: \\$(hostname)\$($share.Name)" -ForegroundColor Blue
    }
}

# --- 3. Configure firewall ---
Write-Host "`n[3/4] Configuring SMB firewall rules..." -ForegroundColor Yellow

# Enable built-in File and Printer Sharing rules
Enable-NetFirewallRule -DisplayGroup "File and Printer Sharing"

# Restrict SMB to management and VM subnets
$ruleExists = Get-NetFirewallRule -DisplayName "SMB-Management-Subnet" -ErrorAction SilentlyContinue
if (-not $ruleExists) {
    New-NetFirewallRule -DisplayName "SMB-Management-Subnet" `
        -Direction Inbound `
        -Protocol TCP `
        -LocalPort 445 `
        -RemoteAddress $AllowedSubnets `
        -Action Allow `
        -Profile Domain,Private
    Write-Host "  [PASS] Firewall rule created (SMB restricted to local subnets)" -ForegroundColor Green
} else {
    Write-Host "  [INFO] Firewall rule already exists" -ForegroundColor Blue
}

# --- 4. Verify ---
Write-Host "`n[4/4] Verifying shares..." -ForegroundColor Yellow

$allShares = Get-SmbShare | Where-Object { $_.Name -notlike '*$' }
Write-Host ""
Write-Host "  Active shares:" -ForegroundColor White
foreach ($s in $allShares) {
    Write-Host "    \\$(hostname)\$($s.Name)  ->  $($s.Path)" -ForegroundColor White
}

# --- Summary ---
Write-Host "`n=== SMB Setup Complete ===" -ForegroundColor Green
Write-Host ""
Write-Host "NEXT STEPS:" -ForegroundColor Cyan
Write-Host ""
Write-Host "  From ThinkPad (Windows):"
Write-Host "    net use P: \\192.168.20.10\Projects"
Write-Host "    net use D: \\192.168.20.10\Documents"
Write-Host "    net use F: \\192.168.20.10\FitnaAI"
Write-Host ""
Write-Host "  From ThinkPad (Linux):"
Write-Host "    sudo mount -t cifs //192.168.20.10/Projects /mnt/projects -o username=Administrator,uid=1000"
Write-Host "    sudo mount -t cifs //192.168.20.10/FitnaAI /mnt/fitnaai -o username=Administrator,uid=1000"
Write-Host ""
Write-Host "  Permanent mount (/etc/fstab):"
Write-Host "    //192.168.20.10/Projects  /mnt/projects  cifs  credentials=/root/.smbcredentials,uid=1000,gid=1000  0  0"
Write-Host ""
