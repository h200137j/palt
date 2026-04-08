/**
 * theme.ts — PALT Material UI Theme
 *
 * A Google-style Material Design 3 theme with yellow as the primary brand color.
 * Follows the exact colour roles from the MD3 spec:
 *   Primary    → Google Yellow (#FBBC04)
 *   On Primary → near-black for WCAG AA contrast
 *   Surface    → white / near-black (light / dark)
 */
import { createTheme, alpha } from '@mui/material/styles';

// ─── Palette tokens ───────────────────────────────────────────────────────────

const GOOGLE_YELLOW = '#FBBC04';
const GOOGLE_YELLOW_DARK = '#F9A825'; // pressed / hover state
const GOOGLE_YELLOW_CONTAINER = '#FFF8E1'; // tinted surface in light mode
const ON_PRIMARY = '#1A1400'; // near-black → passes WCAG AA on yellow

// ─── Theme definition ─────────────────────────────────────────────────────────

const theme = createTheme({
  palette: {
    mode: 'light',

    primary: {
      main: GOOGLE_YELLOW,
      dark: GOOGLE_YELLOW_DARK,
      contrastText: ON_PRIMARY,
    },

    secondary: {
      main: '#1A73E8', // Google Blue — used for accents / links
      contrastText: '#FFFFFF',
    },

    background: {
      default: '#F8F9FA', // Google's light grey page background
      paper: '#FFFFFF',
    },

    text: {
      primary: '#202124',   // Google's near-black body text
      secondary: '#5F6368', // Google's muted grey
    },

    divider: '#E0E0E0',

    error: {
      main: '#D93025', // Google Red
    },

    success: {
      main: '#0F9D58', // Google Green
    },
  },

  // ─── Typography ───────────────────────────────────────────────────────────

  typography: {
    fontFamily: '"Roboto", "Helvetica Neue", Arial, sans-serif',

    // Display / hero text
    h1: { fontSize: '2.125rem', fontWeight: 400, letterSpacing: '-0.5px' },
    h2: { fontSize: '1.5rem',   fontWeight: 400 },
    h3: { fontSize: '1.25rem',  fontWeight: 500 },

    // Card / section headings
    h4: { fontSize: '1.125rem', fontWeight: 500 },
    h5: { fontSize: '1rem',     fontWeight: 500 },
    h6: { fontSize: '0.875rem', fontWeight: 500, letterSpacing: '0.15px' },

    subtitle1: { fontSize: '1rem',     fontWeight: 400, letterSpacing: '0.15px' },
    subtitle2: { fontSize: '0.875rem', fontWeight: 500, letterSpacing: '0.1px' },

    body1: { fontSize: '1rem',     letterSpacing: '0.5px' },
    body2: { fontSize: '0.875rem', letterSpacing: '0.25px' },

    caption: { fontSize: '0.75rem',  letterSpacing: '0.4px' },
    overline: { fontSize: '0.625rem', letterSpacing: '1.5px', textTransform: 'uppercase' },

    button: { fontWeight: 500, letterSpacing: '1.25px', textTransform: 'uppercase' },
  },

  // ─── Shape ────────────────────────────────────────────────────────────────

  shape: {
    borderRadius: 12, // MD3 uses more rounded shapes than MD2
  },

  // ─── Component overrides ──────────────────────────────────────────────────

  components: {
    // ── AppBar ──────────────────────────────────────────────────────────────
    MuiAppBar: {
      styleOverrides: {
        root: {
          // Google-style top app bar: white with a subtle shadow
          backgroundColor: '#FFFFFF',
          color: '#202124',
          boxShadow: '0 1px 3px rgba(0,0,0,0.12), 0 1px 2px rgba(0,0,0,0.08)',
        },
      },
    },

    // ── Toolbar ─────────────────────────────────────────────────────────────
    MuiToolbar: {
      styleOverrides: {
        root: { minHeight: 64 },
      },
    },

    // ── Buttons ─────────────────────────────────────────────────────────────
    MuiButton: {
      defaultProps: { disableElevation: true },
      styleOverrides: {
        root: { borderRadius: 24, padding: '8px 24px', fontWeight: 500 },
        containedPrimary: {
          backgroundColor: GOOGLE_YELLOW,
          color: ON_PRIMARY,
          '&:hover': { backgroundColor: GOOGLE_YELLOW_DARK },
        },
      },
    },

    MuiFab: {
      styleOverrides: {
        root: { boxShadow: '0 3px 6px rgba(0,0,0,0.16)' },
      },
    },

    // ── Cards ───────────────────────────────────────────────────────────────
    MuiCard: {
      defaultProps: { elevation: 0 },
      styleOverrides: {
        root: {
          border: '1px solid #E0E0E0',
          borderRadius: 16,
          transition: 'box-shadow 200ms ease, transform 200ms ease',
          '&:hover': {
            boxShadow: '0 4px 16px rgba(0,0,0,0.12)',
            transform: 'translateY(-1px)',
          },
        },
      },
    },

    // ── Chip ────────────────────────────────────────────────────────────────
    MuiChip: {
      styleOverrides: {
        root: { fontWeight: 500 },
        colorPrimary: {
          backgroundColor: GOOGLE_YELLOW_CONTAINER,
          color: '#7C5700',
          '& .MuiChip-icon': { color: '#7C5700' },
        },
      },
    },

    // ── List items ──────────────────────────────────────────────────────────
    MuiListItemButton: {
      styleOverrides: {
        root: {
          borderRadius: 12,
          '&.Mui-selected': {
            backgroundColor: alpha(GOOGLE_YELLOW, 0.15),
            '&:hover': { backgroundColor: alpha(GOOGLE_YELLOW, 0.22) },
          },
        },
      },
    },

    // ── Tooltip ─────────────────────────────────────────────────────────────
    MuiTooltip: {
      defaultProps: { arrow: true },
      styleOverrides: {
        tooltip: {
          backgroundColor: '#202124',
          fontSize: '0.75rem',
          borderRadius: 8,
        },
      },
    },

    // ── TextField ───────────────────────────────────────────────────────────
    MuiTextField: {
      defaultProps: { variant: 'outlined', size: 'small' },
    },

    // ── Paper / surfaces ────────────────────────────────────────────────────
    MuiPaper: {
      styleOverrides: {
        rounded: { borderRadius: 16 },
      },
    },
  },
});

export default theme;
