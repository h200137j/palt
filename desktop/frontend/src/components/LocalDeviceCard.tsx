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
        // Premium yellow mesh surface
        background: `linear-gradient(135deg, ${theme.palette.primary.main} 0%, ${theme.palette.primary.dark} 100%)`,
        borderRadius: 5,
        p: 4,
        mb: 4,
        display: 'flex',
        alignItems: 'center',
        gap: 3,
        position: 'relative',
        overflow: 'hidden',
        boxShadow: `0 20px 40px ${alpha(theme.palette.primary.main, 0.25)}`,
        // Glass blobs
        '&::before': {
          content: '""',
          position: 'absolute',
          top: -60,
          right: -40,
          width: 240,
          height: 240,
          borderRadius: '50%',
          background: `radial-gradient(circle, ${alpha('#fff', 0.25)} 0%, transparent 70%)`,
          pointerEvents: 'none',
        },
        '&::after': {
          content: '""',
          position: 'absolute',
          bottom: -20,
          left: -20,
          width: 140,
          height: 140,
          borderRadius: '50%',
          background: `radial-gradient(circle, ${alpha('#fff', 0.15)} 0%, transparent 70%)`,
          pointerEvents: 'none',
        },
      }}
    >
      {/* OS Avatar with glass container */}
      <Box 
        sx={{ 
          p: 0.5, 
          borderRadius: '24px', 
          background: alpha('#000', 0.05),
          border: `1px solid ${alpha('#000', 0.05)}`
        }}
      >
        <Avatar
          sx={{
            width: 72,
            height: 72,
            backgroundColor: alpha('#1A1400', 0.08),
            color: '#1A1400',
            fontSize: 34,
            flexShrink: 0,
            borderRadius: '20px',
          }}
        >
          <OsIcon sx={{ fontSize: 38 }} />
        </Avatar>
      </Box>

      {/* Device info */}
      <Box sx={{ flex: 1, minWidth: 0, position: 'relative', zIndex: 1 }}>
        <Typography
          variant="overline"
          sx={{ 
            color: alpha('#1A1400', 0.5), 
            fontWeight: 800, 
            lineHeight: 1.2, 
            display: 'block',
            letterSpacing: '2px',
            fontSize: '0.7rem'
          }}
        >
          THIS DEVICE
        </Typography>
        <Typography
          variant="h3"
          sx={{ 
            fontWeight: 900, 
            color: '#1A1400', 
            lineHeight: 1.1, 
            mt: 0.5,
            letterSpacing: '-1.5px'
          }}
          noWrap
        >
          {device.deviceName}
        </Typography>
        <Box sx={{ display: 'flex', alignItems: 'center', gap: 1.5, mt: 1.5 }}>
          <Box sx={{ 
            backgroundColor: alpha('#000', 0.06), 
            px: 1.5, 
            py: 0.5, 
            borderRadius: 1.5,
          }}>
            <Typography variant="body2" sx={{ color: alpha('#1A1400', 0.7), fontFamily: '"Roboto Mono", monospace', fontSize: '0.85rem', fontWeight: 600 }}>
              {device.ipAddress}:{device.port}
            </Typography>
          </Box>
          <Box sx={{ width: 4, height: 4, borderRadius: '50%', bgcolor: alpha('#1A1400', 0.2) }} />
          <Typography variant="body2" sx={{ color: alpha('#1A1400', 0.7), fontWeight: 700, fontSize: '0.9rem' }}>
            {osInfo.label}
          </Typography>
        </Box>
      </Box>

      {/* Status chip */}
      <Chip
        id="chip-local-status"
        icon={<CheckCircleIcon />}
        label="Online"
        sx={{
          backgroundColor: alpha('#000', 0.08),
          color: '#1A1400',
          fontWeight: 900,
          borderRadius: 2,
          '& .MuiChip-icon': { color: '#1A1400', fontSize: 16 },
          alignSelf: 'center',
          px: 1,
          height: 36,
          fontSize: '0.85rem'
        }}
      />
    </Box>
  );
};

export default LocalDeviceCard;
