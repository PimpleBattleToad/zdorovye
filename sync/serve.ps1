param(
  [int]$Port = 8766,
  [string]$Root = (Split-Path -Parent $PSScriptRoot),
  [string]$Bind = '0.0.0.0'
)

# ASCII ONLY on purpose: Windows PowerShell 5.1 reads a BOM-less file as ANSI,
# and UTF-8 Cyrillic bytes 0x91-0x94 turn into smart quotes -> parse error.

$ErrorActionPreference = 'Stop'

try {
  [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
  $OutputEncoding = New-Object System.Text.UTF8Encoding($false)
} catch { }

$rootFull = [System.IO.Path]::GetFullPath($Root).TrimEnd('\')

$mime = @{
  '.html' = 'text/html; charset=utf-8'
  '.json' = 'application/json; charset=utf-8'
  '.js'   = 'application/javascript; charset=utf-8'
  '.css'  = 'text/css; charset=utf-8'
  '.svg'  = 'image/svg+xml'
  '.png'  = 'image/png'
  '.ico'  = 'image/x-icon'
  '.txt'  = 'text/plain; charset=utf-8'
  '.csv'  = 'text/csv; charset=utf-8'
  '.webmanifest' = 'application/manifest+json; charset=utf-8'
}

function Get-LanIp {
  # prefer the adapter that actually has the default route (Wi-Fi / Ethernet),
  # otherwise virtual switches (Hyper-V, VirtualBox) win and the phone cannot connect
  try {
    $route = Get-NetRoute -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue |
             Sort-Object RouteMetric | Select-Object -First 1
    if ($route) {
      $ip = Get-NetIPAddress -InterfaceIndex $route.InterfaceIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue |
            Where-Object { $_.IPAddress -notlike '127.*' -and $_.IPAddress -notlike '169.254.*' } |
            Select-Object -First 1
      if ($ip) { return $ip.IPAddress }
    }
  } catch { }

  try {
    $all = [System.Net.Dns]::GetHostAddresses([System.Net.Dns]::GetHostName())
    foreach ($a in $all) {
      $s = $a.ToString()
      if ($a.AddressFamily -eq [System.Net.Sockets.AddressFamily]::InterNetwork -and -not $s.StartsWith('127.') -and -not $s.StartsWith('169.254.')) {
        return $s
      }
    }
  } catch { }
  return $null
}

$listener = New-Object System.Net.Sockets.TcpListener([System.Net.IPAddress]::Parse($Bind), $Port)
$listener.Start()

Write-Host ''
Write-Host '  Zdorovye - local server' -ForegroundColor Green
Write-Host ('  PC:      http://127.0.0.1:{0}/' -f $Port)
$lanIp = Get-LanIp
if ($lanIp) {
  Write-Host ('  Phone:   http://{0}:{1}/   (same Wi-Fi)' -f $lanIp, $Port) -ForegroundColor Cyan
}
Write-Host '  data.json next to index.html is picked up automatically.'
Write-Host '  Keep this window open while using the app.'
Write-Host '  Stop: Ctrl+C'
Write-Host ''

while ($true) {
  $client = $listener.AcceptTcpClient()
  try {
    $client.ReceiveTimeout = 5000
    $stream = $client.GetStream()
    $reader = New-Object System.IO.StreamReader($stream, [System.Text.Encoding]::ASCII, $false, 1024, $true)

    $requestLine = $reader.ReadLine()
    if (-not $requestLine) { $client.Close(); continue }
    while ($true) {
      $h = $reader.ReadLine()
      if ($null -eq $h -or $h -eq '') { break }
    }

    $method = 'GET'
    $target = '/'
    if ($requestLine -match '^(GET|HEAD)\s+(\S+)') {
      $method = $matches[1]
      $target = $matches[2]
    }

    $path = $target
    $q = $path.IndexOf('?')
    if ($q -ge 0) { $path = $path.Substring(0, $q) }
    $path = [System.Uri]::UnescapeDataString($path)
    if ($path -eq '/' -or $path -eq '') { $path = '/index.html' }
    $path = $path.Replace('/', '\')

    $full = [System.IO.Path]::GetFullPath((Join-Path $rootFull $path.TrimStart('\')))

    $status = '200 OK'
    $body = $null
    $contentType = 'text/plain; charset=utf-8'

    if (-not $full.StartsWith($rootFull, [System.StringComparison]::OrdinalIgnoreCase)) {
      $status = '403 Forbidden'
      $body = [System.Text.Encoding]::UTF8.GetBytes('403 Forbidden')
    } elseif (-not [System.IO.File]::Exists($full)) {
      $status = '404 Not Found'
      $body = [System.Text.Encoding]::UTF8.GetBytes('404 Not Found')
    } else {
      $ext = [System.IO.Path]::GetExtension($full).ToLower()
      if ($mime.ContainsKey($ext)) { $contentType = $mime[$ext] }
      try {
        $body = [System.IO.File]::ReadAllBytes($full)
      } catch {
        $status = '500 Internal Server Error'
        $body = [System.Text.Encoding]::UTF8.GetBytes('500')
      }
    }

    $head = 'HTTP/1.1 ' + $status + "`r`n" +
            'Content-Type: ' + $contentType + "`r`n" +
            'Content-Length: ' + $body.Length + "`r`n" +
            'Cache-Control: no-store, must-revalidate' + "`r`n" +
            'Connection: close' + "`r`n`r`n"

    $headBytes = [System.Text.Encoding]::ASCII.GetBytes($head)
    $stream.Write($headBytes, 0, $headBytes.Length)
    if ($method -ne 'HEAD' -and $body.Length -gt 0) {
      $stream.Write($body, 0, $body.Length)
    }
    $stream.Flush()

    $size = $body.Length
    Write-Host ('  {0} {1} -> {2} ({3} b)' -f $method, $target, $status, $size) -ForegroundColor DarkGray
  } catch {
    Write-Host ('  error: ' + $_.Exception.Message) -ForegroundColor Red
  } finally {
    try { $client.Close() } catch { }
  }
}
