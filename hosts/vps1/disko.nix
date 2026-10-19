{inputs, ...}: {
    den.aspects.vps1.nixos = {
        imports = [inputs.disko.nixosModules.disko];
        disko.devices.disk.main = {
            type = "disk";
            device = "/dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_123128652";
            content = {
                type = "gpt";
                partitions = {
                    ESP = {
                        type = "EF00";
                        size = "512M";
                        content = {
                            type = "filesystem";
                            format = "vfat";
                            mountpoint = "/boot";
                        };
                    };
                    root = {
                        size = "100%";
                        content = {
                            type = "filesystem";
                            format = "ext4";
                            mountpoint = "/";
                        };
                    };
                };
            };
        };

        fileSystems."/persist" = {
            device = "/dev/disk/by-id/scsi-0HC_Volume_106374594";
            fsType = "ext4";
            options = ["defaults" "nofail"];
        };
    };
}
