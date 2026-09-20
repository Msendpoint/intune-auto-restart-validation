### FILE: index.php
<?php 

session_start();
$accessToken = $_SESSION['ms_access_token'];

function graphCall(string $endpoint, string $accessToken, string $method = 'GET', array $body = null) {
    $ch = curl_init();
    $headers = [
        'Authorization: Bearer ' . $accessToken,
        'Content-Type: application/json'
    ];

    curl_setopt($ch, CURLOPT_URL, 'https://graph.microsoft.com' . $endpoint);
    curl_setopt($ch, CURLOPT_HTTPHEADER, $headers);
    curl_setopt($ch, CURLOPT_RETURNTRANSFER, 1);

    if ($method === 'POST' || $method === 'PATCH') {
        curl_setopt($ch, CURLOPT_CUSTOMREQUEST, $method);
        if ($body !== null) {
            curl_setopt($ch, CURLOPT_POSTFIELDS, json_encode($body));
        }
    }

    $response = curl_exec($ch);
    if (curl_errno($ch)) {
        throw new Exception('Graph API curl error: ' . curl_error($ch));
    }
    curl_close($ch);

    return json_decode($response, true);
}

function render_premium_card($title, $value, $trendValue = null, $trendType = 'up', $icon = '📊', $progress = null) {
    echo "<div class='premium-card'>";
    echo "<h2>{$icon} {$title}</h2>";
    echo "<p class='value'>{$value}</p>";
    if ($trendValue !== null) {
        echo "<p class='trend {$trendType}'>{$trendValue}</p>";
    }
    if ($progress !== null) {
        echo "<progress value='{$progress}' max='100'>{$progress}%</progress>";
    }
    echo "</div>";
}

try {
    $updateRings = graphCall('/beta/deviceManagement/updateRingConfigurations', $accessToken);
    foreach ($updateRings['value'] as $ring) {
        $trend = $ring['autoRestartBeforeDeadline'] ? 'up' : 'down';
        render_premium_card($ring['displayName'], json_encode($ring), null, $trend);
    }
} catch (Exception $e) {
    echo "Error: " . $e->getMessage();
}

?>

### FILE: scripts/Automation.ps1
#Requires -Modules Microsoft.Graph.DeviceManagement, Microsoft.Graph.Groups
<#
.SYNOPSIS
    Validates and optionally remediates Intune update ring configurations for auto-restart compliance.
.DESCRIPTION
    This script connects to Microsoft Graph to enumerate Intune update ring configurations, identify misconfigurations, and optionally updates settings to ensure compliance.
.EXAMPLE
    .\Automation.ps1 -RemediateNullDeadlines
#>

param(
    [Parameter(Mandatory = $false)]
    [switch]$RemediateNullDeadlines,

    [Parameter(Mandatory = $false)]
    [int]$DefaultQualityDeadlineDays = 5,

    [Parameter(Mandatory = $false)]
    [int]$DefaultFeatureDeadlineDays = 10,

    [Parameter(Mandatory = $false)]
    [int]$DefaultGracePeriodDays = 2,

    [Parameter(Mandatory = $false)]
    [string]$ExportPath = "$env:TEMP\WUfB_Validation_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"
)

<## Credentials and connection
    Set up authentication and connect to Microsoft Graph
##>
try {
    Connect-MgGraph -Scopes @(
        "DeviceManagementConfiguration.Read.All",
        "DeviceManagementManagedDevices.Read.All",
        "Group.Read.All",
        "DeviceManagementConfiguration.ReadWrite.All"
    ) -ErrorAction Stop
    Write-Verbose "[AUTH] Connected to Microsoft Graph"
} catch {
    Write-Error "[AUTH FAIL] Unable to connect to Microsoft Graph: $_"
    exit 1
}

try {
    # Gather update ring configurations
    $updateRings = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/beta/deviceManagement/updateRingConfigurations?`\$select=id,displayName,deadlineForQualityUpdatesInDays,deadlineForFeatureUpdatesInDays,deadlineGracePeriodInDays,autoRestartBeforeDeadline,deadlineNoAutoReboot,assignments" -OutputType PSObject -ErrorAction Stop

    foreach ($ring in $updateRings.value) {
        # Evaluate each update ring for compliance
        $issues = @()
        if (-not $ring.autoRestartBeforeDeadline) { $issues += "AUTO_RESTART_DISABLED" }
        if ($null -eq $ring.deadlineForQualityUpdatesInDays) { $issues += "NULL_QUALITY_DEADLINE" }
        if ($null -eq $ring.deadlineForFeatureUpdatesInDays) { $issues += "NULL_FEATURE_DEADLINE" }
        if ($null -eq $ring.deadlineGracePeriodInDays) { $issues += "NULL_GRACE_PERIOD" }

        if ($issues.Length -gt 0) {
            Write-Warning "[RING ISSUE] $($ring.displayName): $($issues -join ', ')"
            
            # Optionally fix any issues found
            if ($RemediateNullDeadlines -and $PSCmdlet.ShouldProcess($ring.displayName, "Patch NULL deadline values")) {
                $patchBody = @{
                    autoRestartBeforeDeadline = $true
                    deadlineForQualityUpdatesInDays = $DefaultQualityDeadlineDays
                    deadlineForFeatureUpdatesInDays = $DefaultFeatureDeadlineDays
                    deadlineGracePeriodInDays = $DefaultGracePeriodDays
                }
                
                try {
                    # Update ring
                    Invoke-MgGraphRequest -Method PATCH -Uri "https://graph.microsoft.com/beta/deviceManagement/updateRingConfigurations/$($ring.id)" -Body ($patchBody | ConvertTo-Json -Depth 3) -ContentType "application/json" -ErrorAction Stop
                    Write-Host "[REMEDIATED] $($ring.displayName)" -ForegroundColor Green
                } catch {
                    Write-Warning "[PATCH FAIL] $($ring.displayName): $_"
                }
            }
        }
    }
} catch {
    Write-Error "[GRAPH FAIL] Unable to retrieve Update Ring configurations: $_"
    exit 1
}

<##
.NOTES
    Author:      Souhaiel Morhag
    Company:     MSEndpoint.com
    Blog:        https://msendpoint.com
    Academy:     https://app.msendpoint.com/academy
    LinkedIn:    https://linkedin.com/in/souhaiel-morhag
    GitHub:      https://github.com/Msendpoint
    License:     MIT
##>