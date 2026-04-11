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
import UpdateDialog from './components/UpdateDialog';
import ChangelogDialog from './components/ChangelogDialog';
import HistoryView from './components/HistoryView';

import type { Peer } from './types/peer';
import type { HistoryEntry } from './types/history';

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

// Update bindings — only available under Wails; no-ops in browser preview.
const _GetAppVersion     = isWails ? (WailsApp as any).GetAppVersion     : () => Promise.resolve('dev');
const _CheckForUpdate    = isWails ? (WailsApp as any).CheckForUpdate    : () => Promise.resolve({ isNewer: false });
const _OpenURL           = isWails ? (WailsApp as any).OpenURL           : (url: string) => { window.open(url, '_blank'); };
const _GetLastSeenVersion  = isWails ? (WailsApp as any).GetLastSeenVersion  : () => Promise.resolve('');
const _SaveLastSeenVersion = isWails ? (WailsApp as any).SaveLastSeenVersion : () => Promise.resolve();
const GetHistory           = isWails ? (WailsApp as any).GetHistory           : MockApp.GetHistory;
const ClearHistory         = isWails ? (WailsApp as any).ClearHistory         : MockApp.ClearHistory;
const OpenDownloadFolder   = isWails ? (WailsApp as any).OpenDownloadFolder   : () => { console.log('Mock: Open Folder'); };
const GetAliases           = isWails ? (WailsApp as any).GetAliases           : () => Promise.resolve({});
const SetAlias             = isWails ? (WailsApp as any).SetAlias             : (name: string, alias: string) => { console.log(`Mock: Set ${name} alias to ${alias}`); return Promise.resolve(); };

/** How often (ms) to auto-refresh the peer list */
const POLL_INTERVAL_MS = 30_000;

