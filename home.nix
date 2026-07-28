{ config, inputs, pkgs, user, ... }:
let
  dotfiles = "${config.home.homeDirectory}/.dotfiles";
  link = path: config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/${path}";
  agentHelper = name: package: entrypoint: pkgs.writeShellScriptBin name ''
    exec ${pkgs.mise}/bin/mise exec -- node \
      "$HOME/.local/share/agent-tools/node_modules/${package}/${entrypoint}" \
      "$@"
  '';
  # Activation runs this reviewed script from the store, not from the mutable
  # working tree. shellcheck runs at build time; jq/coreutils come from the store.
  materializeAgentConfigsApp = pkgs.writeShellApplication {
    name = "materialize-agent-configs";
    runtimeInputs = [ pkgs.jq pkgs.coreutils ];
    text = builtins.readFile ./scripts/materialize-agent-configs.sh;
  };
  noMistakesVersion = "1.40.2";
  noMistakes = pkgs.buildGoModule {
    pname = "no-mistakes";
    version = noMistakesVersion;
    src = inputs.no-mistakes;
    vendorHash = "sha256-NZOYxNYvt4192uqKBdKRxdgrKFvWx3585psdCnRdPSM=";
    subPackages = [ "cmd/no-mistakes" ];
    ldflags = [
      "-s"
      "-w"
      "-X github.com/kunchenguid/no-mistakes/internal/buildinfo.Version=v${noMistakesVersion}"
    ];
  };
  mattSkillGroups = [ "engineering" "productivity" "misc" "personal" ];
  mattSkillPathsForGroup = group:
    let
      groupRoot = "${inputs.matt-pocock-skills}/skills/${group}";
      entries = builtins.readDir groupRoot;
      skillNames = builtins.filter (name:
        entries.${name} == "directory" &&
        builtins.pathExists "${groupRoot}/${name}/SKILL.md"
      ) (builtins.attrNames entries);
    in
    map (name: "${group}/${name}") skillNames;
  mattSkillPaths = pkgs.lib.concatMap mattSkillPathsForGroup mattSkillGroups;
  packageSkill = name: source: {
    inherit name source;
  };
  renamedPackageSkill = name: declaredName: source: packageSkill name (pkgs.runCommand "${name}-skill" { } ''
    mkdir -p "$out"
    cp -R ${source}/. "$out"
    substituteInPlace "$out/SKILL.md" \
      --replace-fail "name: ${declaredName}" "name: ${name}"
  '');
  managedSkills = map (path: {
    name = builtins.baseNameOf path;
    source = "${inputs.matt-pocock-skills}/skills/${path}";
  }) mattSkillPaths ++ [
    (packageSkill "chrome-devtools-axi" "${inputs.chrome-devtools-axi}/skills/chrome-devtools-axi")
    (packageSkill "gh-axi" "${inputs.gh-axi}/skills/gh-axi")
    (renamedPackageSkill "lavish-axi" "lavish" "${inputs.lavish-axi}/skills/lavish")
    (packageSkill "quota-axi" "${inputs.quota-axi}/skills/quota-axi")
    (packageSkill "tasks-axi" "${inputs.tasks-axi}/skills/tasks-axi")
  ];
  canonicalSkillFiles = builtins.listToAttrs (map (skill: {
    name = ".agents/skills/${skill.name}";
    value.source = skill.source;
  }) managedSkills);
  harnessSkillFiles = builtins.listToAttrs (pkgs.lib.concatMap (skill: map (prefix: {
    name = "${prefix}/${skill.name}";
    value.source = config.lib.file.mkOutOfStoreSymlink
      "${config.home.homeDirectory}/.agents/skills/${skill.name}";
  }) [ ".claude/skills" ".pi/agent/skills" ]) managedSkills);
