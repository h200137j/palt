/**
 * App.tsx — PALT Desktop Root Component
 *
 * Orchestrates:
 *   1. Polling the Go backend (or mock) for the peer list.
 *   2. Maintaining local state: loading, peers, local device, search.
 *   3. Rendering:
 *        TopBar → LocalDeviceCard → peer grid → EmptyState → StatusBar
 *
 * When Wails is available the real wailsjs/go/main/App bindings are used.
 * In standalone browser dev the mock in src/wailsjs/App.mock.ts is used.
 */
import React, { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import {
  Box,
  Container,
  Grid,
  Typography,
  Skeleton,
  Snackbar,
  Alert,
} from '@mui/material';

import TopBar from './components/TopBar';
import LocalDeviceCard from './components/LocalDeviceCard';
import PeerCard from './components/PeerCard';
import EmptyState from './components/EmptyState';
import StatusBar from './components/StatusBar';
import { TransferDialog } from './components/TransferDialog';
import type { OfferData } from './components/TransferDialog';
import { ProgressSnack } from './components/ProgressSnack';
import type { TransferProgress } from './components/ProgressSnack';

import type { Peer } from './types/peer';

// ── Wails bindings ────────────────────────────────────────────────────────────
// When running under `wails dev` or as a built binary, the Wails runtime
// injects window['go'] which the generated App.js calls into.
// When opened in a plain browser (npm run dev, no Wails), window['go'] is
// absent, so we fall back to the mock to keep the UI previewable.
import * as WailsApp  from '../wailsjs/go/main/App';
import * as MockApp   from './wailsjs/App.mock';

const isWails = typeof (window as any)['go'] !== 'undefined';
const GetPeers       = isWails ? WailsApp.GetPeers       : MockApp.GetPeers;
const GetLocalDevice = isWails ? WailsApp.GetLocalDevice : MockApp.GetLocalDevice;

/** How often (ms) to auto-refresh the peer list */
const POLL_INTERVAL_MS = 5_000;

// ─────────────────────────────────────────────────────────────────────────────

const App: React.FC = () => {
  const [peers, setPeers] = useState<Peer[]>([]);
  const [localDevice, setLocalDevice] = useState<Peer | null>(null);
  const [loading, setLoading] = useState(true);
  const [searchQuery, setSearchQuery] = useState('');
  const [lastUpdated, setLastUpdated] = useState<Date | null>(null);
  const [errorMsg, setErrorMsg] = useState<string | null>(null);
  
  // Phase 2 State
  const [offer, setOffer] = useState<OfferData | null>(null);
  const [progress, setProgress] = useState<TransferProgress | null>(null);
  const [transferError, setTransferError] = useState<string | null>(null);

  const pollRef = useRef<ReturnType<typeof setInterval> | null>(null);

  // ── Data fetching ──────────────────────────────────────────────────────────

  const fetchPeers = useCallback(async () => {
    try {
      const results = await GetPeers();
      setPeers(results);
      setLastUpdated(new Date());
    } catch (err) {
      console.error('[App] GetPeers failed:', err);
      setErrorMsg('Could not reach the discovery service. Is the app running?');
    } finally {
      setLoading(false);
    }
  }, []);

  const fetchLocalDevice = useCallback(async () => {
    try {
      const device = await GetLocalDevice();
      setLocalDevice(device);
    } catch (err) {
      console.error('[App] GetLocalDevice failed:', err);
    }
  }, []);

  // Initial load
  useEffect(() => {
    fetchLocalDevice();
    fetchPeers();
  }, [fetchLocalDevice, fetchPeers]);

  // Polling
  useEffect(() => {
    pollRef.current = setInterval(fetchPeers, POLL_INTERVAL_MS);
    return () => {
      if (pollRef.current) clearInterval(pollRef.current);
    };
  }, [fetchPeers]);

  // ── Wails transfer events ──────────────────────────────────────────────────
  useEffect(() => {
    if (!isWails) return;

    // We cast window as any because __wails is not in standard TS lib
    const win = window as any;
    if (!win.runtime) return;

    win.runtime.EventsOn('transfer_offer', (data: OfferData) => {
      try {
        const trustedJSON = localStorage.getItem('palt_trusted_devices');
        if (trustedJSON) {
          const trusted = JSON.parse(trustedJSON) as string[];
          if (trusted.includes(data.senderName)) {
            console.log(`[App] Auto-accepting offer from trusted device: ${data.senderName}`);
            // @ts-ignore
            WailsApp.AutoAcceptOffer(data.transferId);
            return;
          }
        }
      } catch (e) {
        console.error('Failed to parse trusted devices', e);
      }
      setOffer(data); 
    });

    win.runtime.EventsOn('transfer_started', (data: any) => {
      setProgress({ transferId: data.transferId, written: 0, total: 100 }); 
    });

    win.runtime.EventsOn('transfer_progress', (data: TransferProgress) => {
      setProgress(data);
    });

    win.runtime.EventsOn('transfer_complete', () => {
      setTimeout(() => setProgress(null), 1000);
    });

    win.runtime.EventsOn('transfer_error', (data: any) => {
      setProgress(null);
      setTransferError(data.error);
    });
    
    return () => {
      win.runtime.EventsOff('transfer_offer');
      win.runtime.EventsOff('transfer_progress');
      win.runtime.EventsOff('transfer_started');
      win.runtime.EventsOff('transfer_complete');
      win.runtime.EventsOff('transfer_error');
    };
  }, []);

  // ── Manual refresh ─────────────────────────────────────────────────────────

  const handleRefresh = useCallback(() => {
    setLoading(true);
    fetchPeers();
    // Restart poll timer
    if (pollRef.current) clearInterval(pollRef.current);
    pollRef.current = setInterval(fetchPeers, POLL_INTERVAL_MS);
  }, [fetchPeers]);

  // ── Send file (Phase 2 stub) ───────────────────────────────────────────────

  const handleSendFile = useCallback(async (peer: Peer) => {
    try {
      if (isWails) {
        if (typeof (WailsApp as any).SendFile !== 'function') {
          setErrorMsg('SendFile function not found on backend. Please restart `wails dev` to load the new bindings.');
          return;
        }
        // @ts-ignore
        await WailsApp.SendFile(peer.ipAddress, peer.port);
      } else {
        setErrorMsg(`Mock transfer to ${peer.deviceName} triggered`);
      }
    } catch (e: any) {
      setErrorMsg(`SendFile error: ${e?.message || e}`);
    }
  }, []);

  const acceptOffer = useCallback(async (transferId: string, alwaysTrust: boolean) => {
    if (alwaysTrust && offer) {
      try {
        const trustedJSON = localStorage.getItem('palt_trusted_devices');
        const trusted = trustedJSON ? JSON.parse(trustedJSON) as string[] : [];
        if (!trusted.includes(offer.senderName)) {
          trusted.push(offer.senderName);
          localStorage.setItem('palt_trusted_devices', JSON.stringify(trusted));
          console.log(`[App] Added ${offer.senderName} to trusted devices.`);
        }
      } catch (e) {
        console.error('Failed to save trusted device', e);
      }
    }

    setOffer(null);
    if (isWails) {
      // @ts-ignore
      await WailsApp.AcceptOffer(transferId);
    }
  }, [offer]);

  const rejectOffer = useCallback(async (transferId: string) => {
    setOffer(null);
    if (isWails) {
      // @ts-ignore
      await WailsApp.RejectOffer(transferId);
    }
  }, []);

  // ── Filtered peers ─────────────────────────────────────────────────────────

  const filteredPeers = useMemo(() => {
    const q = searchQuery.trim().toLowerCase();
    if (!q) return peers;
    return peers.filter(
      (p) =>
        p.deviceName.toLowerCase().includes(q) ||
        p.ipAddress.includes(q) ||
        p.os.toLowerCase().includes(q),
    );
  }, [peers, searchQuery]);

  // ─────────────────────────────────────────────────────────────────────────────

  /** Renders a 3-column skeleton grid while the first load is in progress */
  const renderSkeletons = () =>
    Array.from({ length: 3 }).map((_, i) => (
      <Grid item xs={12} sm={6} md={4} key={i}>
        <Skeleton
          variant="rounded"
          height={148}
          sx={{ borderRadius: 2, transform: 'none' }}
          animation="wave"
        />
      </Grid>
    ));

  return (
    <Box
      sx={{
        display: 'flex',
        flexDirection: 'column',
        minHeight: '100vh',
        backgroundColor: 'background.default',
      }}
    >
      {/* ── Top App Bar ───────────────────────────────────────────────────── */}
      <TopBar
        peerCount={peers.length}
        loading={loading}
        searchQuery={searchQuery}
        onSearchChange={setSearchQuery}
        onRefresh={handleRefresh}
      />

      {/* ── Main content (offset for AppBar + StatusBar) ──────────────────── */}
      <Container
        maxWidth="lg"
        component="main"
        sx={{ pt: { xs: 10, sm: 11 }, pb: 6, flex: 1 }}
      >
        {/* ── This Device ─────────────────────────────────────────────────── */}
        <LocalDeviceCard device={localDevice} />

        {/* ── Section heading ──────────────────────────────────────────────── */}
        <Box sx={{ display: 'flex', alignItems: 'baseline', gap: 1.5, mb: 2 }}>
          <Typography variant="h6" fontWeight={600} color="text.primary">
            Nearby Devices
          </Typography>
          {!loading && (
            <Typography variant="caption" color="text.secondary">
              {filteredPeers.length} of {peers.length} device{peers.length !== 1 ? 's' : ''}
            </Typography>
          )}
        </Box>

        {/* ── Peer grid ────────────────────────────────────────────────────── */}
        {loading && peers.length === 0 ? (
          <Grid container spacing={2}>
            {renderSkeletons()}
          </Grid>
        ) : filteredPeers.length > 0 ? (
          <Grid container spacing={2}>
            {filteredPeers.map((peer) => (
              <Grid item xs={12} sm={6} md={4} key={peer.id}>
                <PeerCard peer={peer} onSendFile={handleSendFile} />
              </Grid>
            ))}
          </Grid>
        ) : (
          <EmptyState
            loading={loading}
            filtered={searchQuery.trim().length > 0}
            onRefresh={handleRefresh}
          />
        )}
      </Container>

      {/* ── Bottom Status Bar ─────────────────────────────────────────────── */}
      <StatusBar
        loading={loading}
        peerCount={peers.length}
        lastUpdated={lastUpdated}
      />

      {/* ── Toast notifications ──────────────────────────────────────────── */}
      <Snackbar
        open={errorMsg !== null}
        autoHideDuration={4000}
        onClose={() => setErrorMsg(null)}
        anchorOrigin={{ vertical: 'bottom', horizontal: 'center' }}
        sx={{ mb: 4 }}
      >
        <Alert
          onClose={() => setErrorMsg(null)}
          severity="info"
          variant="filled"
          sx={{ borderRadius: 2 }}
        >
          {errorMsg}
        </Alert>
      </Snackbar>

      <TransferDialog 
        open={offer !== null} 
        offer={offer} 
        onAccept={acceptOffer} 
        onReject={rejectOffer} 
      />

      <ProgressSnack 
        progress={progress} 
        error={transferError} 
        onClose={() => setTransferError(null)} 
      />
    </Box>
  );
};

export default App;
