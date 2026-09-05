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

    infra_venv="infra/.venv"
    infra_requirements="infra/requirements.txt"
    infra_stamp="$infra_venv/.requirements.stamp"

    if [ -f "$infra_requirements" ]; then
      infra_requirements_hash="$(sha256sum "$infra_requirements" | cut -d ' ' -f1)"

      if [ ! -x "$infra_venv/bin/python3" ] || ! grep -qx "home = ${pkgs.python3}/bin" "$infra_venv/pyvenv.cfg" 2>/dev/null; then
        ${pkgs.python3}/bin/python3 -m venv --clear "$infra_venv"
      fi

      if [ ! -f "$infra_stamp" ] || [ "$(cat "$infra_stamp")" != "$infra_requirements_hash" ]; then
        ${pkgs.lib.getExe pkgs.uv} pip install --python "$infra_venv/bin/python3" -r "$infra_requirements"
        printf '%s' "$infra_requirements_hash" > "$infra_stamp"
      fi

      export VIRTUAL_ENV="$PWD/$infra_venv"
      export PATH="$VIRTUAL_ENV/bin:$PATH"
    fi
  '';
}
