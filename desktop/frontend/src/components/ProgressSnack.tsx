import React from 'react';
import { Snackbar, Alert, LinearProgress, Box, Typography, Button, Paper } from '@mui/material';
import { alpha } from '@mui/material/styles';
import { FolderOpen as FolderIcon } from '@mui/icons-material';

export interface TransferProgress {
  transferId: string;
  written: number;
  total: number;
  sentItems?: number;
  totalItems?: number;
  currentFile?: string;
  speed?: number;
  status?: 'transferring' | 'completed' | 'error';
}

interface ProgressSnackProps {
  progress: TransferProgress | null;
  error: string | null;
  onOpenFolder: () => void;
  onClose: () => void;
}

const formatBytes = (bytes: number) => {
  if (bytes === 0) return '0 B';
  const k = 1024;
  const sizes = ['B', 'KB', 'MB', 'GB', 'TB'];
  const i = Math.floor(Math.log(bytes) / Math.log(k));
  return parseFloat((bytes / Math.pow(k, i)).toFixed(2)) + ' ' + sizes[i];
};

export const ProgressSnack: React.FC<ProgressSnackProps> = ({ progress, error, onOpenFolder, onClose }) => {
  if (error) {
    return (
      <Snackbar open={true} onClose={onClose} anchorOrigin={{ vertical: 'bottom', horizontal: 'center' }}>
        <Alert severity="error" variant="filled" onClose={onClose} sx={{ width: '100%', borderRadius: 3, boxShadow: 6 }}>
          {error}
        </Alert>
      </Snackbar>
    );
  }

  if (!progress) return null;

  const isCompleted = progress.status === 'completed';
  const percent = progress.total > 0 ? (progress.written / progress.total) * 100 : 0;
  const speedStr = progress.speed ? `${formatBytes(Math.round(progress.speed))}/s` : '--';
  
  const fillingBg = isCompleted 
    ? 'rgba(76, 175, 80, 0.05)' 
    : `linear-gradient(90deg, ${alpha('#FBBC04', 0.08)} ${percent}%, transparent ${percent}%)`;

  return (
    <Snackbar open={true} autoHideDuration={isCompleted ? 5000 : null} onClose={onClose} anchorOrigin={{ vertical: 'bottom', horizontal: 'center' }}>
      <Paper 
        elevation={8}
        sx={{ 
          minWidth: 420, 
          borderRadius: 4, 
          overflow: 'hidden',
          background: fillingBg,
          border: '1px solid',
          borderColor: isCompleted ? 'success.light' : 'divider',
          transition: 'background 0.3s ease'
        }}
      >
        <Box sx={{ p: 2 }}>
          <Box sx={{ display: 'flex', alignItems: 'center', mb: 1.5 }}>
            <Box sx={{ 
              display: 'flex', 
              alignItems: 'center', 
              justifyContent: 'center',
              width: 36, 
              height: 36, 
              borderRadius: 2, 
              bgcolor: isCompleted ? alpha('#4caf50', 0.1) : alpha('#FBBC04', 0.1),
              color: isCompleted ? 'success.main' : '#FBBC04',
              mr: 2
            }}>
              {isCompleted ? <FolderIcon fontSize="small" /> : <Box sx={{ animation: 'spin 2s linear infinite', '@keyframes spin': { '0%': { transform: 'rotate(0deg)' }, '100%': { transform: 'rotate(360deg)' } } }}>🔄</Box>}
            </Box>
            
            <Box sx={{ flexGrow: 1, minWidth: 0 }}>
              <Typography variant="subtitle2" sx={{ fontWeight: 700, lineHeight: 1.2, mb: 0.5, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>
                {isCompleted ? 'Batch Transfer Complete' : (progress.currentFile || 'Transferring...')}
              </Typography>
              {!isCompleted && (
                <Typography variant="caption" color="text.secondary">
                  {progress.sentItems} of {progress.totalItems} files • {speedStr}
                </Typography>
              )}
            </Box>

            {isCompleted ? (
              <Button 
                size="small" 
                variant="contained" 
                color="success"
                onClick={onOpenFolder}
                sx={{ borderRadius: 2, textTransform: 'none', fontWeight: 'bold' , ml: 1}}
                startIcon={<FolderIcon />}
              >
                Open
              </Button>
            ) : (
              <Typography variant="h6" sx={{ fontWeight: 900, color: '#FBBC04', ml: 2, opacity: 0.8 }}>
                {Math.round(percent)}%
              </Typography>
            )}
          </Box>

          <Box sx={{ display: 'flex', justifyContent: 'space-between', mb: 0.5 }}>
            <Typography variant="caption" color="text.secondary">
              {formatBytes(progress.written)} of {formatBytes(progress.total)}
            </Typography>
          </Box>
          
          <LinearProgress 
            variant="determinate" 
            value={percent} 
            sx={{ 
              height: 6, 
              borderRadius: 3, 
              bgcolor: alpha('#000', 0.05),
              '& .MuiLinearProgress-bar': {
                bgcolor: isCompleted ? 'success.main' : '#FBBC04',
                borderRadius: 3
              }
            }} 
          />
        </Box>
      </Paper>
    </Snackbar>
  );
};
