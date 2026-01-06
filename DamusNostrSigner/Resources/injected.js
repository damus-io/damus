// NIP-07 window.nostr - injected into page context
// This script is injected by content.js to run in the MAIN world

(function() {
    'use strict';

    if (window.nostr) return;

    let requestId = 0;
    const pending = new Map();

    // Listen for responses from content script
    window.addEventListener('DAMUS_RESPONSE', (e) => {
        const { id, result, error } = e.detail;
        const p = pending.get(id);
        if (!p) return;

        // Check if result contains an action we need to handle
        if (result && result._damusAction === 'openUrl') {
            handleOpenUrlAction(id, result);
            return;
        }

        pending.delete(id);
        error ? p.reject(new Error(error)) : p.resolve(result);
    });

    // Listen for poll results
    window.addEventListener('DAMUS_POLL_RESULT', (e) => {
        const { id, result, error } = e.detail;
        const p = pending.get(id);
        if (!p) return;
        pending.delete(id);
        error ? p.reject(new Error(error)) : p.resolve(result);
    });

    function request(method, params) {
        return new Promise((resolve, reject) => {
            const id = ++requestId;
            pending.set(id, { resolve, reject });
            window.dispatchEvent(new CustomEvent('DAMUS_REQUEST', {
                detail: { id, method, params }
            }));
            // 5 minute timeout for signing (user may be slow)
            setTimeout(() => {
                if (pending.has(id)) {
                    pending.delete(id);
                    reject(new Error('Timeout'));
                }
            }, 300000);
        });
    }

    // Handle URL opening action - extension couldn't open directly
    function handleOpenUrlAction(id, actionData) {
        const { url, requestId: extRequestId } = actionData;

        // Show user feedback before switching apps
        const notification = document.createElement('div');
        notification.style.cssText = `
            position: fixed;
            top: 20px;
            right: 20px;
            background: #1a1a2e;
            color: white;
            padding: 16px 24px;
            border-radius: 12px;
            z-index: 999999;
            font-family: -apple-system, BlinkMacSystemFont, sans-serif;
            box-shadow: 0 4px 12px rgba(0,0,0,0.3);
        `;
        notification.textContent = 'Opening Damus for signing...';
        document.body.appendChild(notification);

        // Open the URL to switch to Damus
        window.location.href = url;

        // Start polling for result when user returns
        // The content script will handle this
        window.dispatchEvent(new CustomEvent('DAMUS_START_POLL', {
            detail: { id, requestId: extRequestId }
        }));

        // Remove notification after a delay
        setTimeout(() => notification.remove(), 2000);
    }

    window.nostr = {
        async getPublicKey() {
            return request('getPublicKey', {});
        },

        async signEvent(event) {
            return request('signEvent', { event });
        },

        nip04: {
            async encrypt(pubkey, plaintext) {
                return request('nip04.encrypt', { pubkey, plaintext });
            },
            async decrypt(pubkey, ciphertext) {
                return request('nip04.decrypt', { pubkey, ciphertext });
            }
        },

        nip44: {
            async encrypt(pubkey, plaintext) {
                return request('nip44.encrypt', { pubkey, plaintext });
            },
            async decrypt(pubkey, ciphertext) {
                return request('nip44.decrypt', { pubkey, ciphertext });
            }
        },

        _damus: true
    };
})();
