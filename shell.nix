{ pkgs ? import <nixpkgs> { } }:
let
  sitter = (pkgs.tree-sitter.withPlugins (p: builtins.attrValues p));
in
pkgs.mkShell {
  # nativeBuildInputs is usually what you want -- tools you need to run
  nativeBuildInputs = [
    sitter
  ];
}
