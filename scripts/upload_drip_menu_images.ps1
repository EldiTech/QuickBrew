param(
  [Parameter(Mandatory = $true)] [string] $Email,
  [Parameter(ValueFromPipeline = $true)] [string] $PasswordInput,
  [string] $ImageRoot = (Join-Path $PSScriptRoot '..\DRIP AND CO'),
  [switch] $WhatIf,
  [switch] $VerifyOnly
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$projectId = 'quick-brew-64673'
$apiKey = 'AIzaSyDlxmUqWTadFACJvQEkZmwGpxz__3pnjkk'
$shopId = 'coffee-shop-a'
$maxBase64Chars = 700 * 1024

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
  $normalized = $value.Normalize([Text.NormalizationForm]::FormD)
  ([Regex]::Replace($normalized, '[^\p{L}\p{Nd}]', '')).ToLowerInvariant()
}

function Get-AllDocuments([string] $baseUri, [hashtable] $headers) {
  $documents = @()
  $nextPageToken = $null
  do {
    $pageUri = if ($nextPageToken) {
      "${baseUri}?pageToken=$([uri]::EscapeDataString($nextPageToken))"
    } else {
      $baseUri
    }
    $page = Invoke-RestMethod -Headers $headers -Uri $pageUri
    $documents += @($page.documents)
    $nextPageToken = $page.nextPageToken
  } while ($nextPageToken)
  $documents
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
      try {
        $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $graphics.DrawImage($source, 0, 0, $width, $height)
      } finally {
        $graphics.Dispose()
      }
      try {
        foreach ($quality in @(82, 72, 62, 52, 42)) {
          $stream = [System.IO.MemoryStream]::new()
          $parameters = [System.Drawing.Imaging.EncoderParameters]::new(1)
          try {
            $encoder = [System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() |
              Where-Object { $_.MimeType -eq 'image/jpeg' }
            $parameters.Param[0] = [System.Drawing.Imaging.EncoderParameter]::new(
              [System.Drawing.Imaging.Encoder]::Quality, [int64]$quality)
            $bitmap.Save($stream, $encoder, $parameters)
            $encoded = [Convert]::ToBase64String($stream.ToArray())
            if ($encoded.Length -le $maxBase64Chars) { return $encoded }
          } finally {
            $stream.Dispose()
            $parameters.Dispose()
          }
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

if (-not (Test-Path -LiteralPath $ImageRoot -PathType Container)) {
  throw "Image folder not found: $ImageRoot"
}

$token = Get-IdToken
$headers = @{ Authorization = "Bearer $token" }
$baseUri = "https://firestore.googleapis.com/v1/projects/$projectId/databases/(default)/documents/shops/$shopId/menu"
$documents = @(Get-AllDocuments $baseUri $headers)
$itemsByName = @{}
foreach ($document in $documents) {
  $name = $document.fields.name.stringValue
  if ([string]::IsNullOrWhiteSpace($name)) { continue }
  $key = Normalize-Name $name
  if (-not $itemsByName.ContainsKey($key)) { $itemsByName[$key] = @() }
  $itemsByName[$key] += $document
}

function Resolve-ImageLookup([string] $baseName) {
  $lookup = Normalize-Name $baseName
  if ($lookup -eq 'swissmisschocolatemilk') {
    return 'swissmiss'
  }
  if ($lookup -eq 'oreacocoa') {
    return 'oreococoa'
  }
  # All photographed "Iced ..." drinks omit that prefix in the menu except
  # the product whose actual menu name is "Iced Latte".
  if ($lookup.StartsWith('iced') -and $lookup -ne 'icedlatte') {
    $lookup = $lookup.Substring(4)
  }
  # The photo filename includes this explanatory English alias; Firestore does not.
  if ($lookup.EndsWith('spanishlatte')) {
    $lookup = $lookup.Substring(0, $lookup.Length - 'spanishlatte'.Length)
  }
  $lookup
}

$images = @(
  Get-ChildItem -LiteralPath $ImageRoot -Recurse -File |
    Where-Object { $_.Extension -in @('.jpg', '.jpeg', '.png') } |
    Sort-Object FullName -Unique
)
if ($images.Count -eq 0) { throw "No JPG or PNG images found in '$ImageRoot'." }

$matches = @()
$missing = @()
foreach ($image in $images) {
  $lookup = Resolve-ImageLookup $image.BaseName
  if (-not $itemsByName.ContainsKey($lookup)) {
    $missing += $image.Name
    continue
  }
  $matches += [PSCustomObject]@{ Image = $image; Documents = @($itemsByName[$lookup]) }
}

if ($missing.Count -gt 0) {
  throw "These images do not match a Drip & Co menu item: $($missing -join ', ')"
}

$targetCount = ($matches | ForEach-Object { $_.Documents.Count } | Measure-Object -Sum).Sum
Write-Output "Matched $($matches.Count) image files to $targetCount Drip & Co menu entries."
foreach ($match in $matches) {
  $names = @($match.Documents | ForEach-Object { $_.fields.name.stringValue }) -join ', '
  Write-Output "  $($match.Image.Name) -> $names"
}

if ($VerifyOnly) {
  $withImages = @($matches | ForEach-Object {
    $_.Documents | Where-Object { -not [string]::IsNullOrWhiteSpace($_.fields.imageBase64.stringValue) }
  })
  Write-Output "$($withImages.Count) of $targetCount matched menu entries currently have an uploaded image."
  exit 0
}

if ($WhatIf) {
  Write-Output "No changes made (-WhatIf)."
  exit 0
}

$uploaded = 0
foreach ($match in $matches) {
  $encoded = Convert-ToFirestoreJpegBase64 $match.Image.FullName
  $payload = @{ fields = @{ imageBase64 = @{ stringValue = $encoded } } } |
    ConvertTo-Json -Depth 6 -Compress
  foreach ($document in $match.Documents) {
    $targetUri = "https://firestore.googleapis.com/v1/$($document.name)?updateMask.fieldPaths=imageBase64"
    Invoke-RestMethod -Method Patch -Headers $headers -ContentType 'application/json' -Uri $targetUri -Body $payload | Out-Null
    $uploaded++
  }
  Write-Output "Uploaded $($match.Image.Name) to $($match.Documents.Count) menu entry/entries ($($encoded.Length) Base64 chars)."
}

$verifiedDocuments = @(Get-AllDocuments $baseUri $headers)
$verifiedByName = @{}
foreach ($document in $verifiedDocuments) {
  $name = $document.fields.name.stringValue
  if (-not [string]::IsNullOrWhiteSpace($name)) {
    $key = Normalize-Name $name
    if (-not $verifiedByName.ContainsKey($key)) { $verifiedByName[$key] = @() }
    $verifiedByName[$key] += $document
  }
}
$verified = 0
foreach ($match in $matches) {
  $lookup = Resolve-ImageLookup $match.Image.BaseName
  $verified += @($verifiedByName[$lookup] | Where-Object {
    -not [string]::IsNullOrWhiteSpace($_.fields.imageBase64.stringValue)
  }).Count
}

if ($verified -ne $targetCount) {
  throw "Upload completed, but verification found images on only $verified of $targetCount target entries."
}
Write-Output "Verified $verified of $targetCount Drip & Co menu images in Firestore."
