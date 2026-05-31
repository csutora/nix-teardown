# nix-teardown-test

## usage

add as an input:

```nix
inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    nix-darwin = {
        url = "github:nix-darwin/nix-darwin/master";
        inputs.nixpkgs.follows = "nixpkgs";
    };

    # ...

    nix-teardown-test = {
        url = "github:csutora/nix-teardown?dir=examples/test";
        inputs.nixpkgs.follows = "nixpkgs";
    };
};
```

and in your flake outputs:

```nix
outputs = inputs@{ self, nixpkgs, nix-darwin, nix-teardown-test }: {
    darwinConfigurations."hostname" = nix-darwin.lib.darwinSystem {
        modules = [
            # ...
            nix-teardown-test.darwinModules.default
        ];
        # ...
    };
};
```

on rebuild, the example installs two markers and exposes a verifier:

```sh
nix run --no-write-lock-file 'github:csutora/nix-teardown?dir=examples/test#verify' -- installed
# remove the example from your config, rebuild
nix run --no-write-lock-file 'github:csutora/nix-teardown?dir=examples/test#verify' -- cleaned
```
