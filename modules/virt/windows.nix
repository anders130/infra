{
    serviceRegistry.windows = {
        web = {
            subdomain = "windows11.qemu";
            local = true;
        };
        dashboard = {
            name = "Windows 11";
            icon = "microsoft-windows";
            category = "Platform";
            widget = {
                type = "quickemu-vm";
                vmName = "windows-11-23h2";
                vmDir = "/var/lib/quickemu/windows-11-23h2";
            };
        };
        actions = [
            {
                id = "start";
                label = "Start";
                command = "start-vm";
            }
            {
                id = "stop";
                label = "Stop";
                command = "stop-vm";
            }
        ];
    };

    den.aspects.windows.nixos = {
        config,
        lib,
        pkgs,
        ...
    }: let
        inherit (lib) mkOption types;
        svc = config.my.services.windows;
        servicePath = "/var/lib/quickemu";
        sharePath = svc.sharePath;
        novncPort = 6080;
        vmName = "windows-11-23h2";
        vmPath = "${servicePath}/${vmName}";
        vmConfPath = "${vmPath}/${vmName}.conf";
        files = {
            windows-iso = {
                path = "${vmPath}/windows.iso";
                url = "https://dn721608.ca.archive.org/0/items/win11_23h2_english_x64v2_202409/Win11_23H2_English_x64v2.iso";
            };
            virtio-win = {
                path = "${vmPath}/virtio-win.iso";
                url = "https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/stable-virtio/virtio-win.iso";
            };
        };
        windows-11-conf = pkgs.writeText "${vmName}.conf" ''
            #! --vm
            guest_os="windows"
            disk_img="${vmPath}/disk.qcow2"
            iso_img="${vmPath}/windows.iso"
            fixed_iso="${vmPath}/virtio-win.iso"
            disk_size="64G"
            tpm="on"
            secureboot="off"
        '';
        setupVmScript = pkgs.writeShellScriptBin "setup-vm" ''
            mkdir -p ${vmPath}
            # Windows ISO
            if [ ! -e "${files.windows-iso.path}" ]; then
                ${lib.getExe pkgs.wget} -O ${files.windows-iso.path} ${files.windows-iso.url}
            fi
            # Virtio ISO
            if [ ! -e "${files.virtio-win.path}" ]; then
                ${lib.getExe pkgs.wget} -O ${files.virtio-win.path} ${files.virtio-win.url}
            fi
        '';
        startVmScript = pkgs.writeShellScriptBin "start-vm" ''
            mkdir -p ${vmPath}
            cp -f ${windows-11-conf} ${vmConfPath}
            ${lib.getExe pkgs.quickemu} \
              --vm ${vmConfPath} \
              --display none \
              --extra_args "-vnc :1"
        '';
        stopVmScript = pkgs.writeShellScriptBin "stop-vm" ''
            pkill -f "${vmPath}/disk.qcow2"
        '';
    in {
        options.my.services.windows = {
            sharePath = mkOption {
                type = types.str;
                default = "/home/admin/public";
                description = "Directory shared with the VM host over SMB alongside the download shares below.";
            };
            dataSharePath = mkOption {
                type = types.str;
                default = "/var/lib/samba/shares/data";
                description = "SMB share path exposed as \"data\".";
            };
            appdataSharePath = mkOption {
                type = types.str;
                default = "/var/lib/samba/shares/appdata";
                description = "SMB share path exposed as \"appdata\".";
            };
            shareForceUser = mkOption {
                type = types.str;
                default = "nobody";
                description = "Unix user SMB writes are attributed to, regardless of the connecting Windows account.";
            };
            allowedSubnet = mkOption {
                type = types.str;
                default = "127.0.0.1";
                description = "Space-separated hosts/subnets allowed to reach the SMB shares (Samba \"hosts allow\" syntax).";
            };
        };

        config.systemd.tmpfiles.rules = [
            "d ${servicePath} 0755 root root - -"
            "d ${sharePath} 0755 admin users - -"
        ];
        config.environment.systemPackages = [setupVmScript startVmScript stopVmScript];
        config.systemd.services.novnc-windows11 = {
            description = "novnc for headless windows11 vm";
            after = ["network.target"];
            wantedBy = ["multi-user.target"];
            serviceConfig = {
                ExecStart = ''
                    ${lib.getExe pkgs.novnc} \
                        --vnc localhost:5901 \
                        --listen ${toString novncPort}
                '';
                Environment = "PATH=${pkgs.procps}/bin:${pkgs.coreutils}/bin:${pkgs.gnugrep}/bin";
                Restart = "always";
            };
        };
        config.my.services.caddy.virtualHosts.${config.my.services.windows.url} = {
            local = true;
            extraConfig = ''
                handle /websockify* {
                    reverse_proxy localhost:${toString novncPort}
                }

                root * ${pkgs.novnc}/share/webapps/novnc
                file_server

                handle_path / {
                    rewrite * /vnc.html
                }
            '';
        };
        config.services.samba = {
            enable = true;
            openFirewall = false;
            settings = let
                mkFileShare = path: {
                    inherit path;
                    browseable = "yes";
                    "read only" = "no";
                    "guest ok" = "yes";
                    "create mask" = "0644";
                    "directory mask" = "0755";
                    "force user" = svc.shareForceUser;
                    "force group" = "users";
                };
            in {
                global = {
                    "workgroup" = "WORKGROUP";
                    "server string" = "smbnix";
                    "netbios name" = "smbnix";
                    "security" = "user";
                    "hosts allow" = "${svc.allowedSubnet} 127.0.0.1 localhost";
                    "hosts deny" = "0.0.0.0/0";
                    "guest account" = "nobody";
                    "map to guest" = "bad user";
                };
                data = mkFileShare svc.dataSharePath;
                appdata = mkFileShare svc.appdataSharePath;
            };
        };
    };
}
