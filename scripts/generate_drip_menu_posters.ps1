$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

# Renders Drip & Co's whole-menu posters from assets/menu/drip_co.csv, the same
# way generate_seven_menu_posters.ps1 does for Seven. Keep this file ASCII:
# Windows PowerShell 5.1 reads a BOM-less script as ANSI, so the Vietnamese
# category name is built from code points instead of being typed.

$csvPath = Join-Path $PSScriptRoot '..\assets\menu\drip_co.csv'
$outputDir = Join-Path $PSScriptRoot '..\assets\menu\drip_redesigned'
New-Item -ItemType Directory -Force -Path $outputDir | Out-Null

$peso = [char]0x20B1
$caPhe = "C$([char]0xE0) Ph$([char]0xEA) Series"
$form = [System.Text.NormalizationForm]::FormC

$rows = @(
  Get-Content -LiteralPath $csvPath -Encoding UTF8 |
    Select-Object -Skip 3 |
    ConvertFrom-Csv |
    Where-Object { $_.'Menu Board' -match '^Board' }
)
foreach ($row in $rows) {
  # The sheet may hold a letter as one code point or as base + accent; make
  # them one shape so the category filters below match either.
  foreach ($name in @('Category', 'Sub-Category', 'Item / Flavor')) {
    $row.$name = $row.$name.Normalize($form).Trim()
  }
}

# One poster per page; a page is a stack of panels. A panel with no Sub list
# takes every sub-category of its category.
$pages = @(
  @{
    File = 'drip_menu_1_specials.png'; Title = 'Special Coffees'
    Panels = @(
      @{ Heading = 'Hello Vietnam'; Category = 'Hello Vietnam' },
      @{ Heading = 'Tiramisu'; Category = 'Tiramisu' },
      @{ Heading = 'Specialty Coffee'; Category = $caPhe; Sub = @('Specialty Coffee') }
    )
  },
  @{
    File = 'drip_menu_2_ca_phe_series.png'; Title = $caPhe
    Panels = @(
      @{ Heading = $caPhe; Category = $caPhe; Sub = @('Classic Coffee', 'Premium Coffee') }
    )
  },
  @{
    File = 'drip_menu_3_premium_coffee.png'; Title = 'Premium Coffee'
    Panels = @(
      @{ Heading = 'Premium Coffee'; Category = 'Premium' }
    )
  },
  @{
    File = 'drip_menu_4_milky_series.png'; Title = 'Milky Series'
    Panels = @(
      @{ Heading = 'Milky Series'; Category = 'Milky Series' }
    )
  }
)

$panelHeader = 132   # heading, column captions, rule
$panelFooter = 28
$stackTop = 282.0
$stackHeight = 1560.0
$panelGap = 18.0

function New-Font([float] $size, [System.Drawing.FontStyle] $style = [System.Drawing.FontStyle]::Regular) {
  [System.Drawing.Font]::new('Arial', $size, $style, [System.Drawing.GraphicsUnit]::Pixel)
}

function Write-Text(
  [System.Drawing.Graphics] $graphics,
  [string] $text,
  [System.Drawing.Font] $font,
  [System.Drawing.Brush] $brush,
  [System.Drawing.RectangleF] $bounds,
  [System.Drawing.StringAlignment] $alignment = [System.Drawing.StringAlignment]::Near
) {
  $format = [System.Drawing.StringFormat]::new()
  try {
    $format.Alignment = $alignment
    $format.LineAlignment = [System.Drawing.StringAlignment]::Center
    $format.Trimming = [System.Drawing.StringTrimming]::EllipsisCharacter
    $format.FormatFlags = [System.Drawing.StringFormatFlags]::NoWrap
    $graphics.DrawString($text, $font, $brush, $bounds, $format)
  } finally {
    $format.Dispose()
  }
}

function Price([string] $value) {
  $raw = if ($null -eq $value) { '' } else { $value }
  $digits = [regex]::Replace($raw, '[^0-9.]', '')
  if ([string]::IsNullOrWhiteSpace($digits)) { return '-' }
  "$peso$digits"
}

function Write-ItemText(
  [System.Drawing.Graphics] $graphics,
  [string] $text,
  [System.Drawing.Brush] $brush,
  [System.Drawing.RectangleF] $bounds,
  [double] $scale
) {
  foreach ($size in @(31, 29, 27, 25, 23, 21, 19, 17)) {
    $font = New-Font ([float]($size * $scale))
    try {
      if ($graphics.MeasureString($text, $font).Width -le $bounds.Width) {
        Write-Text $graphics $text $font $brush $bounds
        return
      }
    } finally {
      $font.Dispose()
    }
  }
  $fallback = New-Font 16
  try { Write-Text $graphics $text $fallback $brush $bounds } finally { $fallback.Dispose() }
}

# A group's own title line is only worth a row when it says something the panel
# heading does not already say.
function Show-GroupTitle([string] $groupName, [string] $heading) {
  -not [string]::IsNullOrWhiteSpace($groupName) -and
    ($groupName.Trim() -ne $heading.Trim())
}

