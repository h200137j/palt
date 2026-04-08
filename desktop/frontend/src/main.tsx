/**
 * main.tsx — React / MUI entrypoint
 *
 * Wraps the app in:
 *   - React.StrictMode  (development-time warnings)
 *   - ThemeProvider     (our yellow Google-style MUI theme)
 *   - CssBaseline       (normalises browser defaults, applies body bg colour)
 */
import React from 'react';
import ReactDOM from 'react-dom/client';
import { ThemeProvider } from '@mui/material/styles';
import CssBaseline from '@mui/material/CssBaseline';

import App from './App';
import theme from './theme/theme';

ReactDOM.createRoot(document.getElementById('root')!).render(
  <React.StrictMode>
    <ThemeProvider theme={theme}>
      {/* CssBaseline resets margins/padding and sets background.default as body bg */}
      <CssBaseline />
      <App />
    </ThemeProvider>
  </React.StrictMode>,
);
