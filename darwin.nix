{ namespace, slug }:
{ config, lib, pkgs, ... }:

let
    cfg = config.services.${namespace};

    instanceDir = "/var/lib/nix-teardown/${slug}";
    entriesDir = "${instanceDir}/entries";
    watcherPath = "${instanceDir}/watcher.sh";
    uninstallPath = "${instanceDir}/uninstall.sh";
    selfEntryName = "__nix-teardown-self__";
    selfEntryDir = "${entriesDir}/${selfEntryName}";
    daemonLabel = "nix-teardown.watcher.${slug}";
    daemonPlist = "/Library/LaunchDaemons/${daemonLabel}.plist";

    entryDirId = entry:
        builtins.substring 0 12 (builtins.hashString "sha256" entry.id);

    plistFile = pkgs.writeText "${daemonLabel}.plist" ''
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>${daemonLabel}</string>
            <key>ProgramArguments</key>
            <array>
                <string>/bin/bash</string>
                <string>${watcherPath}</string>
            </array>
            <key>RunAtLoad</key>
            <true/>
            <key>WatchPaths</key>
            <array>
                <string>/run/current-system</string>
            </array>
            <key>StandardErrorPath</key>
            <string>/var/log/${daemonLabel}.log</string>
            <key>StandardOutPath</key>
            <string>/var/log/${daemonLabel}.log</string>
        </dict>
        </plist>
    '';

    watcherFile = pkgs.writeShellScript "nix-teardown-watcher-${slug}" ''
        set -u

        entries=${entriesDir}
        current=$(readlink /run/current-system 2>/dev/null || echo "")

        if [ -z "$current" ] || [ ! -d "$entries" ]; then
            exit 0
        fi

        self_stale=0

        for entry in "$entries"/*/; do
            [ -d "$entry" ] || continue
            dir_name=$(basename "$entry")
            sys_file="$entry/systemConfig"

            [ -f "$sys_file" ] || continue
            if [ "$(cat "$sys_file")" = "$current" ]; then
                continue
            fi

            if [ "$dir_name" = "${selfEntryName}" ]; then
                self_stale=1
                continue
            fi

            entry_id=$(cat "$entry/id" 2>/dev/null || echo "unknown")
            echo "[nix-teardown] running cleanup for: $entry_id" >&2

            if [ -x "$entry/cleanup.sh" ]; then
                "$entry/cleanup.sh" || true
            fi

            rm -rf "$entry"
        done

        if [ "$self_stale" = "1" ]; then
            cat > ${uninstallPath} <<'NIX_TEARDOWN_UNINSTALL'
        #!/bin/bash
        sleep 3
        launchctl bootout system ${daemonPlist} 2>/dev/null
        rm -f ${daemonPlist}
        rm -rf ${instanceDir}
        rmdir /var/lib/nix-teardown 2>/dev/null || true
        NIX_TEARDOWN_UNINSTALL
            chmod +x ${uninstallPath}
            setsid ${uninstallPath} </dev/null >/dev/null 2>&1 &
        fi

        exit 0
    '';

    cleanupFiles = map (entry: {
        inherit entry;
        dirId = entryDirId entry;
        file = pkgs.writeShellScript "nix-teardown-${slug}-${entryDirId entry}-cleanup" entry.cleanup;
    }) cfg.entries;

    entryActivation = lib.concatStringsSep "\n" (map (e: ''
        mkdir -p ${entriesDir}/${e.dirId}
        printf '%s' ${lib.escapeShellArg e.entry.id} > ${entriesDir}/${e.dirId}/id
        printf '%s' "$systemConfig" > ${entriesDir}/${e.dirId}/systemConfig
        cp -f ${e.file} ${entriesDir}/${e.dirId}/cleanup.sh
        chmod +x ${entriesDir}/${e.dirId}/cleanup.sh
    '') cleanupFiles);
in
{
    options.services.${namespace} = {
        entries = lib.mkOption {
            type = lib.types.listOf (lib.types.submodule {
                options = {
                    id = lib.mkOption {
                        type = lib.types.str;
                        description = ''
                            globally unique identifier for this entry. recommended
                            convention: your flake's url, e.g. "github:user/repo".
                            for multiple entries from the same flake, append a suffix
                            (e.g. "github:user/repo#purpose"). on-disk identity is a
                            short hash of this string, so the same id always maps to
                            the same on-disk directory across rebuilds.
                        '';
                    };
                    cleanup = lib.mkOption {
                        type = lib.types.str;
                        description = "bash cleanup script. runs as root.";
                    };
                };
            });
            default = [];
            description = ''
                cleanup entries. consumers should generally use the mkDarwinEntry
                helper from the flake's top-level outputs rather than touching this
                option directly.
            '';
        };
    };

    config = {
        system.activationScripts."nix-teardown-${slug}".text = ''
            set -eu

            mkdir -p ${instanceDir}
            mkdir -p ${entriesDir}

            ${entryActivation}

            mkdir -p ${selfEntryDir}
            printf '%s' "$systemConfig" > ${selfEntryDir}/systemConfig

            cp -f ${watcherFile} ${watcherPath}
            chmod +x ${watcherPath}

            cp -f ${plistFile} ${daemonPlist}
            chmod 644 ${daemonPlist}
            chown root:wheel ${daemonPlist}

            launchctl bootout system ${daemonPlist} 2>/dev/null || true
            launchctl bootstrap system ${daemonPlist}
        '';
    };
}
