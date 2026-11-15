{
    den.default.nixos = {
        users.users.admin = {
            isNormalUser = true;
            extraGroups = ["wheel"];
            hashedPassword = "$6$35ci2VTHBQagt2F.$D3rDPc2vNQfZwtbm.T5KIXv6CHy//.0aPLYodHuE7TIUV3yaiwXyNgCZ5/vldVhgqvndaUtiu9XAA2jNyglFT1";
            openssh.authorizedKeys.keys = [
                "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIN4fLfoAIHuVXS3tzzbw8x8P1N+Ju2uj3LmqCFs5eTiy"
                "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIE7H+tO79V2PY3nv0L+6hNGw2tlJ3RukmaLo4iKClkhY forgejo-deploy"
            ];
        };
        nix.settings.trusted-users = ["admin"];
    };
}
