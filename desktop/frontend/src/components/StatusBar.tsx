/**
 * StatusBar.tsx
 *
 * A slim footer bar showing:
 *   - Discovery status (scanning / idle)
 *   - mDNS service name
 *   - Last updated timestamp
 *
 * Inspired by VS Code's status bar and Google Workspace's bottom status strips.
 */
import React from 'react';
import { Box, Typography, Chip, Divider } from '@mui/material';
import FiberManualRecordIcon from '@mui/icons-material/FiberManualRecord';
import { alpha, useTheme } from '@mui/material/styles';

interface StatusBarProps {
  loading: boolean;
  peerCount: number;
  lastUpdated: Date | null;
  appVersion?: string;
}

const StatusBar: React.FC<StatusBarProps> = ({ loading, peerCount, lastUpdated, appVersion }) => {
  const theme = useTheme();

  const formattedTime = lastUpdated
    ? lastUpdated.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit', second: '2-digit' })
    : '—';

  return (
    <Box
      component="footer"
      id="status-bar"
      sx={{
        position: 'fixed',
        bottom: 0,
        left: 0,
        right: 0,
        height: 28,
        backgroundColor: theme.palette.primary.main,
        display: 'flex',
        alignItems: 'center',
        px: 2,
        gap: 1.5,
        zIndex: theme.zIndex.appBar,
      }}
    >
      {/* Live indicator dot */}
      <FiberManualRecordIcon
        sx={{
          fontSize: 8,
          color: loading ? alpha('#FFFFFF', 0.5) : '#FFFFFF',
          animation: loading ? 'blink 1s step-start infinite' : 'none',
          '@keyframes blink': {
            '0%, 100%': { opacity: 1 },
            '50%':       { opacity: 0 },
          },
        }}
      />

      <Typography variant="caption" sx={{ color: alpha('#FFFFFF', 0.8), fontWeight: 500 }}>
        {loading ? 'Scanning…' : `${peerCount} device${peerCount !== 1 ? 's' : ''} on network`}
      </Typography>

      <Divider orientation="vertical" flexItem sx={{ borderColor: alpha('#FFFFFF', 0.25), my: 0.5 }} />

      <Typography variant="caption" sx={{ color: alpha('#FFFFFF', 0.65) }}>
        _palt._tcp.local
      </Typography>

      <Divider orientation="vertical" flexItem sx={{ borderColor: alpha('#FFFFFF', 0.25), my: 0.5 }} />

      <Typography variant="caption" sx={{ color: alpha('#FFFFFF', 0.65) }}>
        Updated: {formattedTime}
      </Typography>

      {/* Spacer */}
      <Box sx={{ flex: 1 }} />

      <Typography variant="caption" sx={{ color: alpha('#FFFFFF', 0.6), fontWeight: 600, fontSize: '0.65rem', mr: 2 }}>
        made with ❤️ by uriel
      </Typography>

      <Chip
        label={appVersion ? `${appVersion}` : 'PALT'}
        size="small"
        sx={{
          height: 16,
          fontSize: '0.6rem',
          fontWeight: 900,
          backgroundColor: alpha('#FFFFFF', 0.1),
          color: alpha('#FFFFFF', 0.8),
          '& .MuiChip-label': { px: 1 },
        }}
      />
    </Box>
  );
};

export default StatusBar;
