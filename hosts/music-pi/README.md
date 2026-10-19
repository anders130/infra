# music-pi

Raspberry Pi for audio playback, equipped with a HiFiBerry DAC+ HAT.

## Installation

1. **Build the image**

   ```bash
   nix build '.#nixosConfigurations.music-pi.config.system.build.sdImage'
   ```

2. **Write the image to an SD card**

   ```bash
   IMAGE=$(ls result/sd-image/*.img.zst)
   unzstd -d "$IMAGE" -o music-pi.img
   sudo dd if=music-pi.img of=/dev/sdX bs=1M status=progress
   ```

   > Find the correct device with `sudo fdisk -l`. Use the base device (e.g. `/dev/sda`, not `/dev/sda1`).

## Update the configuration remotely

```bash
rebuild --host music-pi --target-host admin@music-pi
```
