param(
  [Parameter(Mandatory = $true)] [string] $Email,
  [Parameter(Mandatory = $true)] [string] $Password,
  [switch] $WhatIf
)

$ErrorActionPreference = 'Stop'
$projectId = 'quick-brew-64673'
$apiKey = 'AIzaSyDlxmUqWTadFACJvQEkZmwGpxz__3pnjkk'
$shopId = 'coffee-shop-b'
$csvPath = Join-Path $PSScriptRoot '..\SEVEN.csv'

function Get-IdToken {
  $body = @{ email = $Email; password = $Password; returnSecureToken = $true } |
    ConvertTo-Json -Compress
  (Invoke-RestMethod -Method Post -ContentType 'application/json' -Uri "https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=$apiKey" -Body $body).idToken
}

function Normalize-Name([string] $value) {
  ([Regex]::Replace($value.Normalize([Text.NormalizationForm]::FormD), '[^\p{L}\p{Nd}]', '')).ToLowerInvariant()
}

function Get-AllDocuments([string] $baseUri, [hashtable] $headers) {
  $documents = @()
  $nextPageToken = $null
  do {
    $pageUri = if ($nextPageToken) { "${baseUri}?pageToken=$([uri]::EscapeDataString($nextPageToken))" } else { $baseUri }
    $page = Invoke-RestMethod -Headers $headers -Uri $pageUri
    $documents += @($page.documents)
    $nextPageToken = $page.nextPageToken
  } while ($nextPageToken)
  $documents
}

function Update-Fields([string] $documentPath, [hashtable] $fields, [hashtable] $headers) {
  $masks = ($fields.Keys | ForEach-Object { "updateMask.fieldPaths=$_" }) -join '&'
  $uri = "https://firestore.googleapis.com/v1/${documentPath}?$masks"
  $body = @{ fields = $fields } | ConvertTo-Json -Depth 6 -Compress
  Invoke-RestMethod -Method Patch -Headers $headers -ContentType 'application/json' -Uri $uri -Body $body | Out-Null
}

$token = Get-IdToken
$headers = @{ Authorization = "Bearer $token" }
$root = "https://firestore.googleapis.com/v1/projects/$projectId/databases/(default)/documents/shops/$shopId"
$rows = Import-Csv -LiteralPath $csvPath
$menuRows = @($rows | Where-Object { $_.'Main Category' -ne 'Add-Ons' })
$addOnRows = @($rows | Where-Object { $_.'Main Category' -eq 'Add-Ons' })
$menuDocs = Get-AllDocuments "$root/menu" $headers
$addOnDocs = Get-AllDocuments "$root/addons" $headers

$menuByName = @{}
foreach ($row in $menuRows) {
  $key = Normalize-Name $row.'Product Name'
  if (-not $menuByName.ContainsKey($key)) { $menuByName[$key] = @() }
  $menuByName[$key] += $row
}
$addOnByName = @{}
foreach ($row in $addOnRows) { $addOnByName[(Normalize-Name $row.'Product Name')] = $row }

$changed = 0
$unmatched = @()
foreach ($doc in $menuDocs) {
  $name = $doc.fields.name.stringValue
  $key = Normalize-Name $name
  if (-not $menuByName.ContainsKey($key)) { $unmatched += $name; continue }
  $candidates = @($menuByName[$key])
  $currentCategory = $doc.fields.category.stringValue
  $currentSubCategory = $doc.fields.subCategory.stringValue
  $match = @($candidates | Where-Object { $_.'Main Category' -eq $currentCategory -or $_.Kind -eq $currentSubCategory })
  if ($match.Count -ne 1) {
    if ($candidates.Count -eq 1) { $match = $candidates } else { $unmatched += "$name (ambiguous)"; continue }
  }
  $row = $match[0]
  if ($currentCategory -eq $row.'Main Category' -and $currentSubCategory -eq $row.Kind) { continue }
  $changed++
  if ($WhatIf) { Write-Output "Would update menu: $name -> $($row.'Main Category') / $($row.Kind)"; continue }
  Update-Fields $doc.name @{
    category = @{ stringValue = $row.'Main Category' }
    subCategory = @{ stringValue = $row.Kind }
  } $headers
  Write-Output "Updated menu: $name -> $($row.'Main Category') / $($row.Kind)"
}

$addOnChanged = 0
foreach ($doc in $addOnDocs) {
  $name = $doc.fields.name.stringValue
  $key = Normalize-Name $name
  if (-not $addOnByName.ContainsKey($key)) { $unmatched += "Add-on: $name"; continue }
  $group = $addOnByName[$key].Kind
  if ($doc.fields.group.stringValue -eq $group) { continue }
  $addOnChanged++
  if ($WhatIf) { Write-Output "Would update add-on: $name -> $group"; continue }
  Update-Fields $doc.name @{ group = @{ stringValue = $group } } $headers
  Write-Output "Updated add-on: $name -> $group"
}

Write-Output "Menu categories changed: $changed. Add-on groups changed: $addOnChanged."
if ($unmatched.Count -gt 0) { Write-Warning "Left unchanged: $($unmatched -join ', ')" }
