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
            setTimeout(() => {
                if (pending.has(id)) {
                    pending.delete(id);
                    reject(new Error('Timeout'));
                }
            }, 300000);
        });
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
