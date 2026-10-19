{inputs, ...}: {
    flake-file.inputs.soundgate.url = "github:anders130/soundgate";
    flake-follows.exclude = ["soundgate/nixpkgs"];

    den.aspects.music-pi.nixos = {
        imports = [inputs.soundgate.nixosModules.soundgate];
        services.soundgate = {
            enable = true;
            openFirewall = true;
            pipewireSink = "@DEFAULT_SINK@";
            controlPipewireVolume = false;
            sources = {
                bluetooth.enable = true;
                spotifyd = {
                    enable = true;
                    deviceName = "music-pi";
                    alsaVolumeSync = false;
                    alsaDevice = "hw:CARD=sndrpihifiberry";
                    alsaControl = "Digital"; # or whatever scontrols shows
                };
                dlna = {
                    enable = true;
                    openFirewall = true;
                    friendlyName = "music-pi";
                    uuid = "a1b2c3d4-e5f6-7890-abcd-music00000pi";
                    interface = "eth0";
                };
            };
        };
    };
}
