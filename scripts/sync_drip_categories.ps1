param(
  [Parameter(Mandatory = $true)] [string] $Email,
  [Parameter(ValueFromPipeline = $true)] [string] $PasswordInput,
  [switch] $WhatIf,
  [switch] $VerifyOnly
)

$ErrorActionPreference = 'Stop'
$projectId = 'quick-brew-64673'
$apiKey = 'AIzaSyDlxmUqWTadFACJvQEkZmwGpxz__3pnjkk'
$shopId = 'coffee-shop-a'
$csvPath = Join-Path $PSScriptRoot '..\DRIP AND CO MENU.csv'

function Get-IdToken {
  if (-not [string]::IsNullOrWhiteSpace($PasswordInput)) {
    $plainPassword = $PasswordInput
  } else {
    $securePassword = Read-Host 'Firebase password' -AsSecureString
    $plainPassword = [Net.NetworkCredential]::new('', $securePassword).Password
  }
  $body = @{ email = $Email; password = $plainPassword; returnSecureToken = $true } |
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
  # PS 5.1 sends string bodies as Latin-1, which mangles Vietnamese names; send UTF-8 bytes.
  Invoke-RestMethod -Method Patch -Headers $headers -ContentType 'application/json; charset=utf-8' -Uri $uri -Body ([Text.Encoding]::UTF8.GetBytes($body)) | Out-Null
}

function New-Document([string] $collectionPath, [hashtable] $fields, [hashtable] $headers) {
  $uri = "https://firestore.googleapis.com/v1/$collectionPath"
  $body = @{ fields = $fields } | ConvertTo-Json -Depth 10 -Compress
  Invoke-RestMethod -Method Post -Headers $headers -ContentType 'application/json; charset=utf-8' -Uri $uri -Body ([Text.Encoding]::UTF8.GetBytes($body)) | Out-Null
}

function Get-MenuFields($row, [bool] $includeName) {
  $grande = if ($row.Grande) { [int]$row.Grande * 100 } else { $null }
  $venti = if ($row.Venti) { [int]$row.Venti * 100 } else { $null }
  $fields = @{
    category = @{ stringValue = $row.'Main Category' }
    subCategory = @{ stringValue = $row.Kind }
    sort = @{ doubleValue = [double]$row._sort }
  }
  if ($includeName) {
    $fields.name = @{ stringValue = $row.'Product Name' }
    $fields.imageBase64 = @{ nullValue = $null }
  }
  if ($null -ne $grande -and $null -ne $venti) {
    $fields.sizePrices = @{ mapValue = @{ fields = @{
      medium = @{ integerValue = $grande.ToString() }
      large = @{ integerValue = $venti.ToString() }
    } } }
    $fields.priceCents = @{ nullValue = $null }
  } else {
    $price = if ($null -ne $venti) { $venti } else { $grande }
    $fields.sizePrices = @{ nullValue = $null }
    $fields.priceCents = @{ integerValue = $price.ToString() }
  }
  $fields
}

$token = Get-IdToken
$headers = @{ Authorization = "Bearer $token" }
$root = "https://firestore.googleapis.com/v1/projects/$projectId/databases/(default)/documents/shops/$shopId"
$rows = @(Import-Csv -LiteralPath $csvPath -Encoding UTF8)
for ($index = 0; $index -lt $rows.Count; $index++) {
  $rows[$index] | Add-Member -NotePropertyName _sort -NotePropertyValue $index
}
$menuDocs = Get-AllDocuments "$root/menu" $headers

if ($VerifyOnly) {
  Write-Output "Live Drip & Co menu documents: $($menuDocs.Count)"
  $menuDocs |
    Group-Object { $_.fields.category.stringValue } |
    Sort-Object Name |
    ForEach-Object {
      $subCategories = @($_.Group | ForEach-Object { $_.fields.subCategory.stringValue } | Sort-Object -Unique)
      Write-Output "$($_.Name): $($_.Count) drinks; subcategories: $($subCategories -join ', ')"
    }
  return
}

$rowsByName = @{}
foreach ($row in $rows) {
  $key = Normalize-Name $row.'Product Name'
  if (-not $rowsByName.ContainsKey($key)) { $rowsByName[$key] = @() }
  $rowsByName[$key] += $row
}

$changed = 0
$unmatched = @()
$usedRows = [Collections.Generic.HashSet[int]]::new()
foreach ($doc in $menuDocs) {
  $name = $doc.fields.name.stringValue
  $key = Normalize-Name $name
  if (-not $rowsByName.ContainsKey($key)) { $unmatched += $name; continue }

  $candidates = @($rowsByName[$key])
  $currentCategory = $doc.fields.category.stringValue
  $currentSubCategory = $doc.fields.subCategory.stringValue
  $match = @($candidates | Where-Object {
    $_.'Main Category' -eq $currentCategory -or $_.Kind -eq $currentSubCategory
  })

  if ($match.Count -ne 1) {
    if ($candidates.Count -eq 1) {
      $match = $candidates
    } elseif (@($candidates | Where-Object { $_.Kind -eq 'Specialty Coffee' }).Count -eq 1) {
      # The existing 50/60 drink is the Specialty Coffee entry. The separate
      # Hello Vietnam item is not created here because this script never
      # invents a price or a second product document.
      $match = @($candidates | Where-Object { $_.Kind -eq 'Specialty Coffee' })
    } else {
      $unmatched += "$name (ambiguous)"
      continue
    }
  }

  $row = $match[0]
  [void]$usedRows.Add([int]$row._sort)
  $changed++
  if ($WhatIf) {
    Write-Output "Would update: $name -> $($row.'Main Category') / $($row.Kind), ₱$($row.Grande)/₱$($row.Venti)"
    continue
  }

  $fields = Get-MenuFields $row $true
  $fields.Remove('imageBase64')  # keep existing drink photos; only repair the name
  Update-Fields $doc.name $fields $headers
  Write-Output "Updated: $name -> $($row.'Main Category') / $($row.Kind)"
}

$created = 0
foreach ($row in $rows) {
  if ($usedRows.Contains([int]$row._sort)) { continue }
  $created++
  if ($WhatIf) {
    Write-Output "Would create: $($row.'Product Name') -> $($row.'Main Category') / $($row.Kind), ₱$($row.Grande)/₱$($row.Venti)"
    continue
  }
  New-Document "projects/$projectId/databases/(default)/documents/shops/$shopId/menu" (Get-MenuFields $row $true) $headers
  Write-Output "Created: $($row.'Product Name') -> $($row.'Main Category') / $($row.Kind)"
}

Write-Output "Drip & Co menu records updated: $changed. New records: $created."
if ($unmatched.Count -gt 0) { Write-Warning "Left unchanged: $($unmatched -join ', ')" }
