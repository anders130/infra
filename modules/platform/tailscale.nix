{
    den.aspects.tailscale.nixos = {
        services.tailscale.enable = true;
        networking.firewall = {
            allowedUDPPorts = [41641];
            # Tailscale requires loose reverse path filtering
            checkReversePath = "loose";
        };
    };
}
