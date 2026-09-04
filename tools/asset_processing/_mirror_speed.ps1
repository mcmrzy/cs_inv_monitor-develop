$urls = @(
  "https://ghfast.top/https://github.com/danielgatis/rembg/releases/download/v0.0.0/u2net.onnx",
  "https://gh-proxy.com/https://github.com/danielgatis/rembg/releases/download/v0.0.0/u2net.onnx",
  "https://mirror.ghproxy.com/https://github.com/danielgatis/rembg/releases/download/v0.0.0/u2net.onnx",
  "https://ghproxy.cc/https://github.com/danielgatis/rembg/releases/download/v0.0.0/u2net.onnx"
)
$i = 0
foreach ($u in $urls) {
  $i++
  $f = "$env:TEMP\_spd$i.bin"
  $t0 = Get-Date
  curl -s -L -m 25 -r 0-3000000 -o $f $u 2>$null
  $dt = ((Get-Date) - $t0).TotalSeconds
  if (Test-Path $f) {
    $s = (Get-Item $f).Length
    $kbps = [math]::Round($s / 1024 / $dt)
    Write-Output "MIRROR$i : $s bytes in $dt s = $kbps KB/s"
  } else {
    Write-Output "MIRROR$i : FAIL"
  }
}
