{
    den.aspects.ds1.nixos = {
        config,
        lib,
        ...
    }: let
        secretNames = [
            "wifi_ssid"
            "wifi_password"
            "garage_wifi_ssid"
            "garage_wifi_password"
            "ap_password"
            "ota_password"
            "api_encryption_key"
        ];
    in {
        my.services.esphome.secretsFile = config.sops.templates."esphome-secrets.yaml".path;

        sops = {
            secrets = lib.genAttrs secretNames (_: {
                sopsFile = config.my.secretFiles.esphome;
            });

            templates."esphome-secrets.yaml" = {
                owner = "esphome";
                content =
                    secretNames
                    |> lib.concatMapStrings (name: "${name}: ${config.sops.placeholder.${name}}\n");
            };
        };
    };
}
