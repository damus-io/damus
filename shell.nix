{ pkgs ? import <nixpkgs> {} }:
with pkgs;
mkShell {
  buildInputs = with python3Packages; [ Mako requests wabt todo-txt-cli ];
}
