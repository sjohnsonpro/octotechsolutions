$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$port = 8765
$prefix = "http://localhost:$port/"
$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add($prefix)
$listener.Start()
Write-Output "Serving $root at $prefix"

$types = @{
  '.html' = 'text/html; charset=utf-8'
  '.css'  = 'text/css; charset=utf-8'
  '.js'   = 'text/javascript; charset=utf-8'
  '.json' = 'application/json; charset=utf-8'
  '.png'  = 'image/png'
  '.jpg'  = 'image/jpeg'
  '.jpeg' = 'image/jpeg'
  '.gif'  = 'image/gif'
  '.webp' = 'image/webp'
  '.svg'  = 'image/svg+xml'
  '.ico'  = 'image/x-icon'
  '.woff' = 'font/woff'
  '.woff2'= 'font/woff2'
  '.ttf'  = 'font/ttf'
  '.eot'  = 'application/vnd.ms-fontobject'
  '.mp4'  = 'video/mp4'
  '.webm' = 'video/webm'
  '.pdf'  = 'application/pdf'
  '.xml'  = 'application/xml'
  '.txt'  = 'text/plain; charset=utf-8'
}

function Send-Bytes($ctx, $status, $type, $bytes) {
  $ctx.Response.StatusCode = $status
  if ($type) { $ctx.Response.ContentType = $type }
  if ($bytes) {
    $ctx.Response.ContentLength64 = $bytes.Length
    $ctx.Response.OutputStream.Write($bytes, 0, $bytes.Length)
  }
  $ctx.Response.Close()
}

while ($listener.IsListening) {
  $ctx = $listener.GetContext()
  try {
    $rel = [Uri]::UnescapeDataString($ctx.Request.Url.AbsolutePath)
    if ($rel.Contains('..')) { Send-Bytes $ctx 400 'text/plain' ([Text.Encoding]::UTF8.GetBytes('Bad path')); continue }
    $relPath = $rel.TrimStart('/').Replace('/', [IO.Path]::DirectorySeparatorChar)
    $full = [IO.Path]::GetFullPath((Join-Path $root $relPath))
    if (-not $full.StartsWith($root, [StringComparison]::OrdinalIgnoreCase)) {
      Send-Bytes $ctx 403 'text/plain' ([Text.Encoding]::UTF8.GetBytes('Forbidden'))
      continue
    }
    if ((Test-Path -LiteralPath $full) -and (Test-Path -LiteralPath $full -PathType Container)) {
      if (-not $rel.EndsWith('/')) {
        $ctx.Response.Redirect($rel + '/')
        $ctx.Response.Close()
        continue
      }
      $full = Join-Path $full 'index.html'
    }
    if (-not (Test-Path -LiteralPath $full -PathType Leaf)) {
      Send-Bytes $ctx 404 'text/plain; charset=utf-8' ([Text.Encoding]::UTF8.GetBytes('Not found'))
      continue
    }
    $ext = [IO.Path]::GetExtension($full).ToLowerInvariant()
    $type = $types[$ext]
    if (-not $type) { $type = 'application/octet-stream' }
    $bytes = [IO.File]::ReadAllBytes($full)
    Send-Bytes $ctx 200 $type $bytes
  } catch {
    try { $ctx.Response.StatusCode = 500; $ctx.Response.Close() } catch {}
  }
}
