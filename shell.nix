{ pkgs ? import <nixpkgs> {} }:
with pkgs;
mkShell {
  buildInputs = with python3Packages; [ mako requests wabt todo-txt-cli pyyaml plotly numpy ];
}
