//
//  nostr.js
//
//  Code from nostore
//


window.nostr = {
    requests: {},

    async getPublicKey() {
        return await this.broadcast('getPubKey');
    },

    async signEvent(event) {
        return await this.broadcast('signEvent', event);
    },

    async getRelays() {
        return await this.broadcast('getRelays');
    },

    // This is here for Alby comatibility. This is not part of the NIP-07 standard.
    // I have found at least one site, nostr.band, which expects it to be present.
    async enable() {
        return { enabled: true };
    },

    broadcast(kind, payload) {
        let reqId = Math.random().toString();
        return new Promise((resolve, _reject) => {
            this.requests[reqId] = resolve;
            window.postMessage({ kind, reqId, payload }, '*');
        });
    },

    nip04: {
        async encrypt(pubKey, plainText) {
            return await window.nostr.broadcast('nip04.encrypt', {
                pubKey,
                plainText,
            });
        },

        async decrypt(pubKey, cipherText) {
            return await window.nostr.broadcast('nip04.decrypt', {
                pubKey,
                cipherText,
            });
        },
    },
};


window.addEventListener('message', message => {
    const validEvents = [
        'getPubKey',
        'signEvent',
        'getRelays',
        'nip04.encrypt',
        'nip04.decrypt',
    ].map(e => `return_${e}`);
    let { kind, reqId, payload } = message.data;

    if (!validEvents.includes(kind)) return;

    window.nostr.requests[reqId]?.(payload);
    delete window.nostr.requests[reqId];
});

