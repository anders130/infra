{
    den.default.nixos = {
        services.openssh.enable = true;
        security = {
            pam.sshAgentAuth.enable = true;
            sudo.wheelNeedsPassword = false;
        };
    };
}
