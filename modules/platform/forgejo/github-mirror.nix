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
                env = {
                    GIT_AUTHOR_NAME = "github-mirror";
                    GIT_AUTHOR_EMAIL = "github-mirror@localhost";
                    GIT_COMMITTER_NAME = "github-mirror";
                    GIT_COMMITTER_EMAIL = "github-mirror@localhost";
                };
                steps = [
                    {
                        uses = "actions/checkout@v4";
                        "with".ref = "master";
                    }
                    {run = "git checkout --orphan snapshot";}
                    {run = "git commit -m \"Snapshot of $(git rev-parse --short master)\"";}
                    {run = "git push --force git@github.com:anders130/infra.git snapshot:master";}
                ];
            };
        });
    };
}
