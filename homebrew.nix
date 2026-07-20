{ ... }:
{
  homebrew = {
    enable = true;
    enableZshIntegration = true;

    # A snapshot of the explicit inventory on 2026-07-20. Prune deliberately
    # in Git after the first successful migration.
    taps = [
      {
        name = "apple/apple";
        clone_target = "https://github.com/apple/homebrew-apple";
        trusted = true;
      }
      {
        name = "felixkratz/formulae";
        trusted = true;
      }
      {
        name = "nikitabobko/tap";
        trusted = true;
      }
      {
        name = "oven-sh/bun";
        trusted = true;
      }
      {
        name = "zkondor/dist";
        trusted = true;
      }
    ];

    brews = [
      "openssl@3"
      "readline"
      "apify-cli"
      "asdf"
      "asitop"
      "autoconf"
      "block-goose-cli"
      "btop"
      "cmake"
      "colima"
      "csvlens"
      "docker"
      "doctl"
      "elixir"
      "eza"
      "fastfetch"
      "fd"
      "ffmpeg"
      "fx"
      "fzf"
      "gh"
      "git-lfs"
      "gmp"
      "gnupg"
      "go"
      "gollama"
      "gum"
      "herdr"
      "htop"
      "httpie"
      "httping"
      "iftop"
      "jj"
      "jq"
      "kubernetes-cli"
      "lazydocker"
      "lazygit"
      "lazyjj"
      "libyaml"
      "llmfit"
      "macmon"
      "mactop"
      "markdownlint-cli2"
      "mole"
      "neovim"
      "nvtop"
      "opencode"
      "p7zip"
      "pango"
      "pinentry-mac"
      "pkgconf"
      "protobuf"
      "rcm"
      "ripgrep"
      "rust"
      "scummvm"
      {
        name = "sleepwatcher";
        restart_service = "changed";
      }
      "smartmontools"
      "solargraph"
      "spotify_player"
      "starship"
      "stow"
      "tabiew"
      "tmux"
      "tree"
      "uv"
      "wget"
      "zellij"
      "zenith"
      {
        name = "felixkratz/formulae/borders";
        trusted = true;
      }
      {
        name = "oven-sh/bun/bun";
        trusted = true;
      }
    ];

    casks = [
      "nikitabobko/tap/aerospace"
      "android-platform-tools"
      "anki"
      "block-goose"
      "claude-code"
      "codex"
      "comfy"
      "cursor"
      "diffusionbee"
      "font-fira-code"
      "font-fira-mono"
      "font-jetbrains-mono"
      "font-jetbrains-mono-nerd-font"
      "font-meslo-lg"
      "ghostty"
      "gimp"
      "gnucash"
      "gpgfrontend"
      "latest"
      "libreoffice"
      "mark-text"
      "miniforge"
      "obsidian"
      "porting-kit"
      "qlmarkdown"
      "raycast"
      "suspicious-package"
      "taskexplorer"
      "utm"
      "vlc"
      "zed"
      "zkondor/dist/znotch"
    ];

    vscode = [ "openai.chatgpt" ];

    onActivation = {
      autoUpdate = true;
      upgrade = true;
      cleanup = "zap";
      extraFlags = [ "--force" ];
      extraEnv = {
        HOMEBREW_NO_ANALYTICS = "1";
        HOMEBREW_NO_ENV_HINTS = "1";
      };
    };
  };
}
