{
    den.aspects.jellyfin.nixos = {pkgs, ...}: {
        my.services.jellyfin.plugins.file-transformation = rec {
            name = "File Transformation";
            version = "3.0.1.0";
            guid = "5e87cc92-571a-4d8d-8d98-d2d4147f9f90";
            folderPrefix = "FileTransformation";
            zip = pkgs.fetchurl {
                url = "https://github.com/IAmParadox27/jellyfin-plugin-file-transformation/releases/download/${version}/Release-12.0.0.zip";
                sha256 = "78defd17c35c07974ba77412201a1294a0137535b4802e08d778bd622dd4d692";
            };
        };
    };
}
