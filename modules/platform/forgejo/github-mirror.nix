{
    den.aspects.forgejo.nixos = {config, ...}: let
        secret = config.sops.secrets."github-mirror/ssh_key";
    in {
        sops.secrets."github-mirror/ssh_key" = {
            sopsFile = config.my.secretFiles.github-mirror;
            group = "deploy-key-readers";
            mode = "0440";
        };

        programs.ssh = {
            knownHosts."github.com".publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl";
            extraConfig = ''
                Match host github.com localuser ${config.systemd.services."gitea-runner-${config.networking.hostName}".serviceConfig.User}
                    IdentityFile ${secret.path}
                    IdentitiesOnly yes
            '';
        };
    };

    perSystem = {pkgs, ...}: {
        files.file.".forgejo/workflows/github-mirror.yml".text = builtins.readFile
        ((pkgs.formats.yaml {}).generate "github-mirror.yml" {
            on = {
                schedule = [{cron = "0 3 * * 0";}];
                workflow_dispatch = {};
            };
            jobs.mirror = {
                runs-on = "native";
                steps = [
                    {
                        uses = "https://git.gollub.dev/jesse/actions/mirror@v1";
                        "with" = {
                            target = "git@github.com:anders130/infra.git";
                            squash = true;
                        };
                    }
                ];
            };
        });
    };
}
