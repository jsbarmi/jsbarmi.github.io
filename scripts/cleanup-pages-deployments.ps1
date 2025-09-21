param(
    [Parameter(Mandatory=$true)][string]$Owner,
    [Parameter(Mandatory=$true)][string]$Repo,
    [Parameter(Mandatory=$false)][int]$Keep = 1
)

# Requires: $env:GITHUB_TOKEN set with repo deployment delete permission.
if (-not $env:GITHUB_TOKEN) {
    Write-Error "GITHUB_TOKEN environment variable not set. Set it to a token with repo deployment permissions."; exit 1
}

$Headers = @{
  Authorization          = "Bearer $env:GITHUB_TOKEN"
  Accept                 = "application/vnd.github+json"
  "X-GitHub-Api-Version" = "2022-11-28"
}

function Invoke-GHApi {
    param([string]$Method, [string]$Url, [object]$Body)
    try {
        if ($Body) {
            return Invoke-RestMethod -Method $Method -Headers $Headers -Uri $Url -Body ($Body | ConvertTo-Json -Depth 5)
        } else {
            return Invoke-RestMethod -Method $Method -Headers $Headers -Uri $Url
        }
    } catch {
        Write-Warning "API call failed: $Method $Url -> $($_.Exception.Message)"; throw
    }
}

# 1) List deployments (paginate just in case)
$perPage = 100
$page = 1
$all = @()
while ($true) {
    $url = "https://api.github.com/repos/$Owner/$Repo/deployments?per_page=$perPage&page=$page"
    $batch = Invoke-GHApi -Method GET -Url $url
    if (-not $batch -or $batch.Count -eq 0) { break }
    $all += $batch
    if ($batch.Count -lt $perPage) { break }
    $page++
}

if (-not $all -or $all.Count -eq 0) {
    Write-Host "No deployments found."; exit 0
}

# Sort newest-first by created_at
$sorted = $all | Sort-Object -Property created_at -Descending
$keepList = $sorted | Select-Object -First $Keep
$deleteList = $sorted | Select-Object -Skip $Keep

Write-Host "Found $($all.Count) deployments. Keeping $Keep (newest). Deleting $($deleteList.Count)."

foreach ($d in $deleteList) {
    $id = $d.id
    # 2) Mark inactive to allow deletion
    $statusUrl = "https://api.github.com/repos/$Owner/$Repo/deployments/$id/statuses"
    $statusBody = @{ state = "inactive"; description = "cleanup of old Pages deployments" }
    try {
        Invoke-GHApi -Method POST -Url $statusUrl -Body $statusBody | Out-Null
    } catch {
        Write-Warning "Could not mark deployment $id inactive. Proceeding to delete anyway."
    }

    # 3) Delete deployment
    $delUrl = "https://api.github.com/repos/$Owner/$Repo/deployments/$id"
    try {
        Invoke-GHApi -Method DELETE -Url $delUrl | Out-Null
        Write-Host "Deleted deployment $id"
    } catch {
        Write-Warning "Failed to delete deployment $id"
    }
}

Write-Host "Cleanup complete."
