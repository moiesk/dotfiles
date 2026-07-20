#!/usr/bin/env node
// Statusline: folder · git branch · model · context (tokens + %)
// Context % is scaled so that 80% of the real window shows as 100%,
// giving a heads-up to /compact before autocompaction kicks in.

const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');

let input = '';
process.stdin.setEncoding('utf8');
process.stdin.on('data', chunk => (input += chunk));
process.stdin.on('end', () => {
  try {
    const data = JSON.parse(input);

    const dir = data.workspace?.current_dir || data.cwd || process.cwd();
    const model = data.model?.display_name || 'Claude';
    const modelId = data.model?.id || '';
    const costUsd = data.cost?.total_cost_usd;

    // --- current folder ---
    const folder = path.basename(dir) || dir;

    // --- git branch (if any) ---
    let branch = '';
    try {
      const b = execSync('git rev-parse --abbrev-ref HEAD 2>/dev/null', {
        cwd: dir,
        encoding: 'utf8',
        stdio: ['ignore', 'pipe', 'ignore'],
      }).trim();
      if (b) branch = b;
    } catch (e) {}

    // --- context window size ---
    // 1M models report "[1m]" in the id (or already exceed 200k tokens).
    const isOneM = /\[?1m\]?/i.test(modelId) || data.exceeds_200k_tokens === true;
    const limit = isOneM ? 1_000_000 : 200_000;

    // --- used context tokens (from the latest usage in the transcript) ---
    let usedTokens = null;
    const tp = data.transcript_path;
    if (tp && fs.existsSync(tp)) {
      try {
        const lines = fs.readFileSync(tp, 'utf8').trim().split('\n');
        for (let i = lines.length - 1; i >= 0; i--) {
          let o;
          try { o = JSON.parse(lines[i]); } catch (e) { continue; }
          const u = o?.message?.usage;
          if (u) {
            usedTokens =
              (u.input_tokens || 0) +
              (u.cache_creation_input_tokens || 0) +
              (u.cache_read_input_tokens || 0);
            break;
          }
        }
      } catch (e) {}
    }

    // --- build context segment ---
    let ctx = '';
    if (usedTokens != null) {
      // Scale: 80% of the real window == 100% displayed.
      const scaledPct = Math.min(100, Math.round((usedTokens / (limit * 0.8)) * 100));

      const filled = Math.max(0, Math.min(10, Math.floor(scaledPct / 10)));
      const bar = '█'.repeat(filled) + '░'.repeat(10 - filled);

      const tokStr =
        usedTokens >= 1000 ? (usedTokens / 1000).toFixed(1) + 'k' : String(usedTokens);

      let color;
      if (scaledPct < 63) color = '\x1b[32m';          // green
      else if (scaledPct < 81) color = '\x1b[33m';      // yellow
      else if (scaledPct < 95) color = '\x1b[38;5;208m'; // orange
      else color = '\x1b[5;31m';                         // blinking red

      const skull = scaledPct >= 95 ? '💀 ' : '';
      ctx = `${color}${skull}${bar} ${tokStr} ${scaledPct}%\x1b[0m`;
    }

    // --- assemble ---
    const parts = [];
    parts.push(`\x1b[1;36m ${folder}\x1b[0m`);            // folder (cyan, bold)
    if (branch) parts.push(`\x1b[35m ${branch}\x1b[0m`);  // branch (magenta)
    parts.push(`\x1b[2m${model}\x1b[0m`);                        // model (dim)
    if (typeof costUsd === 'number') {                           // session cost (green)
      parts.push(`\x1b[32m$${costUsd.toFixed(2)}\x1b[0m`);
    }
    if (ctx) parts.push(ctx);                                    // context

    process.stdout.write(parts.join('  \x1b[2m│\x1b[0m  '));
  } catch (e) {
    // Silent fail keeps the prompt usable.
  }
});
