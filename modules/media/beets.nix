{
    den.aspects.beets.nixos = {
        config,
        lib,
        pkgs,
        ...
    }: let
        inherit (lib) mkOption types;
        svc = config.my.services.beets;
        beetsConfig = pkgs.writeText "beets-config.yaml" ''
            directory: ${svc.musicDir}
            library: /var/lib/beets/library.db

            import:
              copy: no
              move: no
              write: yes
              quiet: yes
              quiet_fallback: asis

            plugins: fetchart embedart

            fetchart:
              auto: yes

            embedart:
              auto: yes
        '';
    in {
        options.my.services.beets.musicDir = mkOption {
            type = types.str;
            default = "/var/lib/beets/music";
            description = "Music library directory beets organizes.";
        };

        config = {
            environment.systemPackages = [pkgs.beets];
            environment.variables.BEETSDIR = "/etc/beets";
            environment.etc."beets/config.yaml".source = beetsConfig;
            systemd.tmpfiles.rules = ["d /var/lib/beets 0755 root root -"];
        };
    };
}
