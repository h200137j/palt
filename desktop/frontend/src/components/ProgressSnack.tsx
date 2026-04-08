import React from 'react';
import { Snackbar, Alert, LinearProgress, Box, Typography } from '@mui/material';

export interface TransferProgress {
  transferId: string;
  written: number;
  total: number;
}

interface ProgressSnackProps {
  progress: TransferProgress | null;
  error: string | null;
  onClose: () => void;
}

export const ProgressSnack: React.FC<ProgressSnackProps> = ({ progress, error, onClose }) => {
  if (error) {
    return (
      <Snackbar open={true} autoHideDuration={6000} onClose={onClose} anchorOrigin={{ vertical: 'bottom', horizontal: 'center' }}>
        <Alert onClose={onClose} severity="error" sx={{ width: '100%' }}>
          {error}
        </Alert>
      </Snackbar>
    );
  }

  if (!progress) return null;

  const percent = progress.total > 0 ? (progress.written / progress.total) * 100 : 0;

  return (
    <Snackbar open={true} anchorOrigin={{ vertical: 'bottom', horizontal: 'center' }}>
      <Alert severity="info" icon={false} sx={{ width: '100%', minWidth: 300, bgcolor: 'background.paper', color: 'text.primary', border: '1px solid', borderColor: 'divider' }}>
        <Box>
          <Typography variant="body2" sx={{ fontWeight: 'bold', mb: 1 }}>
            Transferring... {Math.round(percent)}%
          </Typography>
          <LinearProgress variant="determinate" value={percent} sx={{ height: 8, borderRadius: 4 }} />
        </Box>
      </Alert>
    </Snackbar>
  );
};
