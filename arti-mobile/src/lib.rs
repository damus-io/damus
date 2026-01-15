//! Arti Mobile - FFI wrapper for Arti Tor client on iOS
//!
//! Based on Guardian Project's arti-mobile-ex implementation.

use std::ffi::{CStr, CString};
use std::fmt;
use std::os::raw::{c_char, c_int};
use std::sync::{Arc, Mutex};
use std::thread;
use std::time::Duration;

use anyhow::{Context, Result};
use async_std::task::sleep;
use futures::FutureExt;
use tracing::{info, warn};

use arti::{proxy, reload_cfg, ArtiCombinedConfig, ArtiConfig};
use arti::reload_cfg::ReconfigurableModule;
use arti_client::config::TorClientConfigBuilder;
use arti_client::{TorClient, TorClientConfig};
use tor_config::{ConfigurationSources, Listen};
use tor_rtcompat::{PreferredRuntime, ToplevelBlockOn, ToplevelRuntime};

use tracing_subscriber::fmt::Layer;
use tracing_subscriber::layer::SubscriberExt;
use tracing_subscriber::util::SubscriberInitExt;
use tracing_subscriber::fmt::Subscriber;

#[macro_use]
extern crate lazy_static;

// Global state
lazy_static! {
    static ref STATE: Mutex<ArtiState> = Mutex::new(ArtiState::Uninitialized);
    static ref SOCKS_PORT: Mutex<u16> = Mutex::new(0);
}

#[derive(Clone, Copy, PartialEq)]
enum ArtiState {
    Uninitialized,
    Initialized,
    Starting,
    Running,
    Stopping,
    Stopped,
}

impl fmt::Display for ArtiState {
    fn fmt(&self, f: &mut fmt::Formatter) -> fmt::Result {
        match self {
            ArtiState::Uninitialized => write!(f, "Uninitialized"),
            ArtiState::Initialized => write!(f, "Initialized"),
            ArtiState::Starting => write!(f, "Starting"),
            ArtiState::Running => write!(f, "Running"),
            ArtiState::Stopping => write!(f, "Stopping"),
            ArtiState::Stopped => write!(f, "Stopped"),
        }
    }
}

/// Logging callback type for iOS
type LoggingCallback = extern "C" fn(*const c_char);

/// Start the Arti SOCKS proxy.
///
/// # Arguments
/// * `state_dir` - Directory for Tor state
/// * `cache_dir` - Directory for Tor cache
/// * `socks_port` - SOCKS proxy port
/// * `log_fn` - Callback for log messages
///
/// # Returns
/// Result string (caller must free with `arti_free_string`)
#[no_mangle]
pub extern "C" fn arti_start(
    state_dir: *const c_char,
    cache_dir: *const c_char,
    socks_port: c_int,
    log_fn: LoggingCallback,
) -> *mut c_char {
    // Null pointer checks
    if state_dir.is_null() {
        return CString::new("Error: null state_dir").unwrap().into_raw();
    }
    if cache_dir.is_null() {
        return CString::new("Error: null cache_dir").unwrap().into_raw();
    }

    let state_dir = unsafe { CStr::from_ptr(state_dir) }.to_string_lossy();
    let cache_dir = unsafe { CStr::from_ptr(cache_dir) }.to_string_lossy();

    let result = match start_arti_proxy(
        &state_dir,
        &cache_dir,
        socks_port as u16,
        move |buf: &[u8]| {
            if let Ok(cstr) = CString::new(buf.to_owned()) {
                (log_fn)(cstr.as_ptr());
            }
        },
    ) {
        Ok(res) => {
            format!("OK: {}", res)
        }
        Err(e) => {
            format!("Error: {}", e)
        }
    };

    CString::new(result).unwrap().into_raw()
}

/// Stop the Arti proxy.
#[no_mangle]
pub extern "C" fn arti_stop() {
    stop_arti_proxy();
}

