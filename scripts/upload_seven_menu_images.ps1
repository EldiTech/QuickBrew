param(
  [Parameter(Mandatory = $true)] [string] $Email,
  [Parameter(Mandatory = $true)] [string] $Password,
  [string] $ImageRoot = (Join-Path $PSScriptRoot '..\7 COFFEE MENU PICTURES'),
  [string] $Category,
  [string] $RestrictToCategory,
  [switch] $WhatIf
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$projectId = 'quick-brew-64673'
$apiKey = 'AIzaSyDlxmUqWTadFACJvQEkZmwGpxz__3pnjkk'
$shopId = 'coffee-shop-b'
$maxBase64Chars = 700 * 1024

function Get-IdToken {
  $body = @{ email = $Email; password = $Password; returnSecureToken = $true } |
    ConvertTo-Json -Compress
  $auth = Invoke-RestMethod -Method Post -ContentType 'application/json' -Uri "https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=$apiKey" -Body $body
  return $auth.idToken
}

function Normalize-Name([string] $value) {
  $normalized = $value.Normalize([Text.NormalizationForm]::FormD)
  $normalized = [Regex]::Replace($normalized, '[^\p{L}\p{Nd}]', '')
  return $normalized.ToLowerInvariant()
}

function Convert-ToFirestoreJpegBase64([string] $path) {
  $source = [System.Drawing.Image]::FromFile($path)
  try {
    foreach ($edge in @(900, 800, 700, 600, 500, 420)) {
      $scale = [Math]::Min(1.0, $edge / [Math]::Max($source.Width, $source.Height))
      $width = [Math]::Max(1, [int]($source.Width * $scale))
      $height = [Math]::Max(1, [int]($source.Height * $scale))
      $bitmap = [System.Drawing.Bitmap]::new($width, $height)
      $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
      $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
      $graphics.DrawImage($source, 0, 0, $width, $height)
      $graphics.Dispose()
      try {
        foreach ($quality in @(82, 72, 62, 52, 42)) {
          $stream = [System.IO.MemoryStream]::new()
          $encoder = [System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() |
            Where-Object { $_.MimeType -eq 'image/jpeg' }
          $parameters = [System.Drawing.Imaging.EncoderParameters]::new(1)
          $parameters.Param[0] = [System.Drawing.Imaging.EncoderParameter]::new(
            [System.Drawing.Imaging.Encoder]::Quality, [int64]$quality)
          $bitmap.Save($stream, $encoder, $parameters)
          $encoded = [Convert]::ToBase64String($stream.ToArray())
          $stream.Dispose()
          $parameters.Dispose()
          if ($encoded.Length -le $maxBase64Chars) { return $encoded }
        }
      } finally {
        $bitmap.Dispose()
      }
    }
  } finally {
    $source.Dispose()
  }
  throw "Could not shrink '$path' below the Firestore image limit."
}

$token = Get-IdToken
$headers = @{ Authorization = "Bearer $token" }
$baseUri = "https://firestore.googleapis.com/v1/projects/$projectId/databases/(default)/documents/shops/$shopId/menu"
$itemsByName = @{}
$categoryByDocument = @{}
$nextPageToken = $null
do {
  $pageUri = if ($nextPageToken) {
    "${baseUri}?pageToken=$([uri]::EscapeDataString($nextPageToken))"
  } else {
    $baseUri
  }
  $menu = Invoke-RestMethod -Headers $headers -Uri $pageUri
  foreach ($document in @($menu.documents)) {
    $name = $document.fields.name.stringValue
    $categoryByDocument[$document.name] = $document.fields.category.stringValue
    if ($name) {
      $key = Normalize-Name $name
      if ($itemsByName.ContainsKey($key)) {
        $itemsByName[$key] += $document.name
      } else {
        $itemsByName[$key] = @($document.name)
      }
    }
  }
  $nextPageToken = $menu.nextPageToken
} while ($nextPageToken)

$aliases = @{
  (Normalize-Name 'DIRTY MACHA') = Normalize-Name 'Dirty Matcha'
  (Normalize-Name 'AVO LATTE') = Normalize-Name 'Avo Latte (Avocado)'
  (Normalize-Name 'COOKIES AND CREAM') = Normalize-Name 'Cookies & Cream'
  (Normalize-Name 'TAKO') = Normalize-Name 'Taro'
}
foreach ($alias in $aliases.Keys) {
  if ($itemsByName.ContainsKey($aliases[$alias])) {
    $itemsByName[$alias] = $itemsByName[$aliases[$alias]]
  }
}

$images = Get-ChildItem -LiteralPath $imageRoot -File -Recurse -Filter '*.jpg'
$images += Get-ChildItem -LiteralPath $imageRoot -File -Recurse -Filter '*.png'
$images = @($images | Sort-Object FullName -Unique)

if ($Category) {
  if ($images.Count -ne 1) {
    throw "Category uploads require exactly one image in '$ImageRoot'."
  }
  $targets = @(
    $categoryByDocument.Keys | Where-Object {
      $categoryByDocument[$_] -eq $Category
    }
  )
  if ($targets.Count -eq 0) { throw "No menu items found in category '$Category'." }
  $image = $images[0]
  if ($WhatIf) {
    Write-Output "Would upload $($image.Name) to $($targets.Count) '$Category' item(s)."
    exit 0
  }
  $encoded = Convert-ToFirestoreJpegBase64 $image.FullName
  $payload = @{ fields = @{ imageBase64 = @{ stringValue = $encoded } } } |
    ConvertTo-Json -Depth 6 -Compress
  foreach ($documentPath in $targets) {
    $targetUri = "https://firestore.googleapis.com/v1/${documentPath}?updateMask.fieldPaths=imageBase64"
    Invoke-RestMethod -Method Patch -Headers $headers -ContentType 'application/json' -Uri $targetUri -Body $payload | Out-Null
  }
  Write-Output "Uploaded $($image.Name) to $($targets.Count) '$Category' item(s)."
  exit 0
}

$missing = @()
$matched = 0
foreach ($image in $images) {
  $lookup = Normalize-Name $image.BaseName
  # Refresher filenames use "FLAVOR TYPE" while Firebase uses "TYPE - FLAVOR".
  if (-not $itemsByName.ContainsKey($lookup)) {
    if ($image.BaseName.ToUpperInvariant() -eq 'PASSION FRUIT TEA') {
      $passionFruitTea = Normalize-Name 'Fruit Tea - Passion Fruit'
      if ($itemsByName.ContainsKey($passionFruitTea)) {
        $lookup = $passionFruitTea
      }
    }
    foreach ($drinkType in @('FRUIT TEA', 'YAKULT', 'SODA')) {
      if ($image.BaseName.ToUpperInvariant().EndsWith(" $drinkType")) {
        $flavor = $image.BaseName.Substring(0, $image.BaseName.Length - $drinkType.Length).Trim()
        $reordered = Normalize-Name ("$drinkType - $flavor")
        if ($itemsByName.ContainsKey($reordered)) {
          $lookup = $reordered
          break
        }
      }
    }
  }
  if (-not $itemsByName.ContainsKey($lookup)) {
    $missing += $image.Name
    continue
  }
  $targetPaths = @($itemsByName[$lookup])
  if ($RestrictToCategory) {
    $targetPaths = @(
      $targetPaths | Where-Object {
        $categoryByDocument[$_] -eq $RestrictToCategory
      }
    )
    if ($targetPaths.Count -eq 0) {
      $missing += "$($image.Name) (not in $RestrictToCategory)"
      continue
    }
  }
  $matched++
  if ($WhatIf) {
    Write-Output "Would upload: $($image.Name) ($($targetPaths.Count) matching menu item(s))"
    continue
  }
  $encoded = Convert-ToFirestoreJpegBase64 $image.FullName
  $payload = @{ fields = @{ imageBase64 = @{ stringValue = $encoded } } } |
    ConvertTo-Json -Depth 6 -Compress
  foreach ($documentPath in $targetPaths) {
    $targetUri = "https://firestore.googleapis.com/v1/${documentPath}?updateMask.fieldPaths=imageBase64"
    Invoke-RestMethod -Method Patch -Headers $headers -ContentType 'application/json' -Uri $targetUri -Body $payload | Out-Null
  }
  Write-Output "Uploaded: $($image.Name) to $($targetPaths.Count) item(s) ($($encoded.Length) Base64 chars)"
}

Write-Output "Matched $matched of $($images.Count) image files."
if ($missing.Count -gt 0) {
  Write-Warning "No matching Firebase menu item: $($missing -join ', ')"
}
