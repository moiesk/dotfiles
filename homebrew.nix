{ ... }:
{
  homebrew = {
    enable = true;
    enableZshIntegration = true;

    # Homebrew is reserved for native macOS apps and tap-specific tools. The
    # portable CLI inventory lives in home.packages instead.
    taps = [
      {
        name = "felixkratz/formulae";
        trusted = true;
      }
      {
        name = "nikitabobko/tap";
        trusted = true;
      }
    ];

    brews = [
      # Runtime dependencies for mise's precompiled Ruby binaries.
      "gmp"
      "libyaml"
      "openssl@3"
      "readline"
      # End of Runtime dependencies for mise' precompiled Ruby binaries
      "herdr"
      "scummvm"
      {
        name = "felixkratz/formulae/borders";
        trusted = true;
      }
    ];

    casks = [
      "nikitabobko/tap/aerospace"
      "anki"
      "kunchenguid/tap/baby-menu"
      "claude-code"
      "codex"
      "comfy"
      "font-fira-code"
      "font-fira-mono"
      "font-jetbrains-mono"
      "font-jetbrains-mono-nerd-font"
      "ghostty"
      "gnucash"
      "gpgfrontend"
      "libreoffice"
      "obsidian"
      "porting-kit"
      "qlmarkdown"
      "raycast"
      "suspicious-package"
      "taskexplorer"
      "utm"
      "vlc"
      "zed"
    ];

    # Always converge casks to Homebrew's latest available version, including
    # self-updating and unversioned apps that normal upgrades may skip.
    greedyCasks = true;

    onActivation = {
      autoUpdate = true;
      upgrade = true;
      cleanup = "zap";
      extraEnv = {
        HOMEBREW_NO_ANALYTICS = "1";
        HOMEBREW_NO_ENV_HINTS = "1";
      };
    };
  };
}