/** Shape of the update info returned by the Go CheckForUpdate binding */
interface UpdateInfo {
  isNewer: boolean;
  latestVersion: string;
  downloadUrl: string;
  releaseNotes: string;
}

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
  const [history, setHistory] = useState<HistoryEntry[]>([]);
  const [aliases, setAliases] = useState<Record<string, string>>({});
  const [currentTab, setCurrentTab] = useState(0); // 0 = Devices, 1 = History

  // ── Update state ─────────────────────────────────────────────────────────────
  const [appVersion, setAppVersion] = useState('');
  const [updateInfo, setUpdateInfo] = useState<UpdateInfo | null>(null);
  const [updateDialogOpen, setUpdateDialogOpen] = useState(false);
  const [changelogOpen, setChangelogOpen] = useState(false);
  const [changelogNotes, setChangelogNotes] = useState('');
  // ─────────────────────────────────────────────────────────────────────────────────

  const pollRef = useRef<ReturnType<typeof setInterval> | null>(null);

  // ── Update + Changelog on mount ──────────────────────────────────────────────
  useEffect(() => {
    (async () => {
      try {
        // 1. Fetch and store the current build version.
        const version = await _GetAppVersion();
        setAppVersion(version);

        // 2. Check if the user has seen this version before.
        const lastSeen = await _GetLastSeenVersion();
        if (lastSeen !== version && version !== 'dev') {
          setChangelogNotes(''); // will be filled by CheckForUpdate below
          setTimeout(() => setChangelogOpen(true), 600);
        }

        // 3. Check for a newer version in the background.
        const info: UpdateInfo = await _CheckForUpdate();
        if (info.isNewer) {
          setUpdateInfo(info);
        }
        // Reuse release notes for the changelog if available.
        if (info.releaseNotes) {
          setChangelogNotes(info.releaseNotes);
        }
      } catch (err) {
        console.warn('[App] Update check failed:', err);
      }
    })();
  }, []);

  const handleChangelogDismiss = useCallback(async () => {
    setChangelogOpen(false);
    try {
      await _SaveLastSeenVersion(appVersion);
    } catch (err) {
      console.warn('[App] SaveLastSeenVersion failed:', err);
    }
  }, [appVersion]);

  const handleUpdateDownload = useCallback(() => {
    if (updateInfo?.downloadUrl) {
      _OpenURL(updateInfo.downloadUrl);
    }
  }, [updateInfo]);

  // ── Data fetching ──────────────────────────────────────────────────────────────

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

  const fetchHistory = useCallback(async () => {
    try {
      const results = await GetHistory();
      setHistory(results);
    } catch (err) {
      console.error('[App] GetHistory failed:', err);
    }
  }, []);

  const fetchAliases = useCallback(async () => {
    try {
      const results = await GetAliases();
      setAliases(results);
    } catch (err) {
      console.error('[App] GetAliases failed:', err);
    }
  }, []);

  // Initial load
  useEffect(() => {
    fetchLocalDevice();
    fetchPeers();
    fetchHistory();
    fetchAliases();
  }, [fetchLocalDevice, fetchPeers, fetchHistory, fetchAliases]);

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

    win.runtime.EventsOn('peers_changed', (newPeers: Peer[]) => {
      setPeers(newPeers);
      setLastUpdated(new Date());
    });

    win.runtime.EventsOn('transfer_offer', (data: OfferData) => {
      setOffer(data); 
    });

    win.runtime.EventsOn('transfer_started', (data: any) => {
      setProgress({ transferId: data.transferId, written: 0, total: 100 }); 
    });

    win.runtime.EventsOn('transfer_progress', (data: TransferProgress) => {
      setProgress(data);
    });

    win.runtime.EventsOn('transfer_complete', () => {
      setProgress(prev => {
        if (!prev) return null;
        return { ...prev, status: 'completed' };
      });
    });

    win.runtime.EventsOn('transfer_error', (data: any) => {
      setProgress(null);
      setTransferError(data.error);
    });

    win.runtime.EventsOn('history_updated', (data: HistoryEntry[]) => {
      setHistory(data);
    });
    
    return () => {
      win.runtime.EventsOff('peers_changed');
      win.runtime.EventsOff('history_updated');
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
        if (isWails) {
          if (typeof (WailsApp as any).AddTrustedDevice === 'function') {
            // @ts-ignore
            WailsApp.AddTrustedDevice(offer.senderName);
          }
        }
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

  const handleClearHistory = useCallback(async () => {
    if (isWails) {
      // @ts-ignore
      await WailsApp.ClearHistory();
    } else {
      setHistory([]);
    }
  }, []);

  const handleOpenFolder = useCallback(async () => {
    if (isWails) {
      await OpenDownloadFolder();
    }
  }, []);

  const handleSetAlias = useCallback(async (peer: Peer) => {
    const current = aliases[peer.deviceName] || '';
    const newAlias = window.prompt(`Set nickname for ${peer.deviceName}:`, current);
    
    if (newAlias === null) return; // Cancelled
    
    await SetAlias(peer.deviceName, newAlias);
    const updated = await GetAliases();
    setAliases(updated);
  }, [aliases]);

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
        updateAvailable={!!updateInfo?.isNewer}
        latestVersion={updateInfo?.latestVersion}
        onUpdateClick={() => setUpdateDialogOpen(true)}
      />

      {/* ── Main content (offset for AppBar + StatusBar) ──────────────────── */}
      <Container
        maxWidth="lg"
        component="main"
        sx={{ pt: { xs: 10, sm: 11 }, pb: 6, flex: 1 }}
      >
        {/* ── This Device ─────────────────────────────────────────────────── */}
        <LocalDeviceCard device={localDevice} />

        {/* ── Tabs ────────────────────────────────────────────────────────── */}
        <Box sx={{ borderBottom: 1, borderColor: 'divider', mb: 3 }}>
          <Grid container spacing={2}>
            <Grid item sx={{ 
              pb: 1, 
              cursor: 'pointer', 
              borderBottom: currentTab === 0 ? '2px solid' : 'none',
              borderColor: 'primary.main',
              opacity: currentTab === 0 ? 1 : 0.6
            }} onClick={() => setCurrentTab(0)}>
              <Typography variant="subtitle2" fontWeight={600} color={currentTab === 0 ? 'primary.main' : 'inherit'}>
                Nearby Devices
              </Typography>
            </Grid>
            <Grid item sx={{ 
              pb: 1, 
              cursor: 'pointer', 
              borderBottom: currentTab === 1 ? '2px solid' : 'none',
              borderColor: 'primary.main',
              opacity: currentTab === 1 ? 1 : 0.6
            }} onClick={() => setCurrentTab(1)}>
              <Typography variant="subtitle2" fontWeight={600} color={currentTab === 1 ? 'primary.main' : 'inherit'}>
                History
              </Typography>
            </Grid>
          </Grid>
        </Box>

        {currentTab === 0 ? (
          <>
            {/* ── Section heading ──────────────────────────────────────────────── */}
            <Box sx={{ display: 'flex', alignItems: 'baseline', gap: 1.5, mb: 2 }}>
              <Typography variant="h6" fontWeight={600} color="text.primary">
                Available Peers
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
                    <PeerCard 
                      peer={peer} 
                      alias={aliases[peer.deviceName]}
                      onSendFile={handleSendFile}
                      onRename={handleSetAlias}
                    />
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
          </>
        ) : (
          <HistoryView history={history} onClear={handleClearHistory} />
        )}
      </Container>

      {/* ── Bottom Status Bar ─────────────────────────────────────────────── */}
      <StatusBar
        loading={loading}
        peerCount={peers.length}
        lastUpdated={lastUpdated}
        appVersion={appVersion}
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
        onOpenFolder={handleOpenFolder}
        onClose={() => {
          setProgress(null);
          setTransferError(null);
        }} 
      />

      {/* ── Update Available Dialog ──────────────────────────────────────── */}
      {updateInfo && (
        <UpdateDialog
          open={updateDialogOpen}
          currentVersion={appVersion}
          latestVersion={updateInfo.latestVersion}
          releaseNotes={updateInfo.releaseNotes}
          downloadUrl={updateInfo.downloadUrl}
          onDownload={handleUpdateDownload}
          onClose={() => setUpdateDialogOpen(false)}
        />
      )}

      {/* ── First-Boot Changelog Dialog ─────────────────────────────────── */}
      <ChangelogDialog
        open={changelogOpen}
        version={appVersion}
        releaseNotes={changelogNotes}
        onDismiss={handleChangelogDismiss}
      />
    </Box>
  );
};

export default App;
