// What the doorbell camera "sees": a porch at dusk, drawn by hand in SVG (no generated imagery).
// A warm wall lamp, a green door, a parcel on the mat and a visitor's silhouette under the porch light.
export const Porch = ({width, height, t = 1}: {width: number; height: number; t?: number}) => (
  <svg width={width} height={height} viewBox="0 0 160 90" preserveAspectRatio="xMidYMid slice" style={{display: 'block'}}>
    <defs>
      <linearGradient id="porch-sky" x1="0" y1="0" x2="0" y2="1">
        <stop offset="0" stopColor="#2B2F4E" />
        <stop offset="1" stopColor="#7A5560" />
      </linearGradient>
      <linearGradient id="porch-wall" x1="0" y1="0" x2="0" y2="1">
        <stop offset="0" stopColor="#B8876A" />
        <stop offset="1" stopColor="#6E4A3A" />
      </linearGradient>
      <radialGradient id="porch-glow" cx="0.5" cy="0.5" r="0.5">
        <stop offset="0" stopColor="#FFD9A0" stopOpacity="0.95" />
        <stop offset="0.35" stopColor="#F2A85A" stopOpacity="0.45" />
        <stop offset="1" stopColor="#F2A85A" stopOpacity="0" />
      </radialGradient>
      <linearGradient id="porch-door" x1="0" y1="0" x2="1" y2="0">
        <stop offset="0" stopColor="#2F4A3E" />
        <stop offset="1" stopColor="#3D5C4C" />
      </linearGradient>
    </defs>
    <rect width="160" height="90" fill="url(#porch-sky)" />
    {/* Wall and eaves */}
    <rect x="0" y="14" width="160" height="76" fill="url(#porch-wall)" />
    <rect x="0" y="10" width="160" height="6" fill="#3A2A24" />
    {/* Siding lines */}
    {[24, 34, 44, 54, 64, 74].map((y) => (
      <line key={y} x1="0" x2="160" y1={y} y2={y} stroke="#5A3C30" strokeOpacity="0.35" strokeWidth="0.6" />
    ))}
    {/* Door with frame, panels and brass knob */}
    <rect x="58" y="24" width="38" height="58" fill="#E8DCC8" />
    <rect x="61" y="27" width="32" height="55" fill="url(#porch-door)" />
    <rect x="65" y="31" width="10" height="20" rx="1" fill="none" stroke="#24382F" strokeWidth="1" />
    <rect x="79" y="31" width="10" height="20" rx="1" fill="none" stroke="#24382F" strokeWidth="1" />
    <rect x="65" y="56" width="24" height="20" rx="1" fill="none" stroke="#24382F" strokeWidth="1" />
    <circle cx="89" cy="56" r="1.4" fill="#E9B65A" />
    {/* House number */}
    <text x="44" y="40" fontFamily="system-ui" fontSize="7" fontWeight="700" fill="#F3E3C6" opacity="0.85">12</text>
    {/* Wall lamp and its glow */}
    <circle cx="108" cy="30" r={22 * (0.9 + 0.1 * t)} fill="url(#porch-glow)" />
    <rect x="105.5" y="25" width="5" height="9" rx="1.5" fill="#FFE2B0" />
    <rect x="105" y="23.5" width="6" height="2" fill="#2A1E19" />
    {/* Step and mat */}
    <rect x="48" y="82" width="58" height="8" fill="#4B3A33" />
    <rect x="62" y="80" width="30" height="3" rx="1" fill="#8A5A3A" />
    {/* Plant pot */}
    <path d="M30 70 h12 l-2 12 h-8 z" fill="#B0603E" />
    <circle cx="33" cy="64" r="6" fill="#3E6B48" />
    <circle cx="40" cy="62" r="5" fill="#4C7D54" />
    <circle cx="36" cy="58" r="5" fill="#5B8E5F" />
    {/* Visitor: rim-lit silhouette holding a parcel */}
    <g>
      <ellipse cx="124" cy="44" rx="7" ry="8" fill="#1E1A22" />
      <path d="M110 90 C110 66 114 56 124 56 C134 56 138 66 138 90 Z" fill="#1E1A22" />
      <path d="M118 44 C118 39 121 36.5 124 36.5" stroke="#F6C27A" strokeWidth="1" fill="none" opacity="0.8" />
      <path d="M112 72 C113 63 117 58 122 57" stroke="#F6C27A" strokeWidth="1" fill="none" opacity="0.6" />
      <rect x="114" y="66" width="18" height="13" rx="1" fill="#C8955C" />
      <rect x="114" y="71" width="18" height="2.5" fill="#E6C48E" />
    </g>
    {/* Camera vignette */}
    <rect width="160" height="90" fill="none" stroke="black" strokeOpacity="0.25" strokeWidth="10" />
  </svg>
);
