{
    den,
    inputs,
    lib,
    ...
}: let
    hosts = inputs.self.nixosConfigurations;
    repoRoot = inputs.self.outPath;

    mkSectionType = l:
        l.types.submodule {
            options.title = l.mkOption {type = l.types.str;};
            options.content = l.mkOption {type = l.types.lines;};
        };

    capitalize = s: lib.toUpper (builtins.substring 0 1 s) + builtins.substring 1 (-1) s;

    mkServicesTable = urlFor: services:
        services
        |> lib.filterAttrs (_: svc: svc ? port)
        |> lib.mapAttrsToList (name: _: "| ${capitalize name} | ${urlFor name} |")
        |> (rows: ["| Service | URL |" "| --- | --- |"] ++ rows)
        |> builtins.concatStringsSep "\n";

    posOf = r: let
        tryField = field:
            if r ? ${field}
            then builtins.unsafeGetAttrPos field r
            else null;
    in
        lib.findFirst (x: x != null) null
        (map tryField ["intro" "title" "sections" "install"]);

    derivePath = name: r:
        r.path or (
            let
                pos = posOf r;
            in
                if pos != null
                then let
                    dir = dirOf pos.file;
                    rel = lib.removePrefix (repoRoot + "/") dir;
                in
                    if rel != dir
                    then rel
                    else null
                else if hosts ? ${name}
                then "hosts/${name}"
                else null
        );

    mkEntry = name: let
        r = den.aspects.${name}.readme;
        isHost = hosts ? ${name};
        h =
            if isHost
            then hosts.${name}.config.networking.hostName
            else name;
    in {
        path = derivePath name r;
        title =
            r.title or (
                if isHost
                then name
                else ""
            );
        intro = r.intro or "";
        sections =
            lib.optional (isHost && r.install or "" != "") {
                title = "Installation";
                content = r.install;
            }
            ++ r.sections or []
            ++ lib.optional isHost {
                title = "Update the configuration remotely";
                content = ''
                    ```bash
                    rebuild --host ${h} --target-host admin@${h}
                    ```
                '';
            };
    };

    readmeAspects = lib.filterAttrs (
        name: aspect:
            builtins.isAttrs aspect
            && aspect ? readme
            && builtins.isAttrs aspect.readme
            && (derivePath name aspect.readme) != null
    )
    den.aspects;
in {
    options.readmeLib = lib.mkOption {
        internal = true;
        readOnly = true;
        type = lib.types.raw;
        default = {
            inherit mkSectionType mkServicesTable;
            mkSopsSecrets = path: ''
                Edit the secrets file:

                ```bash
                sops ${path}
                ```

                Update keys after adding a new device:

                ```bash
                sops updatekeys ${path}
                ```
            '';
            mkSdImageInstall = writeTarget: hostName: ''
                1. **Build the image**

                   ```bash
                   nix build '.#nixosConfigurations.${hostName}.config.system.build.sdImage'
                   ```

                2. **Write the image to ${writeTarget}**

                   ```bash
                   IMAGE=$(ls result/sd-image/*.img.zst)
                   unzstd -d "$IMAGE" -o ${hostName}.img
                   sudo dd if=${hostName}.img of=/dev/sdX bs=1M status=progress
                   ```

                   > Find the correct device with `sudo fdisk -l`. Use the base device (e.g. `/dev/sda`, not `/dev/sda1`).
            '';
        };
    };
    config = {
        den.reservedKeys = ["readme"];

        perSystem = {
            pkgs,
            lib,
            config,
            ...
        }: let
            sectionType = mkSectionType lib;
            readmeType = lib.types.submodule {
                options = {
                    path = lib.mkOption {
                        type = lib.types.str;
                        description = "Directory path relative to repo root (README.md is appended).";
                    };
                    title = lib.mkOption {
                        type = lib.types.str;
                        default = "";
                    };
                    intro = lib.mkOption {
                        type = lib.types.lines;
                        default = "";
                    };
                    sections = lib.mkOption {
                        type = lib.types.listOf sectionType;
                        default = [];
                    };
                    usage = lib.mkOption {
                        type = lib.types.listOf sectionType;
                        default = [];
                        description = "Subsections under a '## Usage' heading.";
                    };
                };
            };

            join = parts: builtins.concatStringsSep "\n\n" (builtins.filter (x: x != "") parts);
            heading = level: s: "${level} ${s.title}\n\n${s.content}";

            writeMarkdown = text:
                pkgs.runCommand "README.md" {nativeBuildInputs = [pkgs.prettier];} ''
                    prettier --parser markdown ${pkgs.writeText "readme" text} > $out
                '';

            render = doc:
                writeMarkdown (join (
                    [
                        (lib.optionalString (doc.title != "") "# ${doc.title}")
                        doc.intro
                    ]
                    ++ map (heading "##") doc.sections
                    ++ lib.optional (doc.usage != []) (
                        "## Usage\n\n"
                        + builtins.concatStringsSep "\n\n" (map (heading "###") doc.usage)
                    )
                ));
        in {
            options.readmeFiles = lib.mkOption {
                type = lib.types.attrsOf readmeType;
                default = {};
            };
            config.readmeFiles = lib.mapAttrs (name: _: mkEntry name) readmeAspects;
            config.files.file =
                lib.mapAttrs' (_: rf: lib.nameValuePair "${rf.path}/README.md" {source = render rf;})
                config.readmeFiles;
        };
    };
}
