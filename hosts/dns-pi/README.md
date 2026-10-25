# dns-pi

Raspberry Pi 4B handling DNS (Pihole), Zigbee proxy, and MQTT. Boots NixOS from an NVMe SSD connected via USB.

## Installation

1. **Build the image**

   ```bash
   nix build '.#nixosConfigurations.dns-pi.config.system.build.sdImage'
   ```

2. **Write the image to the NVMe drive**

   ```bash
   IMAGE=$(ls result/sd-image/*.img.zst)
   unzstd -d "$IMAGE" -o dns-pi.img
   sudo dd if=dns-pi.img of=/dev/sdX bs=1M status=progress
   ```

   > Find the correct device with `sudo fdisk -l`. Use the base device (e.g. `/dev/sda`, not `/dev/sda1`).

## Update the configuration remotely

```bash
rebuild --host dns-pi --target-host admin@dns-pi
```
