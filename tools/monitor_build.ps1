param(
    [string]$Repo = "RemusJ1337/Telegram-iOS"
)

$run = gh run list --repo $Repo --limit 1 --json databaseId,status,conclusion,name,createdAt,updatedAt,url | ConvertFrom-Json
if (-not $run) {
    Write-Host "No runs found for $Repo"
    exit 1
}

$runId = $run[0].databaseId
$status = $run[0].status
$conclusion = $run[0].conclusion
$url = $run[0].url

Write-Host "Run ID: $runId"
Write-Host "Status: $status"
Write-Host "Conclusion: $conclusion"
Write-Host "URL: $url"

$details = gh run view $runId --repo $Repo --json jobs | ConvertFrom-Json
if ($details.jobs) {
    foreach ($job in $details.jobs) {
        Write-Host "`nJob: $($job.name) [$($job.status) / $($job.conclusion)]"
        foreach ($step in $job.steps) {
            Write-Host "  - $($step.name): $($step.status) ($($step.conclusion))"
        }
    }
}
