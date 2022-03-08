# zbasefind

## Usage

```
$ zig build

$ ./zig-out/bin/zbasefind esp32_wifi_firmware.bin
info: File size = 655712
info: Buffer size = 655712
info: Loaded firmware file esp32_wifi_firmware.bin
info: Number of pointers: 111082
info: Number of strings: 2274
info: Best base address candidates:
info: Base address: 3f400000, matches: 1804
info: Base address: 00000000, matches: 146
info: Base address: f01c0000, matches: 140
info: Base address: 3ffb0000, matches: 78
info: Base address: 3f410000, matches: 68
```