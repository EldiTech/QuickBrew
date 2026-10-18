$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$csvPath = Join-Path $PSScriptRoot '..\assets\menu\seven_coffee_and_tea.csv'
$outputDir = Join-Path $PSScriptRoot '..\assets\menu\seven_redesigned'
New-Item -ItemType Directory -Force -Path $outputDir | Out-Null

$peso = [char]0x20B1
$rows = @(
  Get-Content -LiteralPath $csvPath |
    Select-Object -Skip 3 |
    ConvertFrom-Csv |
    Where-Object { $_.'Menu Board' -match '^Board' }
)

$pages = @(
  @{ File = 'seven_menu_1_iced_coffee.png'; Title = 'Iced Coffee'; Categories = @('Iced Coffee') },
  @{ File = 'seven_menu_2_non_coffee.png'; Title = 'Iced Non-Coffee'; Categories = @('Iced Non-Coffee') },
  @{ File = 'seven_menu_3_hot_and_salty.png'; Title = 'Hot & Salty'; Categories = @('Hot Beverages', 'Salty Cream Series') },
  @{ File = 'seven_menu_4_iced_blended.png'; Title = 'Iced Blended'; Categories = @('Iced Blended') },
  @{ File = 'seven_menu_5_milktea.png'; Title = 'Milktea'; Categories = @('Milktea') },
  @{ File = 'seven_menu_6_refreshers.png'; Title = 'Refreshers'; Categories = @('Refresher') },
  @{ File = 'seven_menu_7_lemonade.png'; Title = 'Fresh Lemonade'; Categories = @('Fresh Lemonade') }
)

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
  [System.Drawing.RectangleF] $bounds
) {
  foreach ($size in @(31, 29, 27, 25, 23, 21, 19, 17)) {
    $font = New-Font $size
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

function Draw-Section(
  [System.Drawing.Graphics] $graphics,
  [System.Drawing.RectangleF] $bounds,
  [string] $category,
  [object[]] $items,
  [System.Drawing.Brush] $cream,
  [System.Drawing.Brush] $muted,
  [System.Drawing.Brush] $orange,
  [System.Drawing.Pen] $border
) {
  $panel = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(238, 13, 48, 38))
  try {
    $graphics.FillRectangle($panel, $bounds)
    $graphics.DrawRectangle($border, $bounds.X, $bounds.Y, $bounds.Width, $bounds.Height)
    $heading = New-Font 42 ([System.Drawing.FontStyle]::Bold)
    $caption = New-Font 18 ([System.Drawing.FontStyle]::Bold)
    $subFont = New-Font 26 ([System.Drawing.FontStyle]::Bold)
    $priceFont = New-Font 31 ([System.Drawing.FontStyle]::Bold)
    try {
      Write-Text $graphics $category.ToUpperInvariant() $heading $orange ([System.Drawing.RectangleF]::new($bounds.X + 28, $bounds.Y + 24, $bounds.Width - 56, 52))
      Write-Text $graphics 'SIZE / PRICE' $caption $muted ([System.Drawing.RectangleF]::new($bounds.X + 28, $bounds.Y + 78, $bounds.Width - 56, 24))
      $linePen = [System.Drawing.Pen]::new([System.Drawing.Color]::FromArgb(80, 229, 222, 198), 1)
      try { $graphics.DrawLine($linePen, $bounds.X + 28, $bounds.Y + 112, $bounds.Right - 28, $bounds.Y + 112) } finally { $linePen.Dispose() }

      $groups = @($items | Group-Object 'Sub-Category')
      $y = $bounds.Y + 132
      $availableHeight = $bounds.Bottom - $y - 20
      $lineCount = $groups.Count
      foreach ($group in $groups) {
        $lineCount += [math]::Ceiling($group.Count / 2.0)
      }
      $rowHeight = [math]::Max(44, [math]::Min(84, [math]::Floor($availableHeight / [math]::Max(1, $lineCount))))
      $columnWidth = ($bounds.Width - 68) / 2
      foreach ($group in $groups) {
        $sub = if ([string]::IsNullOrWhiteSpace($group.Name)) { 'MENU' } else { $group.Name }
        Write-Text $graphics $sub.ToUpperInvariant() $subFont $cream ([System.Drawing.RectangleF]::new($bounds.X + 28, $y, $bounds.Width - 56, $rowHeight))
        $y += $rowHeight
        $groupRows = [math]::Ceiling($group.Count / 2.0)
        for ($row = 0; $row -lt $groupRows; $row++) {
          for ($column = 0; $column -lt 2; $column++) {
            $index = $row + $column * $groupRows
            if ($index -ge $group.Count) { continue }
            $item = $group.Group[$index]
            $x = $bounds.X + 28 + $column * $columnWidth
            $priceWidth = 68
            $priceGap = 12
            $nameWidth = $columnWidth - ($priceWidth * 2) - $priceGap
            Write-ItemText $graphics $item.'Item / Flavor' $cream ([System.Drawing.RectangleF]::new($x, $y, $nameWidth, $rowHeight))
            Write-Text $graphics (Price $item.'Medium (PHP)') $priceFont $orange ([System.Drawing.RectangleF]::new($x + $nameWidth, $y, $priceWidth, $rowHeight)) ([System.Drawing.StringAlignment]::Far)
            Write-Text $graphics (Price $item.'Large (PHP)') $priceFont $orange ([System.Drawing.RectangleF]::new($x + $nameWidth + $priceWidth + $priceGap, $y, $priceWidth, $rowHeight)) ([System.Drawing.StringAlignment]::Far)
          }
          $y += $rowHeight
        }
        $y += [math]::Max(12, $rowHeight * 0.35)
      }
    } finally {
      $heading.Dispose(); $caption.Dispose(); $subFont.Dispose(); $priceFont.Dispose()
    }
  } finally {
    $panel.Dispose()
  }
}

foreach ($page in $pages) {
  $pageRows = @($rows | Where-Object { $_.Category -in $page.Categories })
  if ($pageRows.Count -eq 0) { throw "No menu rows found for $($page.Title)." }

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
    $orange = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(255, 235, 132, 55))
    $border = [System.Drawing.Pen]::new([System.Drawing.Color]::FromArgb(230, 235, 132, 55), 3)
    try {
      $brand = New-Font 25 ([System.Drawing.FontStyle]::Bold)
      $title = New-Font 72 ([System.Drawing.FontStyle]::Bold)
      $intro = New-Font 22
      try {
        Write-Text $graphics 'SEVEN COFFEE & TEA' $brand $cream ([System.Drawing.RectangleF]::new(56, 58, 968, 42))
        Write-Text $graphics $page.Title.ToUpperInvariant() $title $orange ([System.Drawing.RectangleF]::new(56, 108, 968, 92))
        Write-Text $graphics 'MENU BOARD  |  PRICES IN PHP  |  M = MEDIUM  -  L = LARGE' $intro $muted ([System.Drawing.RectangleF]::new(58, 210, 964, 36))
      } finally { $brand.Dispose(); $title.Dispose(); $intro.Dispose() }

      $groups = @()
      foreach ($category in $page.Categories) {
        $groups += ,@($pageRows | Where-Object Category -eq $category)
      }
      $totalWeight = [double](($groups | ForEach-Object { $_.Count + 3 }) | Measure-Object -Sum).Sum
      $y = 282.0
      $available = 1560.0
      for ($i = 0; $i -lt $page.Categories.Count; $i++) {
        $weight = $groups[$i].Count + 3
        $height = if ($i -eq $page.Categories.Count - 1) { 1842 - $y } else { [math]::Floor($available * $weight / $totalWeight) - 18 }
        Draw-Section $graphics ([System.Drawing.RectangleF]::new(48, $y, 984, $height)) $page.Categories[$i] $groups[$i] $cream $muted $orange $border
        $y += $height + 18
        $available -= $height + 18
        $totalWeight -= $weight
      }
      $footer = New-Font 18 ([System.Drawing.FontStyle]::Bold)
      try {
        Write-Text $graphics 'QUICKBREW  -  ASK STAFF ABOUT AVAILABLE ADD-ONS' $footer $muted ([System.Drawing.RectangleF]::new(56, 1858, 968, 28)) ([System.Drawing.StringAlignment]::Center)
      } finally { $footer.Dispose() }
    } finally { $cream.Dispose(); $muted.Dispose(); $orange.Dispose(); $border.Dispose() }
  } finally {
    $graphics.Dispose()
  }
  try {
    $bitmap.Save((Join-Path $outputDir $page.File), [System.Drawing.Imaging.ImageFormat]::Png)
  } finally {
    $bitmap.Dispose()
  }
  Write-Output "Generated $($page.File) ($($pageRows.Count) menu items)."
}
