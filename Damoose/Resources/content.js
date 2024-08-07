let script = document.createElement('script');
script.setAttribute('src', browser.runtime.getURL('nostr.js'));
document.body.appendChild(script);
console.log("Added Damoose the nostr helper to the page.")


function test_iframe() {
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

    // Function to show the iframe popup
    function toggle_popup() {
        if (iframe.style.display === 'block')
            iframe.style.display = 'none';
        else
            iframe.style.display = 'block';
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
        ];
        let { kind, reqId, payload } = message.data;
        if (!validEvents.includes(kind)) return;

        if (kind === 'popup_initialized') {
            // get all the queued requests for this host from the extension
            const requests = await browser.runtime.sendMessage({
                kind: 'requests',
                host: window.location.host,
            });

            if (browser.runtime.lastError)
                console.log(browser.runtime.lastError)

            // send initial requests
            iframe.contentWindow.postMessage({
                kind: 'requests',
                payload: requests,
            }, '*')
        } else {
            // window.nostr stuff
            const host = window.location.host
            const msg = {kind, payload, host}
            const result = await browser.runtime.sendMessage(msg)

            iframe.contentWindow.postMessage({
                kind: 'request',
                payload: msg,
            }, '*')

            console.log(result);

            kind = `return_${kind}`;

            window.postMessage({ kind, reqId, payload: result }, '*');
        }
    });
}

test_iframe()

