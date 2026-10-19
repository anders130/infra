{
    python3Packages,
    fetchFromGitHub,
}: let
    ytmusicapi = python3Packages.ytmusicapi.overridePythonAttrs (_: rec {
        version = "1.12.3";
        src = fetchFromGitHub {
            owner = "sigma67";
            repo = "ytmusicapi";
            tag = version;
            hash = "sha256-mIxtr018hE3LSJCJdD2Lr8UUOic8m2rmPwU86EJuLFk=";
        };
    });
in
    python3Packages.buildPythonApplication {
        pname = "ytm-migrate";
        version = "0.1.0";
        pyproject = true;
        src = ./.;
        build-system = [python3Packages.setuptools];
        dependencies = [python3Packages.requests ytmusicapi];
        nativeCheckInputs = [python3Packages.pytestCheckHook];
    }
