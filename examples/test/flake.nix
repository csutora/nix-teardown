{
    description = "test consumer for nix-teardown";

    inputs = {
        nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
        nix-teardown = {
            url = "github:csutora/nix-teardown";
            inputs.nixpkgs.follows = "nixpkgs";
        };
    };

    outputs = { self, nixpkgs, nix-teardown }:
    let
        systems = [ "aarch64-darwin" "x86_64-darwin" ];
        forEachSystem = f:
            nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});

        tmpMarker = "/tmp/nix-teardown-test/marker";
        rootMarker = "/var/lib/nix-teardown-test/marker";
        ranMarker = "/tmp/nix-teardown-test-cleanup-ran";
    in {
        darwinModules.default = { ... }: {
            imports = [
                (nix-teardown.mkDarwinEntry "https://github.com/csutora/nix-teardown/tree/main/examples/test" ''
                    rm -rf /tmp/nix-teardown-test
                    rm -rf /var/lib/nix-teardown-test
                    date > ${ranMarker}
                '')
            ];

            config.system.activationScripts.nix-teardown-test.text = ''
                mkdir -p /tmp/nix-teardown-test
                touch ${tmpMarker}

                mkdir -p /var/lib/nix-teardown-test
                touch ${rootMarker}

                rm -f ${ranMarker}
            '';
        };

        apps = forEachSystem (pkgs: {
            verify = {
                type = "app";
                program = toString (pkgs.writeShellScript "nix-teardown-test-verify" ''
                    set -u
                    fail=0

                    check_present() {
                        if [ -e "$1" ]; then
                            echo "  [+] present: $1"
                        else
                            echo "  [-] missing: $1"
                            fail=1
                        fi
                    }

                    check_absent() {
                        if [ ! -e "$1" ]; then
                            echo "  [+] absent:  $1"
                        else
                            echo "  [-] still present: $1"
                            fail=1
                        fi
                    }

                    mode="''${1:-installed}"
                    case "$mode" in
                        installed)
                            echo "verifying installed state..."
                            check_present ${tmpMarker}
                            check_present ${rootMarker}
                            check_absent  ${ranMarker}
                            ;;
                        cleaned)
                            echo "verifying cleaned state..."
                            check_absent  ${tmpMarker}
                            check_absent  ${rootMarker}
                            check_present ${ranMarker}
                            check_absent  /var/lib/nix-teardown-test
                            check_absent  /var/lib/nix-teardown
                            shopt -s nullglob
                            stale_plists=(/Library/LaunchDaemons/nix-teardown.watcher.*.plist)
                            if [ ''${#stale_plists[@]} -eq 0 ]; then
                                echo "  [+] no nix-teardown daemon plists in /Library/LaunchDaemons/"
                            else
                                for p in "''${stale_plists[@]}"; do
                                    echo "  [-] daemon plist still present: $p"
                                done
                                fail=1
                            fi
                            ;;
                        *)
                            echo "usage: nix run .#verify -- {installed|cleaned}" >&2
                            exit 2
                            ;;
                    esac

                    exit $fail
                '');
            };
        });
    };
}
