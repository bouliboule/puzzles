// Per-puzzle metadata: default parameters, touch input modes, help.
// Button names map to the midend's LEFT / RIGHT / MIDDLE buttons.

export const PUZZLES = {
  loopy: {
    title: 'Loopy',
    tagline: 'Draw one loop around the numbers',
    defaultParams: '15x22t0dh',
    stylus: true,
    modes: [
      { id: 'line', label: 'Line', button: 'left' },
      { id: 'cross', label: 'Cross', button: 'right' },
    ],
    help: `
      <p>Draw a single closed loop along the grid lines. Each number says how many of the four edges around its square are part of the loop.</p>
      <h3>Controls</h3>
      <ul>
        <li><b>Tap or click an edge</b> to draw a line. Tap again to mark it with a cross; a third tap clears it.</li>
        <li><b>Long press</b> or <b>right-click</b> an empty edge to cross it directly. Cross mode makes that the default tap.</li>
        <li>Tip: turn on <i>Auto-follow</i> in the puzzle settings to draw whole forced paths with one tap.</li>
      </ul>`,
  },
  bridges: {
    title: 'Bridges',
    tagline: 'Connect every island',
    defaultParams: '15x22i30e10m2d2',
    stylus: true,
    modes: [
      { id: 'bridge', label: 'Bridge', button: 'left' },
      { id: 'block', label: 'Block', button: 'right' },
    ],
    extraMenu: [{ label: 'Hint', key: 'h' }],
    help: `
      <p>Connect all the islands into one network with horizontal and vertical bridges. Each island's number is how many bridges end there. At most two bridges join any pair of islands, and bridges never cross.</p>
      <h3>Controls</h3>
      <ul>
        <li><b>Drag</b> from one island towards another to add a bridge. Drag again for a double bridge, again to block the gap (no bridge allowed), and once more to clear it.</li>
        <li><b>Long press then drag</b>, <b>right-drag</b>, or Block mode toggles a block directly.</li>
        <li><b>Tap an island</b> to mark it finished (greys it out).</li>
      </ul>`,
  },
  keen: {
    title: 'Keen',
    tagline: 'Arithmetic Latin square',
    defaultParams: '6dn',
    stylus: true,
    keypad: true,
    // Applied once, before the player has saved their own settings.
    defaultPrefs: { 'Keep mouse highlight after changing a pencil mark': true },
    modes: [
      { id: 'number', label: 'Number', button: 'left' },
      { id: 'notes', label: 'Notes', button: 'right' },
    ],
    extraMenu: [{ label: 'Fill all notes', key: 'M' }],
    help: `
      <p>Fill the grid so every row and column contains each number exactly once. Each outlined cage must produce its target using the given operation (+ − × ÷). Subtraction and division cages have two cells.</p>
      <h3>Controls</h3>
      <ul>
        <li><b>Tap a cell</b>, then a number on the keypad. Tap the same cell again to switch it to notes (pencil marks); a third tap deselects it.</li>
        <li><b>Long press</b> or <b>right-click</b> a cell, or use Notes mode, to go straight to notes.</li>
        <li><b>Fill all notes</b> (in the menu) puts every possible number in each empty cell.</li>
      </ul>`,
  },
  pattern: {
    title: 'Pattern',
    tagline: 'Nonogram picture logic',
    defaultParams: '20x20',
    stylus: true,
    modes: [
      { id: 'fill', label: 'Fill', button: 'left' },
      { id: 'dot', label: 'Dot', button: 'right' },
      { id: 'clear', label: 'Clear', button: 'middle' },
    ],
    help: `
      <p>Shade squares to reveal a picture. The numbers beside each row and above each column list the lengths of the runs of shaded squares in that line, in order.</p>
      <h3>Controls</h3>
      <ul>
        <li><b>Tap</b> a square to fill it, again to mark it with a dot (definitely empty), and a third time to clear it.</li>
        <li><b>Drag</b> applies the first square's next state along a straight line.</li>
        <li><b>Long press</b> or <b>right-click</b> an empty square to dot it directly. Dot and Clear modes are also available.</li>
      </ul>`,
  },
  pearl: {
    title: 'Pearl',
    tagline: 'Thread a loop through the pearls',
    defaultParams: '10x10dt',
    stylus: true,
    modes: [
      { id: 'line', label: 'Line', button: 'left' },
      { id: 'cross', label: 'Cross', button: 'right' },
    ],
    extraMenu: [{ label: 'Hint', key: 'h' }],
    help: `
      <p>Draw a single closed loop through cell centres, moving horizontally and vertically. The loop must pass through every pearl.</p>
      <ul>
        <li><b>Black pearl:</b> the loop turns on it, and goes straight through the cells on both sides.</li>
        <li><b>White pearl:</b> the loop goes straight through it, and turns in at least one of the cells either side.</li>
      </ul>
      <h3>Controls</h3>
      <ul>
        <li><b>Drag</b> across cells to draw the loop; dragging back over a line erases it.</li>
        <li><b>Tap an edge</b> between two cells to draw a line there, again to cross it, and a third time to clear it.</li>
        <li><b>Long press</b> or <b>right-click</b> an edge, or use Cross mode, to cross it directly.</li>
      </ul>`,
  },
  slant: {
    title: 'Slant',
    tagline: 'Fill every square with a diagonal',
    defaultParams: '8x8dh',
    stylus: true,
    modes: [
      { id: 'back', label: '╲ first', button: 'left' },
      { id: 'fwd', label: '╱ first', button: 'right' },
    ],
    help: `
      <p>Draw a diagonal line in every square. Each numbered dot says how many lines meet at it, and the lines must never form a closed loop.</p>
      <h3>Controls</h3>
      <ul>
        <li><b>Tap</b> a square to cycle ╲ → ╱ → blank.</li>
        <li><b>Long press</b> or <b>right-click</b> cycles the other way (╱ first), as does the ╱ first mode.</li>
      </ul>`,
  },
};

