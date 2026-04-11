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
  IconButton,
  Tooltip,
  Divider,
} from '@mui/material';
import EditIcon from '@mui/icons-material/Edit';
import SendIcon from '@mui/icons-material/Send';
import ContentCopyIcon from '@mui/icons-material/ContentCopy';
import type { Peer } from '../types/peer';
import { getOsInfo } from '../utils/osHelpers';
import { alpha, useTheme } from '@mui/material/styles';

interface PeerCardProps {
  peer: Peer;
  alias?: string;
  /** Called when "Send File" is clicked — wired up in Phase 2 */
  onSendFile?: (peer: Peer) => void;
  /** Called when the user clicks the edit icon to change the nickname */
  onRename?: (peer: Peer) => void;
}

const PeerCard: React.FC<PeerCardProps> = ({ peer, alias, onSendFile, onRename }) => {
  const theme = useTheme();
  const osInfo = getOsInfo(peer.os);
  const OsIcon = osInfo.Icon;

  const handleCopyIp = () => {
    navigator.clipboard.writeText(`${peer.ipAddress}:${peer.port}`);
  };

  const displayName = alias || peer.deviceName;
  const isAliased = !!alias;

  return (
    <Card
      id={`card-peer-${peer.id}`}
      sx={{ 
        height: '100%', 
        display: 'flex', 
        flexDirection: 'column',
        bgcolor: alpha(theme.palette.background.paper, 0.4),
        backdropFilter: 'blur(10px)',
        borderRadius: 5,
        border: '1px solid',
        borderColor: alpha('#fff', 0.05),
        transition: 'all 0.3s cubic-bezier(0.4, 0, 0.2, 1)',
        '&:hover': {
          transform: 'translateY(-4px)',
          borderColor: alpha(theme.palette.primary.main, 0.3),
          boxShadow: `0 12px 32px ${alpha('#000', 0.4)}, 0 0 20px ${alpha(theme.palette.primary.main, 0.05)}`,
        }
      }}
    >
      <CardContent sx={{ flex: 1, p: 3, pb: 1 }}>
        <Box sx={{ display: 'flex', alignItems: 'flex-start', gap: 2.5 }}>
          {/* OS avatar with glass container */}
          <Box sx={{ 
            p: 0.5, 
            borderRadius: 3.5, 
            bgcolor: alpha(osInfo.color, 0.08),
            border: `1px solid ${alpha(osInfo.color, 0.1)}`
          }}>
            <Avatar
              id={`avatar-peer-${peer.id}`}
              sx={{
                width: 52,
                height: 52,
                backgroundColor: 'transparent',
                color: osInfo.color,
                flexShrink: 0,
                borderRadius: 3,
              }}
            >
              <OsIcon sx={{ fontSize: 28 }} />
            </Avatar>
          </Box>

          {/* Device name + address */}
          <Box sx={{ minWidth: 0, flex: 1, pt: 0.5 }}>
            <Box sx={{ display: 'flex', alignItems: 'center', gap: 1 }}>
              <Tooltip title={isAliased ? `Original: ${peer.deviceName}` : "Set nickname"}>
                <Typography
                  variant="h6"
                  noWrap
                  sx={{ 
                    fontWeight: 800, 
                    lineHeight: 1.2, 
                    color: 'text.primary',
                    cursor: isAliased ? 'help' : 'default',
                    letterSpacing: '-0.4px'
                  }}
                >
                  {displayName}
                </Typography>
              </Tooltip>
              {onRename && (
                <IconButton 
                  size="small"
                  onClick={() => onRename(peer)}
                  sx={{ 
                    p: 0.5,
                    color: 'text.disabled', 
                    '&:hover': { color: 'primary.main', bgcolor: alpha(theme.palette.primary.main, 0.1) }
                  }} 
                >
                  <EditIcon sx={{ fontSize: 16 }} />
                </IconButton>
              )}
            </Box>

            <Box sx={{ display: 'flex', alignItems: 'center', gap: 1, mt: 0.75 }}>
              <Typography
                variant="caption"
                sx={{
                  color: 'text.secondary',
                  fontFamily: '"Roboto Mono", monospace',
                  fontSize: '0.75rem',
                  fontWeight: 500,
                  opacity: 0.8
                }}
              >
                {peer.ipAddress}:{peer.port}
              </Typography>
              <Tooltip title="Copy address">
                <IconButton 
                  size="small" 
                  onClick={handleCopyIp}
                  sx={{ p: 0.2, color: 'text.disabled', '&:hover': { color: 'text.primary' } }}
                >
                  <ContentCopyIcon sx={{ fontSize: 14 }} />
                </IconButton>
              </Tooltip>
            </Box>
          </Box>
        </Box>

        {/* OS chip */}
        <Box sx={{ mt: 2.5 }}>
          <Chip
            id={`chip-os-${peer.id}`}
            icon={<OsIcon sx={{ fontSize: '14px !important' }} />}
            label={osInfo.label}
            size="small"
            sx={{
              backgroundColor: alpha(osInfo.color, 0.1),
              color: osInfo.color,
              fontWeight: 700,
              fontSize: '0.75rem',
              borderRadius: 2,
              px: 0.5,
              '& .MuiChip-icon': { color: osInfo.color },
            }}
          />
        </Box>
      </CardContent>

      <Box sx={{ p: 2.5, pt: 1 }}>
        <Button
          id={`btn-send-${peer.id}`}
          variant="contained"
          startIcon={<SendIcon sx={{ fontSize: 18 }} />}
          onClick={() => onSendFile?.(peer)}
          fullWidth
          sx={{
            borderRadius: 3,
            textTransform: 'none',
            fontWeight: 800,
            fontSize: '0.9rem',
            py: 1.25,
            letterSpacing: '0.3px',
            boxShadow: `0 8px 16px ${alpha(theme.palette.primary.main, 0.2)}`,
            '&:hover': {
              boxShadow: `0 12px 24px ${alpha(theme.palette.primary.main, 0.3)}`,
            }
          }}
        >
          Send Files
        </Button>
      </Box>
    </Card>
  );
};

export default PeerCard;
