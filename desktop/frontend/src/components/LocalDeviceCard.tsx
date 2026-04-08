/**
 * LocalDeviceCard.tsx
 *
 * Displays the local device's own identity in a prominent yellow "hero" banner
 * at the top of the main content area. This is the "This device" section —
 * modelled after how Google Home shows the current hub device.
 */
import React from 'react';
import {
  Box,
  Typography,
  Chip,
  Avatar,
  Divider,
} from '@mui/material';
import { alpha, useTheme } from '@mui/material/styles';
import CheckCircleIcon from '@mui/icons-material/CheckCircle';
import type { Peer } from '../types/peer';
import { getOsInfo } from '../utils/osHelpers';

interface LocalDeviceCardProps {
  device: Peer | null;
}

const LocalDeviceCard: React.FC<LocalDeviceCardProps> = ({ device }) => {
  const theme = useTheme();

  if (!device) return null;

  const osInfo = getOsInfo(device.os);
  const OsIcon = osInfo.Icon;

  return (
    <Box
      sx={{
        // Yellow tinted hero surface
        background: `linear-gradient(135deg, ${theme.palette.primary.main} 0%, ${theme.palette.primary.dark} 100%)`,
        borderRadius: 3,
        p: 3,
        mb: 3,
        display: 'flex',
        alignItems: 'center',
        gap: 2,
        position: 'relative',
        overflow: 'hidden',
        boxShadow: `0 4px 20px ${alpha(theme.palette.primary.main, 0.35)}`,
        // Decorative circle
        '&::after': {
          content: '""',
          position: 'absolute',
          top: -40,
          right: -40,
          width: 160,
          height: 160,
          borderRadius: '50%',
          backgroundColor: alpha('#FFFFFF', 0.1),
          pointerEvents: 'none',
        },
      }}
    >
      {/* OS Avatar */}
      <Avatar
        sx={{
          width: 56,
          height: 56,
          backgroundColor: alpha('#1A1400', 0.12),
          color: '#1A1400',
          fontSize: 28,
          flexShrink: 0,
        }}
      >
        <OsIcon sx={{ fontSize: 32 }} />
      </Avatar>

      {/* Device info */}
      <Box sx={{ flex: 1, minWidth: 0 }}>
        <Typography
          variant="overline"
          sx={{ color: alpha('#1A1400', 0.65), fontWeight: 600, lineHeight: 1.2, display: 'block' }}
        >
          This Device
        </Typography>
        <Typography
          variant="h5"
          sx={{ fontWeight: 700, color: '#1A1400', lineHeight: 1.3, mt: 0.25 }}
          noWrap
        >
          {device.deviceName}
        </Typography>
        <Box sx={{ display: 'flex', alignItems: 'center', gap: 1, mt: 0.75 }}>
          <Typography variant="body2" sx={{ color: alpha('#1A1400', 0.7), fontFamily: '"Roboto Mono", monospace', fontSize: '0.8rem' }}>
            {device.ipAddress}:{device.port}
          </Typography>
          <Divider orientation="vertical" flexItem sx={{ borderColor: alpha('#1A1400', 0.25), my: 0.25 }} />
          <Typography variant="body2" sx={{ color: alpha('#1A1400', 0.7) }}>
            {osInfo.label}
          </Typography>
        </Box>
      </Box>

      {/* Status chip */}
      <Chip
        id="chip-local-status"
        icon={<CheckCircleIcon />}
        label="Active"
        size="small"
        sx={{
          backgroundColor: alpha('#1A1400', 0.12),
          color: '#1A1400',
          fontWeight: 600,
          '& .MuiChip-icon': { color: '#1A1400', fontSize: 14 },
          alignSelf: 'flex-start',
        }}
      />
    </Box>
  );
};

export default LocalDeviceCard;
