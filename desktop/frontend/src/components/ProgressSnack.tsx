import React from 'react';
import { Snackbar, Alert, LinearProgress, Box, Typography, Button, Paper } from '@mui/material';
import { alpha, useTheme } from '@mui/material/styles';
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
  const theme = useTheme();

  if (error) {
    return (
      <Snackbar 
        open={true} 
        onClose={onClose} 
        anchorOrigin={{ vertical: 'bottom', horizontal: 'center' }}
        sx={{ bottom: { xs: 40, sm: 60 } }}
      >
        <Alert 
          severity="error" 
          variant="filled" 
          onClose={onClose} 
          sx={{ 
            width: '100%', 
            borderRadius: 4, 
            boxShadow: '0 8px 32px rgba(234, 67, 53, 0.2)',
            bgcolor: '#EA4335',
            fontWeight: 600
          }}
        >
          {error}
        </Alert>
      </Snackbar>
    );
  }

  if (!progress) return null;

  const isCompleted = progress.status === 'completed';
  const percent = progress.total > 0 ? (progress.written / progress.total) * 100 : 0;
  const speedStr = progress.speed ? `${formatBytes(Math.round(progress.speed))}/s` : '--';
  
  return (
    <Snackbar 
      open={true} 
      autoHideDuration={isCompleted ? 8000 : null} 
      onClose={onClose} 
      anchorOrigin={{ vertical: 'bottom', horizontal: 'center' }}
      sx={{ bottom: { xs: 40, sm: 60 } }}
    >
      <Paper 
        elevation={0}
        sx={{ 
          minWidth: 460, 
          borderRadius: 5, 
          overflow: 'hidden',
          background: theme.palette.background.paper,
          border: '1px solid',
          borderColor: isCompleted ? alpha(theme.palette.success.main, 0.5) : alpha(theme.palette.text.secondary!, 0.3),
          position: 'relative',
          transition: 'all 0.4s cubic-bezier(0.4, 0, 0.2, 1)',
          '&::before': {
            content: '""',
            position: 'absolute',
            top: 0,
            left: 0,
            bottom: 0,
            width: `${percent}%`,
            background: isCompleted 
              ? alpha(theme.palette.success.main, 0.1)
              : alpha(theme.palette.primary.main, 0.1),
            transition: 'width 0.5s cubic-bezier(0.1, 0.7, 1.0, 0.1)',
            zIndex: 0
          }
        }}
      >
        <Box sx={{ p: 2.5, position: 'relative', zIndex: 1 }}>
          <Box sx={{ display: 'flex', alignItems: 'center', mb: 2 }}>
            <Box sx={{ 
              display: 'flex', 
              alignItems: 'center', 
              justifyContent: 'center',
              width: 44, 
              height: 44, 
              borderRadius: 3, 
              bgcolor: isCompleted ? alpha(theme.palette.success.main, 0.15) : alpha(theme.palette.primary.main, 0.1),
              color: isCompleted ? theme.palette.success.main : theme.palette.primary.main,
              mr: 2.5,
              boxShadow: isCompleted ? 'none' : `0 0 12px ${alpha(theme.palette.primary.main, 0.2)}`
            }}>
              {isCompleted ? (
                <FolderIcon fontSize="medium" />
              ) : (
                <Box sx={{ 
                  animation: 'pulse 2s infinite ease-in-out',
                  '@keyframes pulse': {
                    '0%': { transform: 'scale(0.95)', opacity: 0.8 },
                    '50%': { transform: 'scale(1.05)', opacity: 1 },
                    '100%': { transform: 'scale(0.95)', opacity: 0.8 },
                  }
                }}>
                  <FolderIcon />
                </Box>
              )}
            </Box>
            
            <Box sx={{ flexGrow: 1, minWidth: 0 }}>
              <Typography variant="body1" sx={{ fontWeight: 800, lineHeight: 1.2, mb: 0.5, letterSpacing: '-0.3px' }}>
                {isCompleted ? 'Transmission Successful' : (progress.currentFile || 'Transferring...')}
              </Typography>
              {!isCompleted && (
                <Typography variant="caption" sx={{ color: 'text.secondary', fontWeight: 600, opacity: 0.8 }}>
                  Preparing {progress.sentItems} of {progress.totalItems} files • {speedStr}
                </Typography>
              )}
              {isCompleted && (
                <Typography variant="caption" sx={{ color: 'success.main', fontWeight: 700 }}>
                  Batch of {progress.totalItems} files received
                </Typography>
              )}
            </Box>

            {!isCompleted && (
              <Typography variant="h5" sx={{ fontWeight: 900, color: 'primary.main', ml: 2 }}>
                {Math.round(percent)}%
              </Typography>
            )}
          </Box>

          <Box sx={{ display: 'flex', justifyContent: 'space-between', mb: 1, px: 0.5 }}>
            <Typography variant="caption" sx={{ fontWeight: 700, opacity: 0.6 }}>
              {formatBytes(progress.written)} / {formatBytes(progress.total)}
            </Typography>
            {isCompleted && (
              <Button 
                size="small" 
                variant="contained" 
                color="success"
                onClick={onOpenFolder}
                startIcon={<FolderIcon />}
                sx={{ 
                  borderRadius: 2, 
                  textTransform: 'none', 
                  py: 0.5,
                  px: 2,
                  fontWeight: 800,
                  fontSize: '0.75rem',
                }}
              >
                View in Folder
              </Button>
            )}
          </Box>
          
          <LinearProgress 
            variant="determinate" 
            value={percent} 
            sx={{ 
              height: 8, 
              borderRadius: 4, 
              bgcolor: alpha('#000', 0.1),
              '& .MuiLinearProgress-bar': {
                bgcolor: isCompleted ? 'success.main' : 'primary.main',
                borderRadius: 4,
                boxShadow: isCompleted ? 'none' : `0 0 8px ${alpha(theme.palette.primary.main, 0.5)}`
              }
            }} 
          />
        </Box>
      </Paper>
    </Snackbar>
  );
};
