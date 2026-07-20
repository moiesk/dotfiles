{ config, user, ... }:
let
  dotfiles = "${config.home.homeDirectory}/.dotfiles";
  link = path: config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/${path}";
  rootLink = path: config.lib.file.mkOutOfStoreSymlink "${dotfiles}/${path}";
in
{
  home.username = user;
  home.homeDirectory = "/Users/${user}";
  home.stateVersion = "24.11";

  home.sessionVariables = {
    EDITOR = "nvim";
    SUDO_EDITOR = "nvim";
    GDRIVE_CREDS_DIR = "$HOME/.config/mcp-gdrive";
    BUN_INSTALL = "$HOME/.bun";
  };

  home.sessionPath = [
    "$HOME/.local/bin"
    "$HOME/.bun/bin"
    "$HOME/.asdf/shims"
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

      fpath=($HOME/.asdf/completions $fpath)
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
  };
}
