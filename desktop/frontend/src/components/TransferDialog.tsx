import React, { useState, useEffect } from 'react';
import { Dialog, DialogTitle, DialogContent, DialogActions, Button, Typography, Box, FormControlLabel, Checkbox } from '@mui/material';

export interface FileMeta {
  name: string;
  size: number;
}

export interface OfferData {
  transferId: string;
  files: FileMeta[];
  totalSize: number;
  senderName: string;
}

interface TransferDialogProps {
  open: boolean;
  offer: OfferData | null;
  onAccept: (transferId: string, alwaysTrust: boolean) => void;
  onReject: (transferId: string) => void;
}

const formatBytes = (bytes: number) => {
  if (bytes === 0) return '0 B';
  const k = 1024;
  const sizes = ['B', 'KB', 'MB', 'GB', 'TB'];
  const i = Math.floor(Math.log(bytes) / Math.log(k));
  return parseFloat((bytes / Math.pow(k, i)).toFixed(2)) + ' ' + sizes[i];
};

export const TransferDialog: React.FC<TransferDialogProps> = ({ open, offer, onAccept, onReject }) => {
  const [alwaysTrust, setAlwaysTrust] = useState(false);

  // Reset state when a new offer appears
  useEffect(() => {
    if (open) {
      setAlwaysTrust(false);
    }
  }, [open, offer?.transferId]);

  if (!offer) return null;

  const fileCount = offer.files.length;
  const isMultiple = fileCount > 1;

  return (
    <Dialog open={open} onClose={() => onReject(offer.transferId)} maxWidth="xs" fullWidth>
      <DialogTitle sx={{ fontWeight: 'bold' }}>Incoming {isMultiple ? 'Files' : 'File'}</DialogTitle>
      <DialogContent>
        <Typography variant="body1" gutterBottom>
          <strong>{offer.senderName}</strong> wants to send you {isMultiple ? `${fileCount} files` : 'a file'}:
        </Typography>
        
        <Box sx={{ bgcolor: 'action.hover', p: 2, borderRadius: 2, mt: 2 }}>
          <Typography variant="subtitle2" sx={{ wordBreak: 'break-all' }}>
            {isMultiple ? `${fileCount} items` : offer.files[0].name}
          </Typography>
          <Typography variant="body2" color="text.secondary" sx={{ mt: 0.5 }}>
            {formatBytes(offer.totalSize)}
          </Typography>
        </Box>

        <Box sx={{ mt: 3, px: 0.5 }}>
          <FormControlLabel
            control={
              <Checkbox 
                checked={alwaysTrust} 
                onChange={(e) => setAlwaysTrust(e.target.checked)} 
                color="primary"
                size="small"
              />
            }
            label={
              <Typography variant="body2" color="text.secondary">
                Always accept files from this device
              </Typography>
            }
          />
        </Box>
      </DialogContent>
      <DialogActions sx={{ p: 2, pt: 0 }}>
        <Button 
          onClick={() => onReject(offer.transferId)} 
          color="inherit" 
          sx={{ fontWeight: 'bold' }}
        >
          Decline
        </Button>
        <Button 
          onClick={() => onAccept(offer.transferId, alwaysTrust)} 
          variant="contained" 
          color="primary"
          sx={{ fontWeight: 'bold', borderRadius: 6 }}
        >
          Accept
        </Button>
      </DialogActions>
    </Dialog>
  );
};
