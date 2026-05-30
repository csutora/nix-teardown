{
    description = "declarative module-removal cleanup hooks for nix";

    inputs = {
        nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    };

    outputs = { self, nixpkgs }:
    let
        slug = builtins.substring 0 8 (builtins.hashString "sha256" self.outPath);
        namespace = "nixTeardown_${slug}";
    in {
        inherit slug namespace;

        darwinModules.default = import ./darwin.nix { inherit namespace slug; };

        mkDarwinEntry = id: cleanup: { ... }: {
            imports = [ self.darwinModules.default ];
            config.services.${namespace}.entries = [
                { inherit id cleanup; }
            ];
        };
    };
}
