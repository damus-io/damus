
let requests = []

window.addEventListener('message', message => {
    const { kind, reqId, payload } = message.data;
    if (kind === 'requests') {
        requests = requests.concat(payload.requests)
    } else if (kind === 'request') {
        requests.push(payload)
    }

    update_view(payload.host, requests)
});

function update_view(host, rs) {
    const reqs = document.getElementById("requests")
    const req_lis = rs.map(r => `<li>${r.kind}</li>`).join("\n")

    reqs.innerHTML = `
    <pre>${host}</pre> is requesting:
    <ul>
      ${req_lis}
    </ul>
    `
}

// let the page know the popup iframe is ready to receive nip07 requests for
// approval/disapproval
function popup_initialized() {
    window.parent.postMessage({ kind: "popup_initialized" }, '*');
}

function resolve_request(reqId, kind, payload) {
    window.parent.postMessage({ kind, reqId, payload }, '*');
}

popup_initialized()



