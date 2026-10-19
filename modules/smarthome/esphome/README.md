# ESPHome

ESPHome dashboard for managing ESP32/ESP8266 firmware.

## Dependencies

- [caddy](/modules/platform/caddy.nix)
- [sops](/modules/platform/sops)

## Usage

```nix
den.aspects.<host>.includes = with den.aspects; [esphome];
my.services.esphome.firmwareConfigs.my-device = { ... };
my.services.esphome.secretsFile = config.sops.templates."esphome-secrets.yaml".path;
```

Dashboard is served at `esphome.<domain>`.

## Initial Flashing

WebSerial (browser-based flashing) fails on CP2102-based boards — the
DTR/RTS auto-reset briefly disconnects the USB device, which WebSerial
cannot survive. Use `esptool` for the initial flash instead:

```bash
# Download factory binary from the ESPHome dashboard first
esptool --port /dev/ttyUSB0 --chip esp32 --baud 115200 \
    write-flash 0x0 firmware.factory.bin
```

The user must be in the `dialout` group:

```bash
sudo usermod -aG dialout $USER  # log out and back in after
```

After the initial flash, all subsequent updates are done via OTA
from the ESPHome dashboard — no USB required.
