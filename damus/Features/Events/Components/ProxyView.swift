//
//  ProxyView.swift
//  damus
//
//  Created by eric on 2/3/24.
//

import SwiftUI

struct ProxyTag {
    let id: String
    let protocolName: String
    
    init(id: String, protocolName: String) {
        self.id = id
        self.protocolName = protocolName
    }
}

struct ProxyView: View {
    let event: NostrEvent
    
    @Environment(\.openURL) var openURL
    
    var body: some View {
        Group {
            if let proxy = event_proxy(ev: event) {
                VStack(alignment: .leading) {
                    Button(
                        action: {
                            if let url = URL(string: proxy.id) {
                                openURL(url)
                            }
                        },
                        label: {
                            HStack {
                                let protocolLogo = get_protocol_image(protocolName: proxy.protocolName)
                                if protocolLogo.isEmpty {
                                    Text(proxy.protocolName)
                                        .font(.caption)
                                } else {
                                    Image(protocolLogo)
                                        .resizable()
                                        .scaledToFit()
                                        .frame(width: proxy.protocolName == "activitypub" ? 75 : 20, height: proxy.protocolName == "activitypub" ? 20 : 25)
                                }
                            }
                        }
                    )
                    .buttonStyle(NeutralButtonStyle(padding: EdgeInsets(top: 2, leading: 5, bottom: 2, trailing: 5), cornerRadius: 20))
                }
            } else {
                EmptyView()
            }
        }
    }
}

func get_protocol_image(protocolName: String) -> String {
    switch protocolName {
    case "activitypub": return "activityPub"
    case "rss": return "rss"
    case "atproto": return "atproto"
    case "web": return "globe"
    default:
        return ""
    }
}

func event_proxy(ev: NostrEvent) -> ProxyTag? {
    var proxyParts = [String]()
    for tag in ev.tags {
        if tag.count == 3 && tag[0].matches_str("proxy") {
            proxyParts = tag.strings()
            guard proxyParts.count == 3 else {
                return nil
            }
            return ProxyTag(id: proxyParts[1], protocolName: proxyParts[2])
        }
    }
    return nil
}


struct ProxyView_Previews: PreviewProvider {
    static var previews: some View {
        let activityPubEv = NostrEvent(content: "", keypair: test_keypair, kind: 1, tags: [["proxy", "", "activitypub"]])!
        let atProtoEv = NostrEvent(content: "", keypair: test_keypair, kind: 1, tags: [["proxy", "", "atproto"]])!
        let rssEv = NostrEvent(content: "", keypair: test_keypair, kind: 1, tags: [["proxy", "", "rss"]])!
        let webEv = NostrEvent(content: "", keypair: test_keypair, kind: 1, tags: [["proxy", "", "web"]])!
        let unsupportedEv = NostrEvent(content: "", keypair: test_keypair, kind: 1, tags: [["proxy", "", "unsupported"]])!
        VStack(alignment: .center, spacing: 10) {
            ProxyView(event: activityPubEv)
            ProxyView(event: rssEv)
            ProxyView(event: atProtoEv)
            ProxyView(event: webEv)
            ProxyView(event: unsupportedEv)
        }
    }
}
