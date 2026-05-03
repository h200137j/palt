/**
 * EmptyState.tsx
 *
 * Shown when no peers have been discovered yet — similar to how Google Drive
 * or Google Photos show an empty-state illustration with guidance text.
 */
import React from 'react';
import { Box, Typography, Button, CircularProgress } from '@mui/material';
import WifiSearchingIcon from '@mui/icons-material/WifiFind';
import DevicesIcon from '@mui/icons-material/Devices';
import { alpha, useTheme } from '@mui/material/styles';

interface EmptyStateProps {
  loading: boolean;
  filtered: boolean; // true when a search filter is active
  onRefresh: () => void;
}

const EmptyState: React.FC<EmptyStateProps> = ({ loading, filtered, onRefresh }) => {
  const theme = useTheme();

  return (
    <Box
      id="empty-state"
      sx={{
        display: 'flex',
        flexDirection: 'column',
        alignItems: 'center',
        justifyContent: 'center',
        py: 10,
        px: 3,
        textAlign: 'center',
        gap: 2,
      }}
    >
      {/* Illustration circle */}
      <Box
        sx={{
          width: 96,
          height: 96,
          backgroundColor: theme.palette.background.paper,
          border: `1px solid ${alpha(theme.palette.text.secondary!, 0.3)}`,
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'center',
          mb: 1,
          animation: loading ? 'pulse 1.6s ease-in-out infinite' : 'none',
          '@keyframes pulse': {
            '0%':   { opacity: 1   },
            '50%':  { opacity: 0.5 },
            '100%': { opacity: 1   },
          },
        }}
      >
        {loading ? (
          <CircularProgress size={40} thickness={3} sx={{ color: 'primary.main' }} />
        ) : filtered ? (
          <DevicesIcon sx={{ fontSize: 44, color: 'primary.main' }} />
        ) : (
          <WifiSearchingIcon sx={{ fontSize: 44, color: 'primary.main' }} />
        )}
      </Box>

      <Typography variant="h5" fontWeight={500} color="text.primary">
        {loading
          ? 'Scanning the network…'
          : filtered
          ? 'No matching devices'
          : 'No devices found'}
      </Typography>

      <Typography variant="body2" color="text.secondary" sx={{ maxWidth: 340 }}>
        {loading
          ? 'PALT is broadcasting on your local network. Devices running PALT will appear here.'
          : filtered
          ? 'Try a different search or clear the filter to see all devices.'
          : 'Make sure other PALT devices are on the same Wi-Fi network and the app is running.'}
      </Typography>

      {!loading && (
        <Button
          id="btn-empty-refresh"
          variant="outlined"
          color="primary"
          onClick={onRefresh}
          sx={{ mt: 1, fontWeight: 700 }}
        >
          Scan again
        </Button>
      )}
    </Box>
  );
};

export default EmptyState;
