# =============================================================================
# setup-windows-rdp.ps1 — Enable and configure RDP on Windows VM
#
# Run inside the Windows VM (192.168.20.10) as Administrator.
# Enables Remote Desktop, opens firewall, and configures NLA.
#
# Usage (PowerShell as Admin):
#   Set-ExecutionPolicy Bypass -Scope Process -Force
#   .\setup-windows-rdp.ps1
#
# After running, connect from ThinkPad:
#   xfreerdp /v:192.168.20.10 /u:Administrator /size:1920x1080
# =============================================================================

$ErrorActionPreference = "Stop"

Write-Host "=== Windows RDP Setup ===" -ForegroundColor Cyan
Write-Host "VM: 192.168.20.10 (RX 6800 XT passthrough)" -ForegroundColor Gray

# --- 1. Enable Remote Desktop ---
Write-Host "`n[1/5] Enabling Remote Desktop..." -ForegroundColor Yellow

Set-ItemProperty -Path "HKLM:\System\CurrentControlSet\Control\Terminal Server" `
    -Name "fDenyTSConnections" -Value 0

Write-Host "  [PASS] Remote Desktop enabled" -ForegroundColor Green

# --- 2. Enable Network Level Authentication (NLA) ---
Write-Host "[2/5] Enabling Network Level Authentication..." -ForegroundColor Yellow

Set-ItemProperty -Path "HKLM:\System\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp" `
    -Name "UserAuthentication" -Value 1

Write-Host "  [PASS] NLA enabled" -ForegroundColor Green

# --- 3. Configure Firewall ---
Write-Host "[3/5] Configuring firewall rules..." -ForegroundColor Yellow

# Enable built-in RDP firewall rules
Enable-NetFirewallRule -DisplayGroup "Remote Desktop"

# Additional rule: Allow RDP from management subnet only
$ruleExists = Get-NetFirewallRule -DisplayName "RDP-Management-Subnet" -ErrorAction SilentlyContinue
if (-not $ruleExists) {
    New-NetFirewallRule -DisplayName "RDP-Management-Subnet" `
        -Direction Inbound `
        -Protocol TCP `
        -LocalPort 3389 `
        -RemoteAddress @("192.168.16.0/24", "192.168.20.0/24") `
        -Action Allow `
        -Profile Domain,Private
    Write-Host "  [PASS] Firewall rule created (management + VM subnets)" -ForegroundColor Green
} else {
    Write-Host "  [INFO] Firewall rule already exists" -ForegroundColor Blue
}

# --- 4. Start RDP Service ---
Write-Host "[4/5] Starting Remote Desktop Services..." -ForegroundColor Yellow

Set-Service -Name "TermService" -StartupType Automatic
Start-Service -Name "TermService" -ErrorAction SilentlyContinue

$svc = Get-Service -Name "TermService"
if ($svc.Status -eq "Running") {
    Write-Host "  [PASS] TermService running" -ForegroundColor Green
} else {
    Write-Host "  [WARN] TermService status: $($svc.Status)" -ForegroundColor Yellow
}

# --- 5. Verify Configuration ---
Write-Host "[5/5] Verifying configuration..." -ForegroundColor Yellow

$rdpEnabled = (Get-ItemProperty -Path "HKLM:\System\CurrentControlSet\Control\Terminal Server").fDenyTSConnections
$nlaEnabled = (Get-ItemProperty -Path "HKLM:\System\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp").UserAuthentication
$port = (Get-ItemProperty -Path "HKLM:\System\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp").PortNumber

Write-Host "  RDP Enabled:    $(if ($rdpEnabled -eq 0) { 'Yes' } else { 'No' })" -ForegroundColor White
Write-Host "  NLA Enabled:    $(if ($nlaEnabled -eq 1) { 'Yes' } else { 'No' })" -ForegroundColor White
Write-Host "  RDP Port:       $port" -ForegroundColor White
Write-Host "  Service Status: $($svc.Status)" -ForegroundColor White

# --- Summary ---
Write-Host "`n=== RDP Setup Complete ===" -ForegroundColor Green
Write-Host ""
Write-Host "NEXT STEPS:" -ForegroundColor Cyan
Write-Host "  1. From ThinkPad (Linux):"
Write-Host "       xfreerdp /v:192.168.20.10 /u:Administrator /size:1920x1080 /dynamic-resolution"
Write-Host ""
Write-Host "  2. From ThinkPad (Windows):"
Write-Host "       mstsc /v:192.168.20.10"
Write-Host ""
Write-Host "  3. Test connectivity:"
Write-Host "       Test-NetConnection -ComputerName 192.168.20.10 -Port 3389"
Write-Host ""