function Get-PanelHeight([object[]] $groups, [string] $heading, [int] $columns, [double] $rowHeight) {
  $lines = 0
  foreach ($group in $groups) {
    if (Show-GroupTitle $group.Name $heading) { $lines++ }
    $lines += [math]::Ceiling($group.Count / [double]$columns)
  }
  $gaps = [math]::Max(0, $groups.Count - 1) * [math]::Max(12, $rowHeight * 0.35)
  $panelHeader + $lines * $rowHeight + $gaps + $panelFooter
}

function Draw-Panel(
  [System.Drawing.Graphics] $graphics,
  [System.Drawing.RectangleF] $bounds,
  [string] $heading,
  [object[]] $groups,
  [int] $columns,
  [double] $rowHeight,
  [double] $scale,
  [System.Drawing.Brush] $cream,
  [System.Drawing.Brush] $muted,
  [System.Drawing.Brush] $accent,
  [System.Drawing.Pen] $border
) {
  $panel = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(238, 13, 48, 38))
  try {
    $graphics.FillRectangle($panel, $bounds)
    $graphics.DrawRectangle($border, $bounds.X, $bounds.Y, $bounds.Width, $bounds.Height)

    $headingFont = New-Font 42 ([System.Drawing.FontStyle]::Bold)
    $caption = New-Font 16 ([System.Drawing.FontStyle]::Bold)
    $subFont = New-Font ([float](26 * $scale)) ([System.Drawing.FontStyle]::Bold)
    $priceFont = New-Font ([float](31 * $scale)) ([System.Drawing.FontStyle]::Bold)
    try {
      Write-Text $graphics $heading.ToUpperInvariant() $headingFont $accent ([System.Drawing.RectangleF]::new($bounds.X + 28, $bounds.Y + 24, $bounds.Width - 56, 52))

      $columnGap = 24
      $columnWidth = ($bounds.Width - 56 - ($columnGap * ($columns - 1))) / $columns
      $priceWidth = [math]::Round(76 * $scale)
      $priceGap = 12
      $nameWidth = $columnWidth - ($priceWidth * 2) - $priceGap

      # Both sizes are named once per column, over the prices they head.
      for ($column = 0; $column -lt $columns; $column++) {
        $x = $bounds.X + 28 + $column * ($columnWidth + $columnGap)
        Write-Text $graphics 'GRANDE' $caption $muted ([System.Drawing.RectangleF]::new($x + $nameWidth - 12, $bounds.Y + 80, $priceWidth + 12, 24)) ([System.Drawing.StringAlignment]::Far)
        Write-Text $graphics 'VENTI' $caption $muted ([System.Drawing.RectangleF]::new($x + $nameWidth + $priceWidth + $priceGap, $bounds.Y + 80, $priceWidth, 24)) ([System.Drawing.StringAlignment]::Far)
      }
      $linePen = [System.Drawing.Pen]::new([System.Drawing.Color]::FromArgb(80, 229, 222, 198), 1)
      try { $graphics.DrawLine($linePen, $bounds.X + 28, $bounds.Y + 112, $bounds.Right - 28, $bounds.Y + 112) } finally { $linePen.Dispose() }

      $y = $bounds.Y + $panelHeader
      $groupIndex = 0
      foreach ($group in $groups) {
        if (Show-GroupTitle $group.Name $heading) {
          Write-Text $graphics $group.Name.ToUpperInvariant() $subFont $cream ([System.Drawing.RectangleF]::new($bounds.X + 28, $y, $bounds.Width - 56, $rowHeight))
          $y += $rowHeight
        }
        $groupRows = [math]::Ceiling($group.Count / [double]$columns)
        for ($row = 0; $row -lt $groupRows; $row++) {
          for ($column = 0; $column -lt $columns; $column++) {
            $index = $row + $column * $groupRows
            if ($index -ge $group.Count) { continue }
            $item = $group.Group[$index]
            $x = $bounds.X + 28 + $column * ($columnWidth + $columnGap)
            Write-ItemText $graphics $item.'Item / Flavor' $cream ([System.Drawing.RectangleF]::new($x, $y, $nameWidth, $rowHeight)) $scale
            Write-Text $graphics (Price $item.'Medium (PHP)') $priceFont $accent ([System.Drawing.RectangleF]::new($x + $nameWidth, $y, $priceWidth, $rowHeight)) ([System.Drawing.StringAlignment]::Far)
            Write-Text $graphics (Price $item.'Large (PHP)') $priceFont $accent ([System.Drawing.RectangleF]::new($x + $nameWidth + $priceWidth + $priceGap, $y, $priceWidth, $rowHeight)) ([System.Drawing.StringAlignment]::Far)
          }
          $y += $rowHeight
        }
        $groupIndex++
        if ($groupIndex -lt $groups.Count) { $y += [math]::Max(12, $rowHeight * 0.35) }
      }
    } finally {
      $headingFont.Dispose(); $caption.Dispose(); $subFont.Dispose(); $priceFont.Dispose()
    }
  } finally {
    $panel.Dispose()
  }
}

