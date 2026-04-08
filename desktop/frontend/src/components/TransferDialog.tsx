import React from 'react';
import { Dialog, DialogTitle, DialogContent, DialogActions, Button, Typography, Box } from '@mui/material';

export interface OfferData {
  transferId: string;
  fileName: string;
  fileSize: number;
  senderName: string;
}

interface TransferDialogProps {
  open: boolean;
  offer: OfferData | null;
  onAccept: (transferId: string, fileName: string) => void;
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
  if (!offer) return null;

  return (
    <Dialog open={open} onClose={() => onReject(offer.transferId)} maxWidth="xs" fullWidth>
      <DialogTitle sx={{ fontWeight: 'bold' }}>Incoming File</DialogTitle>
      <DialogContent>
        <Typography variant="body1" gutterBottom>
          <strong>{offer.senderName}</strong> wants to send you a file:
        </Typography>
        
        <Box sx={{ bgcolor: 'action.hover', p: 2, borderRadius: 2, mt: 2 }}>
          <Typography variant="subtitle2" sx={{ wordBreak: 'break-all' }}>
            {offer.fileName}
          </Typography>
          <Typography variant="body2" color="text.secondary" sx={{ mt: 0.5 }}>
            {formatBytes(offer.fileSize)}
          </Typography>
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
          onClick={() => onAccept(offer.transferId, offer.fileName)} 
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
