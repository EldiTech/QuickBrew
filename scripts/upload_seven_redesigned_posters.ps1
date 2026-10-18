param(
  [Parameter(Mandatory = $true)] [string] $Email,
  [Parameter(ValueFromPipeline = $true)] [string] $PasswordInput,
  [switch] $WhatIf
)

$ErrorActionPreference = 'Stop'
$projectId = 'quick-brew-64673'
$apiKey = 'AIzaSyDlxmUqWTadFACJvQEkZmwGpxz__3pnjkk'
$shopId = 'coffee-shop-b'
$imageRoot = Join-Path $PSScriptRoot '..\assets\menu\seven_redesigned'

$boards = @(
  @{ Id = 'seven_menu_1_iced_coffee'; File = 'seven_menu_1_iced_coffee.png'; Title = 'Iced Coffee'; Description = 'Classic and special coffee'; Sort = 1 },
  @{ Id = 'seven_menu_2_non_coffee'; File = 'seven_menu_2_non_coffee.png'; Title = 'Iced Non-Coffee'; Description = 'Classic and special non-coffee drinks'; Sort = 2 },
  @{ Id = 'seven_menu_3_hot_and_salty'; File = 'seven_menu_3_hot_and_salty.png'; Title = 'Hot and Salty'; Description = 'Hot beverages and salty cream series'; Sort = 3 },
  @{ Id = 'seven_menu_4_iced_blended'; File = 'seven_menu_4_iced_blended.png'; Title = 'Iced Blended'; Description = 'Frappe series'; Sort = 4 },
  @{ Id = 'seven_menu_5_milktea'; File = 'seven_menu_5_milktea.png'; Title = 'Milktea'; Description = 'Classic, cream cheese, and cheesecake milktea'; Sort = 5 },
  @{ Id = 'seven_menu_6_refreshers'; File = 'seven_menu_6_refreshers.png'; Title = 'Refreshers'; Description = 'Fruit tea, Yakult, and soda'; Sort = 6 },
  @{ Id = 'seven_menu_7_lemonade'; File = 'seven_menu_7_lemonade.png'; Title = 'Fresh Lemonade'; Description = 'Fresh lemonade drinks'; Sort = 7 }
)

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

function Get-AllDocuments([string] $baseUri, [hashtable] $headers) {
  $documents = @()
  $nextPageToken = $null
  do {
    $uri = if ($nextPageToken) {
      "${baseUri}?pageToken=$([uri]::EscapeDataString($nextPageToken))"
    } else {
      $baseUri
    }
    $page = Invoke-RestMethod -Headers $headers -Uri $uri
    $documents += @($page.documents)
    $nextPageToken = $page.nextPageToken
  } while ($nextPageToken)
  $documents
}

foreach ($board in $boards) {
  $path = Join-Path $imageRoot $board.File
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
    throw "Poster file not found: $path"
  }
}

$token = Get-IdToken
$headers = @{ Authorization = "Bearer $token" }
$baseUri = "https://firestore.googleapis.com/v1/projects/$projectId/databases/(default)/documents/shops/$shopId/whole_menu"
$existing = @(Get-AllDocuments $baseUri $headers)
$newIds = @($boards | ForEach-Object Id)

Write-Output "Seven Coffee poster replacement: $($existing.Count) current board(s) -> $($boards.Count) portrait board(s)."
foreach ($board in $boards) {
  Write-Output "  $($board.Sort). $($board.Title)"
}

if ($WhatIf) {
  Write-Output 'No changes made (-WhatIf).'
  exit 0
}

foreach ($board in $boards) {
  $path = Join-Path $imageRoot $board.File
  $encoded = [Convert]::ToBase64String([IO.File]::ReadAllBytes($path))
  $fields = @{
    title = @{ stringValue = $board.Title }
    description = @{ stringValue = $board.Description }
    sort = @{ integerValue = "$($board.Sort)" }
    aspectRatio = @{ doubleValue = 0.5625 }
    imageBase64 = @{ stringValue = $encoded }
  }
  $payload = @{ fields = $fields } | ConvertTo-Json -Depth 7 -Compress
  $uri = "$baseUri/$($board.Id)"
  Invoke-RestMethod -Method Patch -Headers $headers -ContentType 'application/json' -Uri $uri -Body $payload | Out-Null
  Write-Output "Uploaded $($board.Title)."
}

foreach ($document in $existing) {
  $id = ($document.name -split '/')[-1]
  if ($id -in $newIds) { continue }
  $uri = "https://firestore.googleapis.com/v1/$($document.name)"
  Invoke-RestMethod -Method Delete -Headers $headers -Uri $uri | Out-Null
  Write-Output "Removed replaced board $id."
}

$verified = @(Get-AllDocuments $baseUri $headers)
$verifiedIds = @($verified | ForEach-Object { ($_.name -split '/')[-1] })
if ($verified.Count -ne $boards.Count -or @($newIds | Where-Object { $_ -notin $verifiedIds }).Count -ne 0) {
  throw "Poster upload did not verify: expected exactly $($boards.Count) redesigned board documents."
}
foreach ($document in $verified) {
  if ([string]::IsNullOrWhiteSpace($document.fields.imageBase64.stringValue)) {
    throw "Poster $($document.name) has no image."
  }
}
Write-Output "Verified $($verified.Count) redesigned Seven Coffee poster boards in Firestore."
