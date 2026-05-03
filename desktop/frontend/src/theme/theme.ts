import { createTheme, alpha } from '@mui/material/styles';

// Concrete Lemon design tokens
const PRIMARY   = '#1A1A1A';
const SECONDARY = '#6B6B6B';
const TERTIARY  = '#D4E157';
const NEUTRAL   = '#D9D6D0';
const SURFACE   = '#F0EDE6';

export const THEME_TERTIARY = TERTIARY;

const theme = createTheme({
  palette: {
    mode: 'light',

    primary: {
      main: PRIMARY,
      contrastText: '#FFFFFF',
    },

    secondary: {
      main: SECONDARY,
      contrastText: '#FFFFFF',
    },

    background: {
      default: NEUTRAL,
      paper: SURFACE,
    },

    text: {
      primary: PRIMARY,
      secondary: SECONDARY,
    },

    divider: alpha(PRIMARY, 0.12),

    error:   { main: '#D32F2F' },
    success: { main: '#2E7D32' },
  },

  typography: {
    fontFamily: '"Archivo", sans-serif',

    h1: { fontSize: '2.5rem',   fontWeight: 800 },
    h2: { fontSize: '1.75rem',  fontWeight: 800 },
    h3: { fontSize: '1.5rem',   fontWeight: 700 },
    h4: { fontSize: '1.25rem',  fontWeight: 700 },
    h5: { fontSize: '1.125rem', fontWeight: 600 },
    h6: { fontSize: '1rem',     fontWeight: 600 },

    body1: { fontSize: '0.95rem', lineHeight: 1.5 },
    body2: { fontSize: '0.875rem', lineHeight: 1.5 },

    button: { fontWeight: 700, textTransform: 'none' },

    caption:  { fontFamily: '"Archivo Narrow", sans-serif', fontSize: '0.72rem', letterSpacing: '0.1em' },
    overline: { fontFamily: '"Archivo Narrow", sans-serif', fontSize: '0.72rem', letterSpacing: '0.1em', textTransform: 'uppercase' },
  },

  shape: {
    borderRadius: 0,
  },

  components: {
    MuiCssBaseline: {
      styleOverrides: {
        body: {
          backgroundColor: NEUTRAL,
          backgroundImage: 'none',
        },
      },
    },

    MuiAppBar: {
      styleOverrides: {
        root: {
          backgroundColor: PRIMARY,
          color: '#FFFFFF',
          boxShadow: 'none',
          borderBottom: `1px solid ${alpha(PRIMARY, 0.2)}`,
        },
      },
    },

    MuiButton: {
      defaultProps: { disableElevation: true },
      styleOverrides: {
        root: {
          borderRadius: 0,
          padding: '12px 20px',
          fontWeight: 700,
        },
        containedPrimary: {
          backgroundColor: TERTIARY,
          color: PRIMARY,
          '&:hover': {
            backgroundColor: TERTIARY,
            filter: 'brightness(0.93)',
          },
        },
      },
    },

    MuiCard: {
      defaultProps: { elevation: 0 },
      styleOverrides: {
        root: {
          backgroundColor: SURFACE,
          color: PRIMARY,
          border: `1px solid ${alpha(SECONDARY, 0.3)}`,
          borderRadius: 2,
        },
      },
    },

    MuiPaper: {
      styleOverrides: {
        root: {
          backgroundImage: 'none',
          borderRadius: 0,
        },
        rounded: { borderRadius: 2 },
      },
    },

    MuiTextField: {
      styleOverrides: {
        root: {
          '& .MuiOutlinedInput-root': {
            borderRadius: 0,
            backgroundColor: 'transparent',
            '& fieldset': { borderColor: SECONDARY },
            '&:hover fieldset': { borderColor: PRIMARY },
            '&.Mui-focused fieldset': { borderColor: PRIMARY },
          },
        },
      },
    },

    MuiDialog: {
      styleOverrides: {
        paper: { borderRadius: 2 },
      },
    },

    MuiLinearProgress: {
      styleOverrides: {
        root: { borderRadius: 0 },
        bar:  { borderRadius: 0 },
      },
    },
  },
});

export default theme;