export const ORDER = ['loopy', 'bridges', 'keen', 'pattern', 'pearl', 'slant'];

// Small SVG icons for the home screen. Use currentColor.
export const ICONS = {
  loopy: `<svg viewBox="0 0 48 48" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round">
    <g fill="currentColor" stroke="none">${[6, 18, 30, 42].map(y => [6, 18, 30, 42].map(x => `<circle cx="${x}" cy="${y}" r="1.6"/>`).join('')).join('')}</g>
    <path d="M6 6H30V18H42V42H18V30H6Z" stroke-width="3.2"/>
    <text x="24" y="28.5" font-size="11" font-family="system-ui, sans-serif" font-weight="600" text-anchor="middle" fill="currentColor" stroke="none">3</text></svg>`,
  bridges: `<svg viewBox="0 0 48 48" fill="none" stroke="currentColor">
    <path d="M14 10H34M14 14H34M10 14V34M38 14V34" stroke-width="2.4"/>
    <g stroke-width="2.4" fill="var(--icon-bg)"><circle cx="10" cy="10" r="6.5"/><circle cx="38" cy="10" r="6.5"/><circle cx="10" cy="38" r="6.5"/><circle cx="38" cy="38" r="6.5"/></g>
    <g font-size="8.5" font-family="system-ui, sans-serif" font-weight="600" text-anchor="middle" fill="currentColor" stroke="none"><text x="10" y="13">3</text><text x="38" y="13">3</text><text x="10" y="41">1</text><text x="38" y="41">1</text></g></svg>`,
  keen: `<svg viewBox="0 0 48 48" fill="none" stroke="currentColor">
    <rect x="5" y="5" width="38" height="38" stroke-width="1.2"/>
    <path d="M17.7 5V43M30.3 5V43M5 17.7H43M5 30.3H43" stroke-width="0.8"/>
    <path d="M5 17.7H30.3V5M17.7 17.7V43M30.3 30.3H43" stroke-width="3"/>
    <rect x="5" y="5" width="38" height="38" stroke-width="3"/>
    <g font-family="system-ui, sans-serif" font-weight="600" fill="currentColor" stroke="none"><text x="7.5" y="11.5" font-size="6">6×</text><text x="11.4" y="38.5" font-size="10" text-anchor="middle">2</text><text x="36.6" y="38.5" font-size="10" text-anchor="middle">3</text></g></svg>`,
  pattern: `<svg viewBox="0 0 48 48" fill="currentColor" stroke="none">
    ${['0110', '1111', '1001', '0110'].map((row, y) => [...row].map((c, x) => c === '1' ? `<rect x="${14 + x * 8.5}" y="${14 + y * 8.5}" width="7.5" height="7.5"/>` : '').join('')).join('')}
    <g font-size="6" font-family="system-ui, sans-serif" font-weight="600" text-anchor="middle"><text x="18" y="10">1</text><text x="26.5" y="10">3</text><text x="35" y="10">3</text><text x="43.5" y="10">1</text>
    <text x="8" y="21">2</text><text x="8" y="29.5">4</text><text x="8" y="38">1 1</text><text x="8" y="46.5">2</text></g></svg>`,
  pearl: `<svg viewBox="0 0 48 48" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round">
    <path d="M10 10H38V24H24V38H10Z" stroke-width="3.2"/>
    <circle cx="10" cy="10" r="5" fill="currentColor" stroke="none"/>
    <circle cx="24" cy="10" r="5" fill="var(--icon-bg)" stroke-width="2.4"/>
    <circle cx="10" cy="24" r="5" fill="var(--icon-bg)" stroke-width="2.4"/>
    <circle cx="24" cy="38" r="5" fill="currentColor" stroke="none"/></svg>`,
  slant: `<svg viewBox="0 0 48 48" fill="none" stroke="currentColor" stroke-linecap="round">
    <rect x="6" y="6" width="36" height="36" stroke-width="1"/>
    <path d="M18 6V42M30 6V42M6 18H42M6 30H42" stroke-width="0.8"/>
    <path d="M6 6L18 18M18 6L30 18M42 6L30 18M6 30L18 18M30 18L18 30M30 30L42 18M6 30L18 42M30 30L18 42M30 42L42 30" stroke-width="3"/>
    <g stroke-width="1.6" fill="var(--icon-bg)"><circle cx="18" cy="18" r="4.5"/><circle cx="30" cy="30" r="4.5"/></g>
    <g font-size="6.5" font-family="system-ui, sans-serif" font-weight="600" text-anchor="middle" fill="currentColor" stroke="none"><text x="18" y="20.3">3</text><text x="30" y="32.3">2</text></g></svg>`,
};
