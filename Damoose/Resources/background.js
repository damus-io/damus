let damoose = {
    queue: {},
    reqids: 0,
}

function queue_request(d, kind, host, sendResponse) {
    const id = ++d.reqids
    if (d.queue[host] == null)
        d.queue[host] = []
    d.queue[host].push({kind, id, sendResponse})
}

browser.runtime.onMessage.addListener((message, _sender, sendResponse) => {
    switch (message.kind) {
        // window.nostr
        case 'getPubKey':
        case 'signEvent':
        case 'nip04.encrypt':
        case 'nip04.decrypt':
        case 'getRelays':
            queue_request(damoose, message.kind, message.host, sendResponse);
            return true;

        //
        // extension <-> page comms
        //
        // *requests*
        // The auth popup asks for the latest requests that we have
        // queued. This simply returns it to the tab/page in question.
        //
        case 'requests':
            const payload = {
                requests: damoose.queue[message.host] || [],
                host: message.host
            };
            return Promise.resolve(payload)

        default:
            return Promise.resolve();
    }
});