foreach ($page in $pages) {
  # Resolve each panel's rows, in sheet order, grouped by sub-category.
  $panels = @()
  $itemCount = 0
  foreach ($spec in $page.Panels) {
    $panelRows = @($rows | Where-Object {
      $_.Category -eq $spec.Category -and
      ($null -eq $spec.Sub -or $_.'Sub-Category' -in $spec.Sub)
    })
    if ($panelRows.Count -eq 0) { throw "No menu rows found for $($spec.Heading)." }
    $itemCount += $panelRows.Count
    $panels += ,@{
      Heading = $spec.Heading
      Groups = @($panelRows | Group-Object 'Sub-Category')
    }
  }

  # One column throughout. Two columns left a 12-item page as a small panel
  # floating in empty space, and squeezed names like "Salty Cream Americano"
  # down to a smaller size than their neighbours. The largest page still fits
  # one column at a phone-readable size.
  $columns = 1
  $maxScale = 1.3

  # Largest row height at which every panel still fits the page.
  $available = $stackHeight - $panelGap * ($panels.Count - 1)
  $rowHeight = 48.0
  for ($candidate = 104.0; $candidate -ge 48.0; $candidate -= 2.0) {
    $total = 0.0
    foreach ($panel in $panels) { $total += Get-PanelHeight $panel.Groups $panel.Heading $columns $candidate }
    if ($total -le $available) { $rowHeight = $candidate; break }
  }
  $scale = [math]::Min($maxScale, [math]::Max(0.85, $rowHeight / 84.0))

  $heights = @()
  $total = 0.0
  foreach ($panel in $panels) {
    $h = Get-PanelHeight $panel.Groups $panel.Heading $columns $rowHeight
    $heights += $h
    $total += $h
  }
  $total += $panelGap * ($panels.Count - 1)
  # Whatever the page does not need is split above and below the stack.
  $y = $stackTop + [math]::Max(0, ($stackHeight - $total) / 2)

  $bitmap = [System.Drawing.Bitmap]::new(1080, 1920)
  $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
  try {
    $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $graphics.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit
    $graphics.Clear([System.Drawing.Color]::FromArgb(6, 27, 21))
    $glow = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(45, 90, 138, 94))
    try {
      $graphics.FillEllipse($glow, -220, -160, 760, 760)
      $graphics.FillEllipse($glow, 720, 1420, 480, 480)
    } finally { $glow.Dispose() }

    $cream = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(240, 238, 229, 205))
    $muted = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(190, 184, 202, 170))
    $accent = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(255, 222, 164, 104))
    $border = [System.Drawing.Pen]::new([System.Drawing.Color]::FromArgb(230, 222, 164, 104), 3)
    try {
      $brand = New-Font 25 ([System.Drawing.FontStyle]::Bold)
      $titleFont = New-Font 72 ([System.Drawing.FontStyle]::Bold)
      $intro = New-Font 22
      try {
        Write-Text $graphics 'DRIP & CO.' $brand $cream ([System.Drawing.RectangleF]::new(56, 58, 968, 42))
        Write-Text $graphics $page.Title.ToUpperInvariant() $titleFont $accent ([System.Drawing.RectangleF]::new(56, 108, 968, 92))
        Write-Text $graphics 'MENU BOARD  |  PRICES IN PHP  |  GRANDE  -  VENTI' $intro $muted ([System.Drawing.RectangleF]::new(58, 210, 964, 36))
      } finally { $brand.Dispose(); $titleFont.Dispose(); $intro.Dispose() }

      for ($i = 0; $i -lt $panels.Count; $i++) {
        Draw-Panel $graphics ([System.Drawing.RectangleF]::new(48, $y, 984, $heights[$i])) $panels[$i].Heading $panels[$i].Groups $columns $rowHeight $scale $cream $muted $accent $border
        $y += $heights[$i] + $panelGap
      }

      $footer = New-Font 18 ([System.Drawing.FontStyle]::Bold)
      try {
        Write-Text $graphics 'QUICKBREW  -  ASK STAFF ABOUT AVAILABLE ADD-ONS' $footer $muted ([System.Drawing.RectangleF]::new(56, 1858, 968, 28)) ([System.Drawing.StringAlignment]::Center)
      } finally { $footer.Dispose() }
    } finally { $cream.Dispose(); $muted.Dispose(); $accent.Dispose(); $border.Dispose() }
  } finally {
    $graphics.Dispose()
  }
  try {
    $bitmap.Save((Join-Path $outputDir $page.File), [System.Drawing.Imaging.ImageFormat]::Png)
  } finally {
    $bitmap.Dispose()
  }
  Write-Output "Generated $($page.File) ($itemCount menu items, $columns column(s), row $rowHeight)."
}
