// Single source for the five directions: used by the index page and by each option's control panel.
window.FLOW_OPTIONS = [
  {
    id: 'meniscus',
    name: 'Meniscus',
    why: 'Liquid glass. The pop-up is a drop of frosted glass that takes its colour from whatever is behind it, so it never fights your wallpaper.',
    build: 'Easiest. Native .glassEffect(in: .capsule) on macOS 26; GlassEffectContainer morphs between states. The thinking sheen is a masked LinearGradient.',
    effort: 'Native'
  },
  {
    id: 'reticle',
    name: 'Reticle',
    why: 'Instrument HUD. Corner brackets, a live oscilloscope trace of your voice and short monospaced readouts, like a cockpit display that powers on when you speak.',
    build: 'Moderate. Shapes and Path for the frame, Canvas + TimelineView for the trace, a bundled mono font (or SF Mono). Power-on is scaleEffect keyframes.',
    effort: 'Moderate'
  },
  {
    id: 'afterglow',
    name: 'Afterglow',
    why: 'Ink capsule with a soft aurora behind it that brightens as you get louder. The glow carries state: it spins while thinking and shifts colour on done or error.',
    build: 'Moderate. AngularGradient + .blur behind a Capsule, rotation and colour driven by state. Needs a panel larger than the pill so the glow is not clipped.',
    effort: 'Moderate'
  },
  {
    id: 'filament',
    name: 'Filament',
    why: 'One hairline and one ink colour. Your voice plucks a single string; when you stop, the same line bends into a tick, a cross or a page. No colour at all.',
    build: 'Moderate. Capsule().trim() draws the outline in; the string and its morphs are one Canvas path (72 points lerped between shapes).',
    effort: 'Moderate'
  },
  {
    id: 'nucleus',
    name: 'Nucleus',
    why: 'A small pearl orb instead of a bar. It breathes with your voice, swirls while it thinks, and only opens into a label when there is something to read.',
    build: 'Most custom. Canvas blob with noise-driven radius and clipped gradient lobes, or a Metal .layerEffect shader for the pearl. Keep particles to under ~50.',
    effort: 'Custom'
  }
];
