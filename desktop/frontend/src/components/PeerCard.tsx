/**
 * PeerCard.tsx
 *
 * A Google-style Material card for a single discovered peer device.
 *
 * Layout:
 *   [ OS Avatar ] [ Device name + IP:Port + OS chip ]  [ Send File → ]
 *
 * Hover state: card lifts with a subtle shadow (theme override in theme.ts).
 */
import React from 'react';
import {
  Card,
  CardContent,
  CardActions,
  Avatar,
  Typography,
  Box,
  Chip,
  Button,
  Tooltip,
  Divider,
} from '@mui/material';
import SendIcon from '@mui/icons-material/Send';
import ContentCopyIcon from '@mui/icons-material/ContentCopy';
import type { Peer } from '../types/peer';
import { getOsInfo } from '../utils/osHelpers';
import { alpha } from '@mui/material/styles';

interface PeerCardProps {
  peer: Peer;
  /** Called when "Send File" is clicked — wired up in Phase 2 */
  onSendFile?: (peer: Peer) => void;
}

const PeerCard: React.FC<PeerCardProps> = ({ peer, onSendFile }) => {
  const osInfo = getOsInfo(peer.os);
  const OsIcon = osInfo.Icon;

  const handleCopyIp = () => {
    navigator.clipboard.writeText(`${peer.ipAddress}:${peer.port}`);
  };

  return (
    <Card
      id={`card-peer-${peer.id}`}
      sx={{ height: '100%', display: 'flex', flexDirection: 'column' }}
    >
      <CardContent sx={{ flex: 1, pb: 1 }}>
        <Box sx={{ display: 'flex', alignItems: 'flex-start', gap: 2 }}>
          {/* OS icon avatar with brand colour */}
          <Avatar
            id={`avatar-peer-${peer.id}`}
            sx={{
              width: 48,
              height: 48,
              backgroundColor: alpha(osInfo.color, 0.12),
              color: osInfo.color,
              flexShrink: 0,
            }}
          >
            <OsIcon sx={{ fontSize: 26 }} />
          </Avatar>

          {/* Device name + address */}
          <Box sx={{ minWidth: 0, flex: 1 }}>
            <Typography
              variant="subtitle1"
              fontWeight={600}
              noWrap
              sx={{ color: 'text.primary', lineHeight: 1.3 }}
            >
              {peer.deviceName}
            </Typography>

            <Box sx={{ display: 'flex', alignItems: 'center', gap: 0.5, mt: 0.5 }}>
              <Typography
                variant="caption"
                sx={{
                  color: 'text.secondary',
                  fontFamily: '"Roboto Mono", monospace',
                  fontSize: '0.75rem',
                }}
              >
                {peer.ipAddress}:{peer.port}
              </Typography>
              <Tooltip title="Copy address">
                <ContentCopyIcon
                  id={`btn-copy-${peer.id}`}
                  onClick={handleCopyIp}
                  sx={{
                    fontSize: 13,
                    color: 'text.disabled',
                    cursor: 'pointer',
                    '&:hover': { color: 'text.secondary' },
                    transition: 'color 150ms',
                  }}
                />
              </Tooltip>
            </Box>
          </Box>
        </Box>

        {/* OS chip */}
        <Box sx={{ mt: 1.5 }}>
          <Chip
            id={`chip-os-${peer.id}`}
            icon={<OsIcon sx={{ fontSize: '14px !important' }} />}
            label={osInfo.label}
            size="small"
            sx={{
              backgroundColor: alpha(osInfo.color, 0.1),
              color: osInfo.color,
              fontWeight: 500,
              fontSize: '0.72rem',
              '& .MuiChip-icon': { color: osInfo.color },
            }}
          />
        </Box>
      </CardContent>

      <Divider sx={{ mx: 2 }} />

      <CardActions sx={{ px: 2, py: 1.25 }}>
        <Button
          id={`btn-send-${peer.id}`}
          variant="contained"
          size="small"
          startIcon={<SendIcon sx={{ fontSize: 16 }} />}
          onClick={() => onSendFile?.(peer)}
          fullWidth
          sx={{
            borderRadius: 20,
            textTransform: 'none',
            fontWeight: 600,
            fontSize: '0.82rem',
            py: 0.75,
            letterSpacing: '0.3px',
          }}
        >
          Send File
        </Button>
      </CardActions>
    </Card>
  );
};

export default PeerCard;
