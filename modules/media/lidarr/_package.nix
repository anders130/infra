{
    stdenvNoCC,
    fetchurl,
    autoPatchelfHook,
    makeWrapper,
    icu,
    openssl,
    zlib,
    sqlite,
    curl,
    lib,
    stdenv,
}: let
    version = "3.1.6.5078";
in
    stdenvNoCC.mkDerivation {
        pname = "lidarr-nightly";
        inherit version;

        src = fetchurl {
            url = "https://github.com/Lidarr/Lidarr/releases/download/v${version}/Lidarr.develop.${version}.linux-core-x64.tar.gz";
            sha256 = "1d814f2376ca6c5c4fe91fccdae3a4b11fb1034eb34720be49df708bcf8c2b81";
            name = "Lidarr.develop.${version}.linux-core-x64.tar.gz";
        };

        nativeBuildInputs = [autoPatchelfHook makeWrapper];
        buildInputs = [icu openssl zlib sqlite curl stdenv.cc.cc.lib];
        autoPatchelfIgnoreMissingDeps = ["liblttng-ust.so.0"];
        dontStrip = true;

        installPhase = ''
            runHook preInstall
            mkdir -p $out/lib/lidarr/bin $out/bin
            cp -r . $out/lib/lidarr/bin
            printf 'PackageVersion=%s\nPackageAuthor=[NixOS](https://nixos.org)\nUpdateMethod=External\n' ${version} > $out/lib/lidarr/package_info
            makeWrapper $out/lib/lidarr/bin/Lidarr $out/bin/Lidarr \
                --prefix LD_LIBRARY_PATH : ${lib.makeLibraryPath [sqlite icu openssl]}
            runHook postInstall
        '';

        meta.mainProgram = "Lidarr";
    }
