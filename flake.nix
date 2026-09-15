{
  description = "AxiomLayer SQLite and FTS5 upstream integration gate";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/c3eea5b2156db11c7eeeada3dc737711255b253e";

    sqlite-fleet-mirror = {
      url = "github:sqlite/sqlite/b09c88c14082339b66c7b7158d609a771e64ca69";
      flake = false;
    };

    sqlite-candidate = {
      url = "github:AxiomLayer/sqlite/7936c5107fa4081c347852dc84054a7bb5c5fbe3";
      flake = false;
    };
  };

  outputs = inputs:
    let
      pin = builtins.fromJSON (builtins.readFile ./integration/axiomlayer/runtime-pin.json);
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];
      forAllSystems = inputs.nixpkgs.lib.genAttrs systems;

      integrationFor = system:
        let
          pkgs = import inputs.nixpkgs { inherit system; };
          lib = pkgs.lib;
          releaseArchive = pkgs.fetchurl {
            inherit (pin.fleetRelease.archive) url;
            hash = pin.fleetRelease.archive.nixHash;
          };

          mkSqlite = {
            pname,
            src,
            expectedVersion ? null,
            expectedFossilUuid ? null,
            verifyMirror ? false,
            disableTcl ? false,
          }:
            pkgs.stdenv.mkDerivation {
              inherit pname src;
              version = if expectedVersion == null then "candidate" else expectedVersion;
              strictDeps = true;
              nativeBuildInputs = [
                pkgs.gnugrep
                pkgs.gnumake
                pkgs.pkg-config
              ];
              buildInputs = [ pkgs.zlib ];
              configureFlags = [
                "--fts5"
                "--disable-readline"
              ] ++ lib.optionals disableTcl [ "--disable-tcl" ];
              enableParallelBuilding = true;

              prePatch = lib.optionalString verifyMirror ''
                cc -g -o "$TMPDIR/sqlite-src-verify" tool/src-verify.c
                "$TMPDIR/sqlite-src-verify" "$PWD"
              '';

              preConfigure = ''
                source_version=$(tr -d '\r\n' < VERSION)
                test -n "$source_version"
                ${lib.optionalString (expectedVersion != null) ''
                  test "$source_version" = ${lib.escapeShellArg expectedVersion}
                ''}
                ${lib.optionalString (expectedFossilUuid != null) ''
                  if test -f manifest.uuid; then
                    test "$(tr -d '\r\n' < manifest.uuid)" = ${lib.escapeShellArg expectedFossilUuid}
                  else
                    grep -F ${lib.escapeShellArg expectedFossilUuid} sqlite3.c >/dev/null
                  fi
                ''}
              '';

              doCheck = true;
              checkPhase = ''
                runHook preCheck
                compile_option=$(./sqlite3 :memory: "SELECT sqlite_compileoption_used('ENABLE_FTS5');")
                test "$compile_option" = 1
                matches=$(./sqlite3 :memory: \
                  "CREATE VIRTUAL TABLE docs USING fts5(body); INSERT INTO docs(body) VALUES('axiom layer'); SELECT count(*) FROM docs WHERE docs MATCH 'axiom';")
                test "$matches" = 1
                runHook postCheck
              '';

              postInstall = ''
                test -x "$out/bin/sqlite3"
                test -d "$out/lib"
                compile_option=$("$out/bin/sqlite3" :memory: "SELECT sqlite_compileoption_used('ENABLE_FTS5');")
                test "$compile_option" = 1
              '';
            };

          fleetRelease = mkSqlite {
            pname = "axiomlayer-sqlite-fleet-release";
            src = releaseArchive;
            expectedVersion = pin.fleetRelease.version;
            expectedFossilUuid = pin.fleetRelease.fossilManifestUuid;
          };

          upstreamCandidate = mkSqlite {
            pname = "axiomlayer-sqlite-upstream-candidate";
            src = inputs.sqlite-candidate;
            verifyMirror = true;
            disableTcl = true;
          };

          provenance = pkgs.runCommand "axiomlayer-sqlite-provenance" {
            nativeBuildInputs = [ pkgs.openssl ];
          } ''
            archive_sha3=$(openssl dgst -sha3-256 ${releaseArchive} | awk '{print $NF}')
            test "$archive_sha3" = ${lib.escapeShellArg pin.fleetRelease.archive."sha3-256"}

            test ${lib.escapeShellArg inputs.sqlite-fleet-mirror.rev} = \
              ${lib.escapeShellArg pin.fleetRelease.gitMirrorCommit}
            test "$(tr -d '\r\n' < ${inputs.sqlite-fleet-mirror}/VERSION)" = \
              ${lib.escapeShellArg pin.fleetRelease.version}
            test "$(tr -d '\r\n' < ${inputs.sqlite-fleet-mirror}/manifest.uuid)" = \
              ${lib.escapeShellArg pin.fleetRelease.fossilManifestUuid}

            test ${lib.escapeShellArg inputs.sqlite-candidate.rev} = \
              ${lib.escapeShellArg pin.upstreamCandidate.gitMirrorCommit}
            test "$(tr -d '\r\n' < ${inputs.sqlite-candidate}/VERSION)" = \
              ${lib.escapeShellArg pin.upstreamCandidate.version}
            test "$(tr -d '\r\n' < ${inputs.sqlite-candidate}/manifest.uuid)" = \
              ${lib.escapeShellArg pin.upstreamCandidate.fossilManifestUuid}

            touch "$out"
          '';
        in
        {
          inherit fleetRelease provenance upstreamCandidate;
        };
    in
    {
      packages = forAllSystems (system:
        let integration = integrationFor system;
        in {
          fleet-release = integration.fleetRelease;
          upstream-candidate = integration.upstreamCandidate;
          default = integration.upstreamCandidate;
        });

      checks = forAllSystems (system:
        let integration = integrationFor system;
        in {
          fleet-release-fts5 = integration.fleetRelease;
          upstream-candidate-fts5 = integration.upstreamCandidate;
          provenance = integration.provenance;
        });
    };
}
