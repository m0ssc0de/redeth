{ pkgs ? import <nixpkgs> {} }:

pkgs.mkShell {
  buildInputs = with pkgs; [
    google-cloud-sdk
    bashInteractive
    python38Packages.pip
    redis
  ];

  shellHook = ''
    # This command runs every time you enter the shell
    echo "Creating a Python virtual environment and installing ethereum-etl==2.1.1"
    python -m venv .env
    source .env/bin/activate
    pip install ethereum-etl==2.1.1
  '';
}