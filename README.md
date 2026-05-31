# nix-teardown

declarative module-removal cleanup hooks for nix

nix modules can declare what they install, but not what to clean up when removed: as soon as the module is gone, none of its code runs anymore. nix-teardown aims to be an easy solution to this. you, as a developer, can import it into your package's nix flake, and set what commands should be run when the package is uninstalled or disabled. nix-teardown handles everything in the background, and removes itself from the user's system when no package is using it anymore. end users should never even see it.

## usage

add as an input:

```nix
inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    nix-teardown = {
        url = "github:csutora/nix-teardown";
        inputs.nixpkgs.follows = "nixpkgs";
    };
};
```

and in your flake outputs:

```nix
outputs = { nixpkgs, nix-teardown, ... }: {
    darwinModules.default = { config, lib, pkgs, ... }:
    let cfg = config.services.my-app; in {
        imports = [ nix-teardown.darwinModules.default ];

        options.services.my-app = { ... };

        config = lib.mkIf cfg.enable {
            services.${nix-teardown.namespace}.entries = [
                {
                    id = "https://github.com/me/my-app";
                    cleanup = ''
                        if [ -x ${cfg.package}/bin/my-app ]; then
                            ${cfg.package}/bin/my-app shutdown || true
                        fi
                        rm -rf /var/lib/my-app
                    '';
                }
            ];
        };
    };
};
```

for cleanup scripts that don't need to read `config`, there's a shorthand that returns a ready-to-import module:

```nix
imports = [
    nix-teardown.darwinModules.default
    (nix-teardown.mkDarwinEntry "https://github.com/me/my-app" ''
        rm -rf /var/lib/my-app
    '')
];
```

cleanup runs as root.

see [`examples/test/`](examples/test) for a fully working minimal example.

### the id (important!)

`id` should be set to a globally unique value. recommended convention: your flake's url (e.g. `https://github.com/me/my-app`). for multiple entries from the same flake, append a suffix:

```nix
id = "https://github.com/me/my-app#driver-cleanup";
```

the id derives a stable on-disk directory. same id always maps to the same directory across rebuilds, so updating your cleanup script just overwrites the existing one in place.

## cleanup on disable vs cleanup on removal

inside `lib.mkIf cfg.enable`: cleanup runs on both `enable = false` and full module removal.
outside `mkIf`: cleanup runs only on full module removal.

the second is useful in rare cases where you want to keep state around when the module is disabled, but not removed.

## license

mit.
