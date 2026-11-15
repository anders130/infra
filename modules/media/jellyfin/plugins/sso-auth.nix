{
    den.aspects.jellyfin.nixos = {pkgs, ...}: {
        my.services.jellyfin.plugins.sso-auth = rec {
            version = "6.1.0.0";
            guid = "505ce9d1-d916-42fa-86ca-673ef241d7df";
            folderPrefix = "SSO-Auth";
            zip = pkgs.fetchurl {
                url = "https://github.com/MaxRink/jellyfin-plugin-sso/releases/download/v${version}/sso-auth_${version}.zip";
                sha256 = "6311d6b16e89a91e44ce9b5a32c09d28eda292a11b75cd6b942d7bc62664cd00";
            };
        };
    };
}
