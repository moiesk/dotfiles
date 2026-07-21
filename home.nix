{ config, inputs, pkgs, user, ... }:
let
  dotfiles = "${config.home.homeDirectory}/.dotfiles";
  link = path: config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/${path}";
  rootLink = path: config.lib.file.mkOutOfStoreSymlink "${dotfiles}/${path}";
  agentHelper = name: package: entrypoint: pkgs.writeShellScriptBin name ''
    exec ${pkgs.nodejs_24}/bin/node \
      "$HOME/.local/share/agent-tools/lib/node_modules/${package}/${entrypoint}" \
      "$@"
  '';
  noMistakes = pkgs.buildGoModule {
    pname = "no-mistakes";
    version = "1.40.2";
    src = inputs.no-mistakes;
    vendorHash = "sha256-NZOYxNYvt4192uqKBdKRxdgrKFvWx3585psdCnRdPSM=";
    subPackages = [ "cmd/no-mistakes" ];
    ldflags = [
      "-s"
      "-w"
      "-X github.com/kunchenguid/no-mistakes/internal/buildinfo.Version=v1.40.2"
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
  managedSkills = map (path: {
    name = builtins.baseNameOf path;
    source = "${inputs.matt-pocock-skills}/skills/${path}";
  }) mattSkillPaths ++ [
    {
      name = "lavish";
      source = "${inputs.lavish-axi}/skills/lavish";
    }
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
    git-lfs
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
    (agentHelper "gh-axi" "gh-axi" "dist/bin/gh-axi.js")
    (agentHelper "chrome-devtools-axi" "chrome-devtools-axi" "dist/bin/chrome-devtools-axi.js")
    (agentHelper "lavish-axi" "lavish-axi" "dist/cli.mjs")
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
        node = "24.6.0";
        ruby = "3.4.5";
      };
    };
  };

  programs.git = {
    enable = true;
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
      };
      core = {
        excludesfile = "~/.gitignore";
        autocrlf = "input";
      };
      merge.ff = "only";
      fetch.prune = true;
      rebase.autosquash = true;
      diff.colorMoved = "zebra";
      user = {
        name = "Moises Eskinazi";
        email = "moiesk@gmail.com";
        signingkey = "E3F28AFA0C09C844";
      };
      include.path = "~/.gitconfig.local";
    };
  };

  home.file = {
    ".config/nvim".source = link ".config/nvim";

    ".config/ghostty/themes/Catppuccin Latte Herdr".source = link ".config/ghostty/themes/Catppuccin Latte Herdr";
    "Library/Application Support/com.mitchellh.ghostty/config".source = link "Library/Application Support/com.mitchellh.ghostty/config";

    ".config/herdr/config.toml".source = link ".config/herdr/config.toml";

    ".codex/AGENTS.md".source = rootLink "AGENTS.md";
    ".codex/config.toml".source = link ".codex/config.toml";

    ".claude/CLAUDE.md".source = rootLink "AGENTS.md";
    ".claude/settings.json".source = link ".claude/settings.json";
    ".claude/hooks/statusline.js".source = link ".claude/hooks/statusline.js";

    ".pi/agent/AGENTS.md".source = rootLink "AGENTS.md";
    ".pi/agent/settings.json".source = link ".pi/agent/settings.json";
    ".pi/agent/models.json".source = link ".pi/agent/models.json";

    ".config/opencode/AGENTS.md".source = rootLink "AGENTS.md";
    ".config/opencode/package.json".source = link ".config/opencode/package.json";

    ".gitignore".source = link ".gitignore";
    ".markdownlint-cli2.jsonc".source = link ".markdownlint-cli2.jsonc";
    ".tool-versions".source = link ".tool-versions";
  } // canonicalSkillFiles // harnessSkillFiles;
}
