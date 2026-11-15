{
    stdenvNoCC,
    fetchurl,
    makeWrapper,
    dotnet-runtime_10,
    lib,
}: let
    version = "1.22.7";
in
    stdenvNoCC.mkDerivation {
        pname = "vintagestory-server";
        inherit version;

        src = fetchurl {
            url = "https://cdn.vintagestory.at/gamefiles/stable/vs_server_linux-x64_${version}.tar.gz";
            hash = "sha256-p9SlIGBFkKlt6BLubGuvRATUPYbPHsT7rBs6WAtSyEc=";
        };
        sourceRoot = ".";

        nativeBuildInputs = [makeWrapper];
        dontFixup = true;

        installPhase = ''
            runHook preInstall
            mkdir -p $out/lib/vintagestory $out/bin
            cp -r . $out/lib/vintagestory
            makeWrapper ${lib.getExe dotnet-runtime_10} $out/bin/VintagestoryServer \
                --add-flags $out/lib/vintagestory/VintagestoryServer.dll
            runHook postInstall
        '';

        meta = {
            homepage = "https://vintagestory.at/";
            license = lib.licenses.unfree;
            platforms = ["x86_64-linux"];
            mainProgram = "VintagestoryServer";
        };
    }
