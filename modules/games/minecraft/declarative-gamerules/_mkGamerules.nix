pkgs: gamerules: let
    inherit (builtins) concatStringsSep attrNames isBool;
    toValidString = actual:
        if isBool actual
        then
            (
                if actual
                then "true"
                else "false"
            )
        else toString actual;
    toGamerule = gamerule: "gamerule ${gamerule} ${toValidString gamerules.${gamerule}}";
    renderedGamerules =
        gamerules
        |> attrNames
        |> map toGamerule
        |> concatStringsSep "\n";
    packMcmeta = builtins.toFile "pack.mcmeta" (builtins.toJSON {
        pack = {
            description = "Sets gamerules declaratively";
            pack_format = 81;
            supported_formats = [81 81];
        };
    });
in
    pkgs.stdenvNoCC.mkDerivation {
        pname = "declarative-gamerules";
        version = "1.0.0";

        dontUnpack = true;

        buildPhase = ''
            runHook preBuild

            mkdir -p data/declarative_gamerules/function
            echo '${renderedGamerules}' > data/declarative_gamerules/function/setup.mcfunction

            runHook postBuild
        '';

        installPhase = ''
            runHook preInstall

            mkdir -p $out
            cp -r data $out/
            cp ${packMcmeta} $out/pack.mcmeta

            runHook postInstall
        '';
    }
