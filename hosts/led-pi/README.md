# led-pi

Raspberry Pi controlling LED strips.

## Installation

1. **Build the image**

   ```bash
   nix build '.#nixosConfigurations.led-pi.config.system.build.sdImage'
   ```

2. **Write the image to an SD card**

   ```bash
   IMAGE=$(ls result/sd-image/*.img.zst)
   unzstd -d "$IMAGE" -o led-pi.img
   sudo dd if=led-pi.img of=/dev/sdX bs=1M status=progress
   ```

   > Find the correct device with `sudo fdisk -l`. Use the base device (e.g. `/dev/sda`, not `/dev/sda1`).

## Update the configuration remotely

```bash
rebuild --host led-pi --target-host admin@led-pi
```
