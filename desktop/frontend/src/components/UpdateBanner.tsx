/**
 * UpdateBanner.tsx
 *
 * A compact, animated chip that appears in the TopBar when a newer PALT
 * version is available. Clicking it opens the UpdateDialog.
 */
import React from 'react';
import { Chip, Box } from '@mui/material';
import SystemUpdateAltIcon from '@mui/icons-material/SystemUpdateAlt';
import { alpha } from '@mui/material/styles';

interface UpdateBannerProps {
  latestVersion: string;
  onClick: () => void;
}

const UpdateBanner: React.FC<UpdateBannerProps> = ({ latestVersion, onClick }) => {
  return (
    <Box
      sx={{
        '@keyframes pulse-glow': {
          '0%, 100%': { boxShadow: '0 0 0 0 rgba(251,191,36,0.0)' },
          '50%':       { boxShadow: '0 0 0 5px rgba(251,191,36,0.35)' },
        },
      }}
    >
      <Chip
        id="btn-update-available"
        icon={
          <SystemUpdateAltIcon
            sx={{ fontSize: '15px !important', color: '#78350f !important' }}
          />
        }
        label={`Update ${latestVersion}`}
        size="small"
        onClick={onClick}
        sx={{
          backgroundColor: '#fbbf24',
          color: '#78350f',
          fontWeight: 700,
          fontSize: '0.7rem',
          height: 26,
          cursor: 'pointer',
          animation: 'pulse-glow 2.4s ease-in-out infinite',
          border: '1px solid',
          borderColor: alpha('#f59e0b', 0.6),
          '& .MuiChip-label': { px: 1 },
          '&:hover': {
            backgroundColor: '#f59e0b',
            transform: 'scale(1.04)',
          },
          transition: 'background-color 150ms, transform 150ms',
        }}
      />
    </Box>
  );
};

export default UpdateBanner;