/// Get the current SOCKS port.
/// Returns 0 if not running or on error.
#[no_mangle]
pub extern "C" fn arti_get_socks_port() -> c_int {
    SOCKS_PORT.lock().map(|p| *p as c_int).unwrap_or(0)
}

/// Check if Arti is running.
/// Returns 1 if running, 0 otherwise.
#[no_mangle]
pub extern "C" fn arti_is_running() -> c_int {
    if let Ok(state) = STATE.lock() {
        if *state == ArtiState::Running {
            return 1;
        }
    }
    0
}

/// Get the current state as a string.
/// Caller must free with `arti_free_string`.
#[no_mangle]
pub extern "C" fn arti_get_state() -> *mut c_char {
    let state_str = if let Ok(state) = STATE.lock() {
        state.to_string()
    } else {
        "Unknown".to_string()
    };
    CString::new(state_str).unwrap().into_raw()
}

/// Free a string returned by Arti functions.
#[no_mangle]
pub extern "C" fn arti_free_string(s: *mut c_char) {
    if !s.is_null() {
        unsafe { drop(CString::from_raw(s)); }
    }
}

// Internal functions

fn start_arti_proxy<F>(
    state_dir: &str,
    cache_dir: &str,
    socks_port: u16,
    log_fn: F,
) -> Result<String>
where
    F: Fn(&[u8]) + Send + Sync + 'static,
{
    init_log_subscriber(log_fn);
    configure_and_run_arti_proxy(state_dir, cache_dir, socks_port);
    Ok(format!("Arti starting on port {}", socks_port))
}

fn init_log_subscriber<F>(log_fn: F)
where
    F: Fn(&[u8]) + Send + Sync + 'static,
{
    if let Ok(mut state) = STATE.lock() {
        if let ArtiState::Uninitialized = *state {
            let log_fn = Arc::new(log_fn);
            let log = Layer::new().with_writer(move || CallbackWriter::new(log_fn.clone()));
            let _ = Subscriber::builder().finish().with(log).try_init();
            *state = ArtiState::Initialized;
            info!("[ARTI] Initialized");
        }
    }
}

fn configure_and_run_arti_proxy(state_dir: &str, cache_dir: &str, socks_port: u16) {
    if let Ok(mut state) = STATE.lock() {
        match *state {
            ArtiState::Initialized | ArtiState::Stopped => {
                *state = ArtiState::Starting;
                info!("[ARTI] Starting...");
            }
            _ => {
                warn!("[ARTI] Cannot start from state: {}", *state);
                return;
            }
        }
    } else {
        return;
    }

    // Store the port
    if let Ok(mut port) = SOCKS_PORT.lock() {
        *port = socks_port;
    }

    let state_dir = state_dir.to_string();
    let cache_dir = cache_dir.to_string();

    thread::spawn(move || {
        let runtime = match PreferredRuntime::create() {
            Ok(rt) => rt,
            Err(e) => {
                warn!("[ARTI] Failed to create runtime: {}", e);
                if let Ok(mut state) = STATE.lock() {
                    *state = ArtiState::Stopped;
                }
                return;
            }
        };

        let config_sources = ConfigurationSources::default();
        let arti_config = ArtiConfig::default();

        let client_config = match TorClientConfigBuilder::from_directories(&state_dir, &cache_dir).build() {
            Ok(cfg) => cfg,
            Err(e) => {
                warn!("[ARTI] Failed to build client config: {}", e);
                if let Ok(mut state) = STATE.lock() {
                    *state = ArtiState::Stopped;
                }
                return;
            }
        };

        if let Err(e) = runtime.clone().block_on(run_proxy(
            runtime,
            Listen::new_localhost(socks_port),
            config_sources,
            arti_config,
            client_config,
        )) {
            warn!("[ARTI] Proxy failed: {}", e);
            if let Ok(mut state) = STATE.lock() {
                *state = ArtiState::Stopped;
            }
        }
    });
}

fn stop_arti_proxy() {
    if let Ok(mut state) = STATE.lock() {
        if *state == ArtiState::Running {
            *state = ArtiState::Stopping;
            info!("[ARTI] Stopping...");
        }
    }
}

