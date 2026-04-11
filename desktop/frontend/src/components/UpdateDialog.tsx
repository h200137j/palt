/**
 * UpdateDialog.tsx
 *
 * Shown when the user clicks the UpdateBanner chip.
 * Displays the version diff, release notes, and a direct download button
 * for the new .deb package.
 */
import React from 'react';
import {
  Dialog,
  DialogTitle,
  DialogContent,
  DialogActions,
  Button,
  Typography,
  Box,
  Chip,
  Divider,
} from '@mui/material';
import SystemUpdateAltIcon from '@mui/icons-material/SystemUpdateAlt';
import OpenInNewIcon from '@mui/icons-material/OpenInNew';
import ArrowForwardIcon from '@mui/icons-material/ArrowForward';
import { alpha } from '@mui/material/styles';

export interface UpdateDialogProps {
  open: boolean;
  currentVersion: string;
  latestVersion: string;
  releaseNotes: string;
  downloadUrl: string;
  onDownload: () => void;
  onClose: () => void;
}

const UpdateDialog: React.FC<UpdateDialogProps> = ({
  open,
  currentVersion,
  latestVersion,
  releaseNotes,
  downloadUrl,
  onDownload,
  onClose,
}) => {
  return (
    <Dialog
      open={open}
      onClose={onClose}
      maxWidth="sm"
      fullWidth
      PaperProps={{
        sx: { borderRadius: 3, overflow: 'hidden' },
      }}
    >
      {/* Amber accent header strip */}
      <Box
        sx={{
          background: 'linear-gradient(135deg, #f59e0b 0%, #d97706 100%)',
          px: 3,
          py: 2,
          display: 'flex',
          alignItems: 'center',
          gap: 1.5,
        }}
      >
        <SystemUpdateAltIcon sx={{ color: '#78350f', fontSize: 28 }} />
        <Box>
          <Typography variant="h6" fontWeight={700} sx={{ color: '#78350f', lineHeight: 1.2 }}>
            Update Available
          </Typography>
          <Typography variant="caption" sx={{ color: alpha('#78350f', 0.75) }}>
            A new version of PALT is ready to install
          </Typography>
        </Box>
      </Box>

      <DialogContent sx={{ pt: 3 }}>
        {/* Version comparison row */}
        <Box
          sx={{
            display: 'flex',
            alignItems: 'center',
            gap: 1.5,
            mb: 3,
            p: 2,
            borderRadius: 2,
            backgroundColor: 'action.hover',
          }}
        >
          <Chip
            label={currentVersion}
            size="small"
            sx={{ fontWeight: 600, backgroundColor: 'action.selected' }}
          />
          <ArrowForwardIcon sx={{ color: 'text.secondary', fontSize: 18 }} />
          <Chip
            label={latestVersion}
            size="small"
            sx={{
              fontWeight: 700,
              backgroundColor: '#fef3c7',
              color: '#78350f',
              border: '1px solid #f59e0b',
            }}
          />
        </Box>

        <Divider sx={{ mb: 2 }} />

        {/* Release notes */}
        <Typography variant="subtitle2" fontWeight={600} gutterBottom>
          What's New
        </Typography>
        <Box
          sx={{
            maxHeight: 260,
            overflowY: 'auto',
            backgroundColor: 'action.hover',
            borderRadius: 2,
            p: 2,
            fontFamily: 'monospace',
          }}
        >
          <Typography
            variant="body2"
            color="text.secondary"
            sx={{ whiteSpace: 'pre-wrap', lineHeight: 1.7 }}
          >
            {releaseNotes || 'No release notes available.'}
          </Typography>
        </Box>
      </DialogContent>

      <DialogActions sx={{ p: 2, pt: 0, gap: 1 }}>
        <Button onClick={onClose} color="inherit" sx={{ fontWeight: 600 }}>
          Remind me later
        </Button>
        <Button
          id="btn-download-update"
          onClick={onDownload}
          variant="contained"
          startIcon={<OpenInNewIcon />}
          sx={{
            fontWeight: 700,
            borderRadius: 6,
            backgroundColor: '#f59e0b',
            color: '#78350f',
            '&:hover': { backgroundColor: '#d97706' },
          }}
        >
          Download {latestVersion} (.deb)
        </Button>
      </DialogActions>
    </Dialog>
  );
};

export default UpdateDialog;
