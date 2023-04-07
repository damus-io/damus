//
//  ZapDescription.swift
//  damus
//
//  Created by eric on 4/5/23.
//

import SwiftUI

struct ZapDescription: View {
    let event: NostrEvent
    
    var body: some View {
        (Text(Image(systemName: "bolt")) + Text(verbatim: "\(zap_desc(event: event))"))
            .font(.footnote)
            .foregroundColor(.gray)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ZapDescription_Previews: PreviewProvider {
    static var previews: some View {
        ZapDescription(event: test_event)
    }
}

func zap_desc(event: NostrEvent, locale: Locale = Locale.current) -> String {
    let desc = make_zap_description(event.tags)
    let zaptarget = desc.zaptarget

    let bundle = bundleForLocale(locale: locale)

    if desc.zaptarget.isEmpty {
        return ""
    }

    return String(format: NSLocalizedString("Zaps going to %@", bundle: bundle, comment: "Label to indicate that the zaps are being sent to user."), locale: locale, zaptarget)
}


