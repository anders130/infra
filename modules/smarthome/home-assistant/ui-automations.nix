{
    den.aspects.home-assistant.nixos = {lib, ...}: {
        services.home-assistant.configWritable = true;

        systemd.tmpfiles.settings."hass-automations"."/var/lib/hass/automations.yaml" = {
            f = {
                mode = "0600";
                user = "hass";
                group = "hass";
                argument = "[]";
            };
        };

        systemd.services.home-assistant.preStart = lib.mkMerge [
            (lib.mkBefore ''
                rm -f /var/lib/hass/configuration.yaml
            '')
            (lib.mkAfter ''
                if ! grep -qF '!include automations.yaml' /var/lib/hass/configuration.yaml; then
                    printf '\nautomation: !include automations.yaml\n' >> /var/lib/hass/configuration.yaml
                fi
            '')
        ];
    };
}
