
let host_state = {
    requests: {},
    reqids: 0,
    approved: {},
}

function setup_nip07() {
    let script = document.createElement('script');
    script.setAttribute('src', browser.runtime.getURL('nostr.js'));
    document.body.appendChild(script);
    console.log("Added Damoose the nostr helper to the page.")
}

function queue_request(d, message) {
    d.requests[message.reqId] = message
}

function get_request(d, id) {
    return d.requests[id]
}

function setup_iframe() {
    const iframe = document.createElement('iframe');
    // Create an iframe for the secure popup
    iframe.src = browser.runtime.getURL('popup.html');  // Load the secure popup HTML
    iframe.style.position = 'fixed';
    iframe.style.bottom = '0';  // Align the iframe to the bottom of the screen
    iframe.style.left = '0';
    iframe.style.width = '100%';  // Make the iframe span the entire width of the screen
    iframe.style.height = '50%';  // Make the iframe cover the bottom half of the screen
    iframe.style.borderTop = '2px solid black';
    iframe.style.zIndex = '10000';  // Ensure it's on top of other elements
    iframe.style.display = 'none';  // Initially hidden
    iframe.style.backgroundColor = 'white';  // Opaque background

    // Add sandbox attributes to prevent host page access
    iframe.sandbox = 'allow-scripts allow-same-origin';

    // Append the iframe to the body
    document.body.appendChild(iframe);

    function show_popup() {
        iframe.style.display = 'block'
    }

    function hide_popup() {
        iframe.style.display = 'none'
    }

    // Function to show the iframe popup
    function toggle_popup() {
        if (iframe.style.display === 'block')
            hide_popup()
        else
            show_popup()
    }

    // Example trigger
    document.addEventListener('keydown', function(event) {
        if (event.key === 'o') {  // Press 'o' to show the iframe popup
            toggle_popup();
        }
    });

    window.addEventListener('message', async message => {
        const validEvents = [
            // window.nostr stuff
            'getPubKey',
            'signEvent',
            'getRelays',
            'nip04.encrypt',
            'nip04.decrypt',

            // plugin stuff
            'popup_initialized',
            'approve',
            'deny',
        ];
        let { kind, reqId, payload } = message.data;
        if (!validEvents.includes(kind)) return;

        if (kind === 'popup_initialized') {
            if (browser.runtime.lastError)
                console.log(browser.runtime.lastError)

            if (Object.keys(host_state.requests).length !== 0) {
                // send initial requests

                iframe.contentWindow.postMessage({
                    kind: 'requests',
                    host: window.location.host,
                    payload: host_state.requests,
                }, '*')

                show_popup()
            }
        } else if (kind === "approve" || kind === "deny") {
            // response from the iframe that we're approving or denying
            // a set of requests

            hide_popup()

            const result = await browser.runtime.sendMessage({ kind, reqId, payload})

            console.log("%s %s result:", kind, payload.kind, result);

            kind = `return_${payload.kind}`;
            window.postMessage({kind, reqId: payload.reqId, payload: result}, '*');

            console.log(`${kind} extension result: ${result}`)
        } else {
            queue_request(host_state, message.data)
            iframe.contentWindow.postMessage({
                kind: 'request',
                payload: message.data,
                host: window.location.host
            }, '*')

            show_popup()
        }
    });
}


// signer
//setup_nip07()
//setup_iframe()
setup_highlighter()