/// Shorthand for a boxed and pinned Future.
type PinnedFuture<T> = std::pin::Pin<Box<dyn futures::Future<Output = T>>>;

/// Application reconfigurable module
struct Application {
    original_config: ArtiConfig,
}

impl Application {
    fn new(cfg: ArtiConfig) -> Self {
        Self { original_config: cfg }
    }
}

impl ReconfigurableModule for Application {
    fn reconfigure(&self, new: &ArtiCombinedConfig) -> Result<()> {
        let original = &self.original_config;
        let config = &new.0;

        if config.proxy() != original.proxy() {
            warn!("[ARTI] Cannot reconfigure proxy settings while running");
        }
        if config.logging() != original.logging() {
            warn!("[ARTI] Cannot reconfigure logging while running");
        }

        Ok(())
    }
}

async fn run_proxy<R: ToplevelRuntime>(
    runtime: R,
    socks_listen: Listen,
    config_sources: ConfigurationSources,
    arti_config: ArtiConfig,
    client_config: TorClientConfig,
) -> Result<()> {
    use arti_client::BootstrapBehavior::OnDemand;

    let client_builder = TorClient::with_runtime(runtime.clone())
        .config(client_config)
        .bootstrap_behavior(OnDemand);
    let client = client_builder.create_unbootstrapped_async().await?;

    let reconfigurable_modules: Vec<Arc<dyn reload_cfg::ReconfigurableModule>> = vec![
        Arc::new(client.clone()),
        Arc::new(Application::new(arti_config.clone())),
    ];

    let weak_modules = reconfigurable_modules.iter().map(Arc::downgrade).collect();
    reload_cfg::watch_for_config_changes(
        client.runtime(),
        config_sources,
        &arti_config,
        weak_modules,
    )?;

    let mut proxies: Vec<PinnedFuture<(Result<()>, &str)>> = Vec::new();

    if !socks_listen.is_empty() {
        let runtime = runtime.clone();
        let client = client.isolated_client();
        let socks_listen = socks_listen.clone();
        proxies.push(Box::pin(async move {
            let res = proxy::run_proxy(runtime, client, socks_listen, None).await;
            (res, "SOCKS")
        }));
    }

    let proxy_future = futures::future::select_all(proxies).map(|(finished, _, _)| finished);

    futures::select!(
        r = proxy_future.fuse() => r.0.context(format!("{} proxy failure", r.1)),
        r = async {
            client.bootstrap().await?;
            let port = SOCKS_PORT.lock().map(|p| *p).unwrap_or(0);
            info!("[ARTI] Bootstrap complete, proxy ready on port {}", port);

            if let Ok(mut state) = STATE.lock() {
                *state = ArtiState::Running;
            }

            // Poll for stop request
            loop {
                sleep(Duration::from_millis(200)).await;
                if let Ok(state) = STATE.lock() {
                    if *state == ArtiState::Stopping {
                        info!("[ARTI] Stop requested");
                        break;
                    }
                }
            }
            Ok(())
        }.fuse() => r.context("shutdown"),
    )?;

    drop(reconfigurable_modules);

    if let Ok(mut state) = STATE.lock() {
        *state = ArtiState::Stopped;
        info!("[ARTI] Stopped");
    }

    Ok(())
}

// Callback writer for logging
#[derive(Clone)]
struct CallbackWriter<F> {
    func: Arc<F>,
}

impl<F> CallbackWriter<F>
where
    F: Fn(&[u8]) + Send + Sync + 'static,
{
    fn new(callback: Arc<F>) -> Self {
        CallbackWriter { func: callback }
    }
}

impl<F> std::io::Write for CallbackWriter<F>
where
    F: Fn(&[u8]) + Send + Sync + 'static,
{
    fn write(&mut self, buf: &[u8]) -> std::io::Result<usize> {
        (self.func)(buf);
        Ok(buf.len())
    }

    fn flush(&mut self) -> std::io::Result<()> {
        Ok(())
    }
}
