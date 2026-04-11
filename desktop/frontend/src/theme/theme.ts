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
const GOOGLE_YELLOW_DARK = '#F9A825';
const ON_PRIMARY = '#1A1400';

const theme = createTheme({
  palette: {
    mode: 'dark',

    primary: {
      main: GOOGLE_YELLOW,
      dark: GOOGLE_YELLOW_DARK,
      contrastText: ON_PRIMARY,
    },

    secondary: {
      main: '#4285F4', // Google Blue
      contrastText: '#FFFFFF',
    },

    background: {
      default: '#0B0D11', // Midnight background
      paper: '#16191E',   // Slightly lighter for cards
    },

    text: {
      primary: '#E8EAED',
      secondary: '#9AA0A6',
    },

    divider: 'rgba(255, 255, 255, 0.08)',

    error: {
      main: '#EA4335',
    },

    success: {
      main: '#34A853',
    },
  },

  typography: {
    fontFamily: '"Outfit", "Roboto", "Helvetica Neue", Arial, sans-serif',

    h1: { fontSize: '2.5rem',   fontWeight: 900, letterSpacing: '-1px' },
    h2: { fontSize: '1.75rem',  fontWeight: 800, letterSpacing: '-0.5px' },
    h3: { fontSize: '1.5rem',   fontWeight: 700 },
    h4: { fontSize: '1.25rem',  fontWeight: 700 },
    h5: { fontSize: '1.125rem', fontWeight: 600 },
    h6: { fontSize: '1rem',     fontWeight: 600 },

    subtitle1: { fontSize: '1.125rem', fontWeight: 400 },
    subtitle2: { fontSize: '0.875rem', fontWeight: 600 },

    body1: { fontSize: '1rem',     letterSpacing: '0.2px' },
    body2: { fontSize: '0.875rem', letterSpacing: '0.1px' },

    button: { fontWeight: 700, letterSpacing: '0.5px', textTransform: 'none' },
  },

  shape: {
    borderRadius: 16,
  },

  components: {
    MuiCssBaseline: {
      styleOverrides: {
        body: {
          backgroundColor: '#0B0D11',
          backgroundImage: 'radial-gradient(circle at 50% -20%, #1A1F26 0%, #0B0D11 80%)',
          backgroundAttachment: 'fixed',
        },
      },
    },

    MuiAppBar: {
      styleOverrides: {
        root: {
          backgroundColor: alpha('#16191E', 0.8),
          backdropFilter: 'blur(12px)',
          borderBottom: '1px solid rgba(255, 255, 255, 0.08)',
          boxShadow: 'none',
        },
      },
    },

    MuiButton: {
      defaultProps: { disableElevation: true },
      styleOverrides: {
        root: { 
          borderRadius: 12, 
          padding: '10px 24px', 
          fontWeight: 700,
          transition: 'all 0.2s ease-in-out',
        },
        containedPrimary: {
          backgroundColor: GOOGLE_YELLOW,
          color: ON_PRIMARY,
          '&:hover': { 
            backgroundColor: GOOGLE_YELLOW_DARK,
            transform: 'translateY(-1px)',
            boxShadow: `0 4px 12px ${alpha(GOOGLE_YELLOW, 0.3)}`,
          },
        },
      },
    },

    MuiCard: {
      defaultProps: { elevation: 0 },
      styleOverrides: {
        root: {
          backgroundColor: '#16191E',
          border: '1px solid rgba(255, 255, 255, 0.05)',
          borderRadius: 24,
          transition: 'all 0.3s cubic-bezier(0.4, 0, 0.2, 1)',
          '&:hover': {
            borderColor: alpha(GOOGLE_YELLOW, 0.3),
            boxShadow: `0 8px 32px ${alpha('#000', 0.4)}, 0 0 16px ${alpha(GOOGLE_YELLOW, 0.05)}`,
            transform: 'translateY(-2px)',
          },
        },
      },
    },

    MuiPaper: {
      styleOverrides: {
        root: {
          backgroundImage: 'none',
        },
        rounded: { borderRadius: 24 },
      },
    },

    MuiTextField: {
      styleOverrides: {
        root: {
          '& .MuiOutlinedInput-root': {
            borderRadius: 12,
            backgroundColor: alpha('#000', 0.2),
            '& fieldset': { borderColor: 'rgba(255, 255, 255, 0.1)' },
            '&:hover fieldset': { borderColor: 'rgba(255, 255, 255, 0.2)' },
          },
        },
      },
    },
  },
});

export default theme;
