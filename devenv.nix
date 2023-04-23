{ pkgs, ... }:

{
  packages = with pkgs; [
    hugo
    openring
    go
  ];
}
