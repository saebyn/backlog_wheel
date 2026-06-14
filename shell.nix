{ pkgs ? import <nixpkgs> {}}:

pkgs.mkShellNoCC {
  packages = with pkgs; [
    beam28Packages.elixir
    beam28Packages.erlang
    sqlite
    inotify-tools
    git
    gitleaks
    pre-commit
    tailwindcss_4
    watchman

    # Deployment / AWS CDK
    awscli2
    python3
    uv
    jq
    aws-cdk-cli
  ];

  shellHook = ''
    export TAILWINDCSS_PATH="${pkgs.lib.getExe pkgs.tailwindcss_4}"
  '';
}
