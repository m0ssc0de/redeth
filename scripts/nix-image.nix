{ pkgs ? import <nixpkgs> {} }:

pkgs.dockerTools.buildImage {
  name = "my-image";
  tag = "latest";
  contents = [
    pkgs.google-cloud-sdk
    pkgs.redis
    pkgs.kubectl
    pkgs.curl
    pkgs.jq
    pkgs.bashInteractive
  ];
  config = {
    Cmd = [ "/bin/bash" ];
  };
}