in
{
  home.username = user;
  home.homeDirectory = "/Users/${user}";
  home.stateVersion = "24.11";

  # Home Manager 26.05 currently generates its manpage through an options.json
  # derivation that drops Nix store-path context and warns on every rebuild.
  manual.manpages.enable = false;

  home.packages = with pkgs; [
    android-tools
    btop
    bun
    colima
    docker-client
    doctl
    eza
    fd
    ffmpeg
    fx
    fzf
    gh
    gnupg
    go
    httpie
    jq
    jujutsu
    lazydocker
    lazygit
    lazyjj
    llmfit
    macmon
    markdownlint-cli2
    neovim
    noMistakes
    opencode
    p7zip
    pinentry_mac
    ripgrep
    silver-searcher
    smartmontools
    starship
    tabiew
    tmux
    inputs.treehouse.packages.${pkgs.stdenv.hostPlatform.system}.default
    uv
    wget
    (agentHelper "pi" "@earendil-works/pi-coding-agent" "dist/cli.js")
    (agentHelper "gh-axi" "gh-axi" "dist/bin/gh-axi.js")
    (agentHelper "chrome-devtools-axi" "chrome-devtools-axi" "dist/bin/chrome-devtools-axi.js")
    (agentHelper "lavish-axi" "lavish-axi" "dist/cli.mjs")
    (agentHelper "quota-axi" "quota-axi" "dist/bin/quota-axi.js")
    (agentHelper "tasks-axi" "tasks-axi" "dist/bin/tasks-axi.js")
  ];

  home.sessionVariables = {
    EDITOR = "nvim";
    SUDO_EDITOR = "nvim";
    GDRIVE_CREDS_DIR = "$HOME/.config/mcp-gdrive";
    BUN_INSTALL = "$HOME/.bun";
    # Nix owns the binary; self-update cannot replace a store path.
    NO_MISTAKES_NO_UPDATE_CHECK = "1";
  };

  home.sessionPath = [
    "$HOME/.local/bin"
    "$HOME/.bun/bin"
    "$HOME/.cache/lm-studio/bin"
    "$HOME/.antigravity/antigravity/bin"
  ];

  programs.zsh = {
    enable = true;
    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;
    history = {
      path = "${config.home.homeDirectory}/.history";
      size = 10000;
      save = 50000;
    };
    initContent = ''
      eval "$(starship init zsh)"

      autoload -Uz compinit && compinit

      if command -v fzf >/dev/null 2>&1; then
        source <(fzf --zsh)
      fi

      autoload -U up-line-or-beginning-search
      autoload -U down-line-or-beginning-search
      zle -N up-line-or-beginning-search
      zle -N down-line-or-beginning-search
      bindkey "^[[A" up-line-or-beginning-search
      bindkey "^[[B" down-line-or-beginning-search

      export GPG_TTY=$(tty)

      [ -s "$HOME/.bun/_bun" ] && source "$HOME/.bun/_bun"
    '';
  };

  # mise owns the pinned language runtimes and activates them in new shells.
  programs.mise = {
    enable = true;
    enableZshIntegration = true;
    globalConfig = {
      settings.ruby.compile = false;
      tools = {
        node = "24.18.0";
        ruby = "4.0.6";
      };
    };
  };

  programs.git = {
    enable = true;
    lfs.enable = true;
    # Repository build output belongs in each project's own .gitignore.
    ignores = [
      ".DS_Store"
      "*.sw[nop]"
      ".idea/"
      ".bundle/"
      ".byebug_history"
      ".env"
      "/tags"
      "rerun.txt"
      "**/.beads/"
      "**/.claude/settings.local.json"
    ];
    settings = {
      init.defaultBranch = "main";
      push.default = "current";
      color.ui = "auto";
      alias = {
        aa = "add --all";
        ap = "add --patch";
        branches = "for-each-ref --sort=-committerdate --format=\"%(color:blue)%(authordate:relative)%09%(color:red)%(authorname)%09%(color:white)%(color:bold)%(refname:short)\" refs/remotes";
        ci = "commit -v";
        co = "checkout";
        pf = "push --force-with-lease";
        st = "status";
        br = "branch";
        type = "cat-file -t";
        dump = "cat-file -p";
        alias = "config --get-regexp ^alias\\.";
        hist = "log --pretty=format:\"%h %ad | %s%d [%an]\" --graph --date=short";
        ls = "log -n 16 --pretty=format:\"%C(yellow)%h %C(cyan)[%cn] %C(reset)%s %C(red)%d\" --decorate";
        ll = "log -n 6 --pretty=format:\"%C(yellow)%h %C(cyan)[%cn] %C(reset)%s %C(red)%ad\" --decorate --date=short --stat";
        tree = "log -n 16 --pretty=format:\"%C(yellow)%h %C(cyan)[%cn] %C(reset)%s %C(red)%d\" --decorate --graph";
        assume = "update-index --assume-unchanged";
        unassume = "update-index --no-assume-unchanged";
        assumed = "!git ls-files -v | grep '^h' | cut -c 3-";
      };
      core.autocrlf = "input";
      merge.ff = "only";
      fetch.prune = true;
      rebase.autosquash = true;
      diff.colorMoved = "zebra";
      # ADOPTERS: change these to your own name and email before rebuilding, so
      # you do not author commits under the repo owner's identity. Unlike the
      # flake `user`, bootstrap.sh does not rewrite these automatically.
      # useConfigOnly = true keeps Git from falling back to a guessed
      # user.name/user.email, so a blank here fails loudly rather than silently
      # committing under the wrong identity.
      user = {
        name = "Moises Eskinazi";
        email = "moiesk@gmail.com";
        useConfigOnly = true;
      };
    };
  };

  home.file = {
    ".config/nvim".source = link ".config/nvim";

    ".config/ghostty/themes/Catppuccin Latte Herdr".source = link ".config/ghostty/themes/Catppuccin Latte Herdr";
    "Library/Application Support/com.mitchellh.ghostty/config".source = link "Library/Application Support/com.mitchellh.ghostty/config";

    ".config/herdr/config.toml".source = link ".config/herdr/config.toml";

    ".claude/hooks/statusline.js".source = link ".claude/hooks/statusline.js";

    ".config/opencode/.npmrc".source = link ".config/opencode/.npmrc";
    ".config/opencode/package.json".source = link ".config/opencode/package.json";
    ".config/opencode/package-lock.json".source = link ".config/opencode/package-lock.json";

    ".markdownlint-cli2.jsonc".source = link ".markdownlint-cli2.jsonc";
  } // canonicalSkillFiles // harnessSkillFiles;

  # Harnesses write selections and state back to their user configuration.
  # Materialize ordinary files after the old Home Manager links are removed,
  # preserving existing local keys while reapplying tracked portable defaults.
  #
  # Activation-time code runs from the store (reviewed, immutable); runtime
  # data/config stays out-of-store in ~/.dotfiles. Do not "simplify" this back
  # to running the script straight from the mutable working tree.
  home.activation.materializeAgentConfigs =
    config.lib.dag.entryAfter [ "linkGeneration" ] ''
      ${materializeAgentConfigsApp}/bin/materialize-agent-configs "${dotfiles}"
    '';
}
