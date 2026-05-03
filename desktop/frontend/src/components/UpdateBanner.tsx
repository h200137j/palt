import React from 'react';
import { Chip, Box } from '@mui/material';
import SystemUpdateAltIcon from '@mui/icons-material/SystemUpdateAlt';
import { alpha } from '@mui/material/styles';

interface UpdateBannerProps {
  latestVersion: string;
  onClick: () => void;
}

const TERTIARY = '#D4E157';
const ON_CARD  = '#1A1A1A';

const UpdateBanner: React.FC<UpdateBannerProps> = ({ latestVersion, onClick }) => {
  return (
    <Box
      sx={{
        '@keyframes pulse-glow': {
          '0%, 100%': { boxShadow: `0 0 0 0 ${alpha(TERTIARY, 0.0)}` },
          '50%':       { boxShadow: `0 0 0 5px ${alpha(TERTIARY, 0.35)}` },
        },
      }}
    >
      <Chip
        id="btn-update-available"
        icon={
          <SystemUpdateAltIcon
            sx={{ fontSize: '15px !important', color: `${ON_CARD} !important` }}
          />
        }
        label={`Update ${latestVersion}`}
        size="small"
        onClick={onClick}
        sx={{
          backgroundColor: TERTIARY,
          color: ON_CARD,
          fontWeight: 700,
          fontSize: '0.7rem',
          height: 26,
          cursor: 'pointer',
          animation: 'pulse-glow 2.4s ease-in-out infinite',
          border: `1px solid ${alpha(ON_CARD, 0.2)}`,
          borderRadius: 0,
          '& .MuiChip-label': { px: 1 },
          '&:hover': {
            backgroundColor: TERTIARY,
            filter: 'brightness(0.93)',
          },
          transition: 'filter 150ms',
        }}
      />
    </Box>
  );
};

export default UpdateBanner;
